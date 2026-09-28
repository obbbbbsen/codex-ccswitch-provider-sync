# Codex + ccSwitch Provider Sync 使用文档

## 1. 作用

本方案用于解决 Codex Desktop 与 ccSwitch 切换官方账号 / 中转站时，历史会话因为 `model_provider` 不同而无法继续的问题。

当前脚本会保证 `config.toml` 中同时存在：

```toml
[model_providers.custom]

[model_providers.cc-switch-official]
```

并让两者都指向 ccSwitch 当前选中的实际线路。

这样，无论历史会话保存的是：

```text
model_provider = custom
```

还是：

```text
model_provider = cc-switch-official
```

都可以正常找到对应 Provider。

---

## 2. 关键文件位置

### Provider 同步脚本

```text
$env:USERPROFILE\.codex\codex-provider-sync.ps1
```

### Codex 配置文件

```text
$env:USERPROFILE\.codex\config.toml
```

### 自动备份目录

```text
$env:USERPROFILE\.codex\provider-sync-backups
```

脚本最多保留最近 20 份 `config.toml` 备份。

### Codex 本地线程数据库

```text
$env:USERPROFILE\.codex\state_5.sqlite
```

当前同步脚本不会修改该数据库。

---

# 3. 手动运行脚本

如果需要手动启动 Provider watcher：

```powershell
Set-Location "$env:USERPROFILE\.codex"
Set-ExecutionPolicy -Scope Process Bypass
.\codex-provider-sync.ps1
```

正常输出类似：

```text
Codex ccSwitch provider sync started.
Config: <用户主目录>\.codex\config.toml
Mode: FileSystemWatcher + idempotency + self-event suppression
Watching custom <-> cc-switch-official
Backups: <用户主目录>\.codex\provider-sync-backups
Press Ctrl+C to stop.
```

停止手动运行的脚本：

```text
Ctrl + C
```

---

# 4. 注册为 Windows 登录自启任务

建议用“任务计划程序”实现后台自启。

以管理员 PowerShell 执行：

```powershell
$Action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$env:USERPROFILE\.codex\codex-provider-sync.ps1`""

$Trigger = New-ScheduledTaskTrigger -AtLogOn

$Principal = New-ScheduledTaskPrincipal `
  -UserId "$env:USERDOMAIN\$env:USERNAME" `
  -LogonType Interactive `
  -RunLevel Limited

Register-ScheduledTask `
  -TaskName "Codex ccSwitch Provider Sync" `
  -Action $Action `
  -Trigger $Trigger `
  -Principal $Principal `
  -Description "Keeps Codex custom and cc-switch-official provider aliases synchronized." `
  -Force
```

任务名称：

```text
Codex ccSwitch Provider Sync
```

以后 Windows 登录时会自动在后台运行。

---

# 5. 查询任务是否已经注册

```powershell
Get-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

只看名称和状态：

```powershell
Get-ScheduledTask -TaskName "Codex ccSwitch Provider Sync" |
Select-Object TaskName, State
```

常见状态：

```text
Ready
```

表示任务已注册，目前没有运行。

```text
Running
```

表示 watcher 正在后台运行。

---

# 6. 查看任务运行信息

```powershell
Get-ScheduledTaskInfo -TaskName "Codex ccSwitch Provider Sync"
```

可能看到：

```text
LastRunTime
LastTaskResult
NextRunTime
NumberOfMissedRuns
```

如果：

```text
LastTaskResult : 267011
```

对应：

```text
0x41303 = SCHED_S_TASK_HAS_NOT_RUN
```

意思只是：

> 任务已经注册，但还从未运行。

这不是报错。

由于该任务使用 `AtLogOn` 登录触发器，因此刚注册完成时 `NextRunTime` 为空也是正常的。

---

# 7. 立即手动启动后台任务

不需要重新登录 Windows，可以直接执行：

```powershell
Start-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

然后查看状态：

```powershell
Get-ScheduledTask -TaskName "Codex ccSwitch Provider Sync" |
Select-Object TaskName, State
```

正常应为：

```text
Running
```

---

# 8. 停止后台任务

```powershell
Stop-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

再次检查：

```powershell
Get-ScheduledTask -TaskName "Codex ccSwitch Provider Sync" |
Select-Object TaskName, State
```

通常会变成：

```text
Ready
```

---

# 9. 重启后台任务

如果修改了脚本，或者怀疑 watcher 状态异常，可以执行：

```powershell
Stop-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
Start-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

然后检查：

```powershell
Get-ScheduledTask -TaskName "Codex ccSwitch Provider Sync" |
Select-Object TaskName, State
```

---

# 10. 删除自启任务

如果以后不再需要：

```powershell
Unregister-ScheduledTask `
  -TaskName "Codex ccSwitch Provider Sync" `
  -Confirm:$false
```

删除后检查：

```powershell
Get-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

如果提示找不到任务，说明已经删除成功。

注意：

> 删除计划任务不会删除 `codex-provider-sync.ps1` 脚本文件。

如果连脚本也想删除：

```powershell
Remove-Item "$env:USERPROFILE\.codex\codex-provider-sync.ps1"
```

---

# 11. 更新脚本

只要脚本路径保持不变：

```text
$env:USERPROFILE\.codex\codex-provider-sync.ps1
```

就不需要重新注册任务。

更新脚本后只需要：

```powershell
Stop-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
Start-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

即可加载新版。

---

# 12. 检查 Provider 同步是否正常

执行：

```powershell
Select-String `
  "$env:USERPROFILE\.codex\config.toml" `
  -Pattern 'model_provider|^\[model_providers\.'
```

正常情况下，无论当前 ccSwitch 选的是官方还是中转站，都应该同时看到：

```text
model_provider = "custom"
```

或者：

```text
model_provider = "cc-switch-official"
```

以及：

```text
[model_providers.custom]
[model_providers.cc-switch-official]
```

关键不是顶层 `model_provider` 是谁，而是两个 Provider section 必须同时存在。

---

# 13. 检查两个 Provider 当前指向哪里

执行：

```powershell
Get-Content "$env:USERPROFILE\.codex\config.toml" |
Select-String -Pattern '^\[model_providers\.|^base_url|^requires_openai_auth|^experimental_bearer_token'
```

在中转站模式下，两个 Provider 通常都会指向：

```text
http://127.0.0.1:15721/v1
```

在官方模式下，两者则会同步为当前官方线路配置。

---

# 14. ccSwitch 推荐切换流程

为避免 Codex Desktop 缓存旧 Provider，建议：

```text
1. 完全退出 Codex Desktop
2. 在 ccSwitch 中切换官方 / 中转站
3. 等待 1~3 秒，让 watcher 完成 config.toml 同步
4. 再打开 Codex Desktop
```

不要在 Codex 运行过程中频繁切换 Provider。

---

# 15. 为什么历史会话里会同时存在两种 Provider

可以查看：

```powershell
$db = "$env:USERPROFILE\.codex\state_5.sqlite"

sqlite3 $db "SELECT model_provider, COUNT(*) AS count FROM threads GROUP BY model_provider ORDER BY count DESC;"
```

示例输出：

```text
cc-switch-official|12
custom|8
```

这是正常现象。

历史线程会保留创建或迁移时的 Provider ID，例如：

```text
Thread A -> cc-switch-official
Thread B -> custom
```

打开旧线程时，并不会自动把它改成当前 Provider。

同步脚本的作用就是：

```text
cc-switch-official thread
        \
         -> 当前 ccSwitch 线路
        /
custom thread
```

因此没有必要强制修改所有历史线程。

---

# 16. 脚本不会修改什么

当前脚本不会修改：

```text
state_5.sqlite
```

不会修改：

```text
历史 rollout JSONL
```

不会修改：

```text
auth.json
```

也不会修改历史线程的：

```text
model_provider
```

它只负责维护：

```text
$env:USERPROFILE\.codex\config.toml
```

中的两个 Provider alias。

因此出现问题时，影响范围通常只限于 `config.toml`。

---

# 17. 自动备份

每次脚本真正需要修改 `config.toml` 时，会先备份到：

```text
$env:USERPROFILE\.codex\provider-sync-backups
```

查看备份：

```powershell
Get-ChildItem "$env:USERPROFILE\.codex\provider-sync-backups" |
Sort-Object LastWriteTime -Descending
```

脚本最多保留最近 20 个备份。

---

# 18. 恢复 config.toml 备份

先完全退出 Codex 和 watcher。

查看最近备份：

```powershell
Get-ChildItem "$env:USERPROFILE\.codex\provider-sync-backups" |
Sort-Object LastWriteTime -Descending |
Select-Object -First 10 Name, FullName, LastWriteTime
```

选择一个正常版本后：

```powershell
Copy-Item `
  "备份文件完整路径" `
  "$env:USERPROFILE\.codex\config.toml" `
  -Force
```

然后重新启动 watcher。

---

# 19. 常用命令速查

## 启动

```powershell
Start-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

## 停止

```powershell
Stop-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

## 查看状态

```powershell
Get-ScheduledTask -TaskName "Codex ccSwitch Provider Sync" |
Select-Object TaskName, State
```

## 查看详细运行信息

```powershell
Get-ScheduledTaskInfo -TaskName "Codex ccSwitch Provider Sync"
```

## 重启

```powershell
Stop-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
Start-ScheduledTask -TaskName "Codex ccSwitch Provider Sync"
```

## 删除自启任务

```powershell
Unregister-ScheduledTask `
  -TaskName "Codex ccSwitch Provider Sync" `
  -Confirm:$false
```

## 检查 Provider

```powershell
Select-String `
  "$env:USERPROFILE\.codex\config.toml" `
  -Pattern 'model_provider|^\[model_providers\.'
```

## 统计历史线程 Provider

```powershell
$db = "$env:USERPROFILE\.codex\state_5.sqlite"

sqlite3 $db "SELECT model_provider, COUNT(*) AS count FROM threads GROUP BY model_provider ORDER BY count DESC;"
```

---

# 20. 推荐日常使用方式

正常情况下，不需要每天执行任何命令。

Windows 登录后：

```text
任务计划程序
        ↓
自动启动 codex-provider-sync.ps1
        ↓
FileSystemWatcher 后台等待
```

当 ccSwitch 切换线路：

```text
ccSwitch 修改 config.toml
        ↓
FileSystemWatcher 收到事件
        ↓
自动同步另一个 Provider alias
        ↓
完成
```

日常只需要：

```text
关闭 Codex
→ ccSwitch 切换
→ 等 1~3 秒
→ 打开 Codex
```

即可。
