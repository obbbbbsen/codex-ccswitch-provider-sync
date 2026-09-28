# Codex / ccSwitch Provider Compatibility Watcher
# Event-driven, idempotent version with self-event suppression.
#
# Keeps both provider IDs available:
#   - custom
#   - cc-switch-official
#
# The inactive provider is maintained as an alias of the active provider.
# This script does NOT modify:
#   - state_5.sqlite
#   - thread/session history
#   - auth.json

$ConfigPath = Join-Path $env:USERPROFILE ".codex\config.toml"
$BackupDir  = Join-Path $env:USERPROFILE ".codex\provider-sync-backups"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Ignore filesystem notifications caused by this script's own writes.
$script:IgnoreEventsUntil = [datetime]::MinValue

function Get-ActiveProvider {
    param([string]$Text)

    $m = [regex]::Match(
        $Text,
        '(?m)^\s*model_provider\s*=\s*"([^"]+)"\s*$'
    )

    if ($m.Success) {
        return $m.Groups[1].Value
    }

    return $null
}

function Get-ProviderSection {
    param(
        [string]$Text,
        [string]$Provider
    )

    $escaped = [regex]::Escape($Provider)
    $pattern = "(?ms)^\[model_providers\.$escaped\]\s*\r?\n.*?(?=^\[|\z)"
    $m = [regex]::Match($Text, $pattern)

    if ($m.Success) {
        return $m.Value.TrimEnd("`r", "`n")
    }

    return $null
}

function Remove-ProviderSection {
    param(
        [string]$Text,
        [string]$Provider
    )

    $escaped = [regex]::Escape($Provider)
    $pattern = "(?ms)^\[model_providers\.$escaped\]\s*\r?\n.*?(?=^\[|\z)"

    return [regex]::Replace($Text, $pattern, "")
}

function Rename-ProviderSection {
    param(
        [string]$Section,
        [string]$OldName,
        [string]$NewName
    )

    $oldEscaped = [regex]::Escape($OldName)

    return [regex]::Replace(
        $Section,
        "(?m)^\[model_providers\.$oldEscaped\]",
        "[model_providers.$NewName]",
        1
    )
}

function Normalize-ProviderSection {
    param(
        [string]$Section,
        [string]$Provider
    )

    if ($null -eq $Section) {
        return $null
    }

    $escaped = [regex]::Escape($Provider)

    # Replace only the section header so sections with different provider IDs
    # can be compared by content.
    $normalized = [regex]::Replace(
        $Section,
        "(?m)^\[model_providers\.$escaped\]",
        "[model_providers.__provider__]",
        1
    )

    # Normalize line endings and trailing whitespace.
    $normalized = $normalized -replace "`r`n", "`n"
    $normalized = $normalized -replace "`r", "`n"

    $lines = $normalized -split "`n" | ForEach-Object {
        $_.TrimEnd()
    }

    return (($lines -join "`n").Trim())
}

function Test-ProviderSectionsEquivalent {
    param(
        [string]$Text,
        [string]$SourceProvider,
        [string]$TargetProvider
    )

    $source = Get-ProviderSection $Text $SourceProvider
    $target = Get-ProviderSection $Text $TargetProvider

    if (($null -eq $source) -or ($null -eq $target)) {
        return $false
    }

    $sourceNormalized = Normalize-ProviderSection $source $SourceProvider
    $targetNormalized = Normalize-ProviderSection $target $TargetProvider

    return ($sourceNormalized -eq $targetNormalized)
}

function Test-ProviderSectionExists {
    param(
        [string]$Text,
        [string]$Provider
    )

    return ($null -ne (Get-ProviderSection $Text $Provider))
}

function Backup-Config {
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $backupPath = Join-Path $BackupDir "config-$stamp.toml"

    Copy-Item $ConfigPath $backupPath -Force

    # Keep only the newest 20 backups.
    Get-ChildItem $BackupDir -File -Filter "config-*.toml" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 20 |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-ConfigSafely {
    param([string]$Text)

    Backup-Config

    $tempPath = "$ConfigPath.provider-sync.tmp"

    try {
        [System.IO.File]::WriteAllText(
            $tempPath,
            $Text,
            $Utf8NoBom
        )

        $verify = [System.IO.File]::ReadAllText($tempPath)

        if (-not (Test-ProviderSectionExists $verify "custom")) {
            throw "Verification failed: [model_providers.custom] is missing."
        }

        if (-not (Test-ProviderSectionExists $verify "cc-switch-official")) {
            throw "Verification failed: [model_providers.cc-switch-official] is missing."
        }

        # Suppress events caused by our own replacement.
        $script:IgnoreEventsUntil = (Get-Date).AddSeconds(2)

        Move-Item $tempPath $ConfigPath -Force
    }
    finally {
        if (Test-Path $tempPath) {
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Wait-ForStableConfig {
    param(
        [int]$MaxAttempts = 15,
        [int]$DelayMs = 200
    )

    $previousLength = -1
    $previousWrite  = [datetime]::MinValue
    $stableHits     = 0

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        if (-not (Test-Path $ConfigPath)) {
            Start-Sleep -Milliseconds $DelayMs
            continue
        }

        try {
            $item = Get-Item $ConfigPath -ErrorAction Stop

            if (
                $item.Length -eq $previousLength -and
                $item.LastWriteTimeUtc -eq $previousWrite
            ) {
                $stableHits++

                # Two consecutive stable observations.
                if ($stableHits -ge 2) {
                    return $true
                }
            }
            else {
                $stableHits = 0
            }

            $previousLength = $item.Length
            $previousWrite  = $item.LastWriteTimeUtc
        }
        catch {
            $stableHits = 0
        }

        Start-Sleep -Milliseconds $DelayMs
    }

    return $false
}

function Sync-CodexProviders {
    if (-not (Test-Path $ConfigPath)) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') config.toml not found."
        return
    }

    try {
        $stable = Wait-ForStableConfig

        if (-not $stable) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') config.toml did not become stable; skipped."
            return
        }

        $text = [System.IO.File]::ReadAllText($ConfigPath)
        $active = Get-ActiveProvider $text

        if ([string]::IsNullOrWhiteSpace($active)) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') No active model_provider found."
            return
        }

        if ($active -eq "custom") {
            $source = Get-ProviderSection $text "custom"

            if ($null -eq $source) {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') Missing [model_providers.custom]."
                return
            }

            # Idempotency: if both sections already contain the same settings,
            # do nothing and do not touch the file.
            if (Test-ProviderSectionsEquivalent $text "custom" "cc-switch-official") {
                return
            }

            $alias = Rename-ProviderSection $source "custom" "cc-switch-official"
            $newText = Remove-ProviderSection $text "cc-switch-official"
            $newText = $newText.TrimEnd() + "`r`n`r`n" + $alias + "`r`n"

            Write-ConfigSafely $newText
            Write-Host "$(Get-Date -Format 'HH:mm:ss') Synced custom -> cc-switch-official"
            return
        }

        if ($active -eq "cc-switch-official") {
            $source = Get-ProviderSection $text "cc-switch-official"

            if ($null -eq $source) {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') Missing [model_providers.cc-switch-official]."
                return
            }

            # Idempotency: if both sections already contain the same settings,
            # do nothing and do not touch the file.
            if (Test-ProviderSectionsEquivalent $text "cc-switch-official" "custom") {
                return
            }

            $alias = Rename-ProviderSection $source "cc-switch-official" "custom"
            $newText = Remove-ProviderSection $text "custom"
            $newText = $newText.TrimEnd() + "`r`n`r`n" + $alias + "`r`n"

            Write-ConfigSafely $newText
            Write-Host "$(Get-Date -Format 'HH:mm:ss') Synced cc-switch-official -> custom"
            return
        }

        Write-Host "$(Get-Date -Format 'HH:mm:ss') Provider '$active' ignored."
    }
    catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') ERROR:"
        Write-Host $_.Exception.Message
    }
}

if (-not (Test-Path $ConfigPath)) {
    Write-Host "config.toml not found:"
    Write-Host $ConfigPath
    exit 1
}

$ConfigDir  = Split-Path $ConfigPath
$ConfigName = Split-Path $ConfigPath -Leaf

$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = $ConfigDir
$Watcher.Filter = $ConfigName
$Watcher.NotifyFilter = (
    [System.IO.NotifyFilters]::LastWrite -bor
    [System.IO.NotifyFilters]::Size -bor
    [System.IO.NotifyFilters]::FileName -bor
    [System.IO.NotifyFilters]::CreationTime
)
$Watcher.EnableRaisingEvents = $true

Write-Host ""
Write-Host "Codex ccSwitch provider sync started."
Write-Host "Config: $ConfigPath"
Write-Host "Mode: FileSystemWatcher + idempotency + self-event suppression"
Write-Host "Watching custom <-> cc-switch-official"
Write-Host "Backups: $BackupDir"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

# Initial sync.
Sync-CodexProviders

try {
    while ($true) {
        $result = $Watcher.WaitForChanged(
            [System.IO.WatcherChangeTypes]::All,
            60000
        )

        if ($result.TimedOut) {
            continue
        }

        # Ignore notifications caused by this script itself.
        if ((Get-Date) -lt $script:IgnoreEventsUntil) {
            continue
        }

        # Debounce external changes and let ccSwitch finish writing.
        Start-Sleep -Milliseconds 500

        # Check again in case an event arrived while our previous write
        # was still inside the suppression window.
        if ((Get-Date) -lt $script:IgnoreEventsUntil) {
            continue
        }

        Sync-CodexProviders
    }
}
finally {
    $Watcher.EnableRaisingEvents = $false
    $Watcher.Dispose()
}
