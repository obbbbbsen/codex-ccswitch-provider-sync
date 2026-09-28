# Codex + ccSwitch Provider Sync

一个面向 Windows 的轻量 PowerShell 工具，用于在 ccSwitch 切换线路后，自动同步 Codex Desktop 的 `custom` 与 `cc-switch-official` Provider 配置。

它解决了因历史会话保存了不同 `model_provider`，导致切换官方账号或中转线路后旧会话无法继续的问题。

## 特点

- 实时监听 `~/.codex/config.toml` 变化
- 自动维护两个兼容的 Provider 别名
- 修改前自动备份配置，最多保留 20 份
- 幂等同步，避免无意义写入和事件循环
- 不修改会话数据库、历史记录或 `auth.json`

## 快速使用

将 `codex-provider-sync.ps1` 放入：

```text
%USERPROFILE%\.codex\
```

然后在 PowerShell 中运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "$env:USERPROFILE\.codex\codex-provider-sync.ps1"
```

脚本运行后，在 ccSwitch 中切换线路即可自动同步 Provider 配置。推荐先退出 Codex Desktop，完成切换并等待数秒后再重新打开。

计划任务配置、备份恢复及故障排查请参阅[完整使用文档](docs/使用文档.md)。

## 注意事项

- 仅支持 Windows PowerShell 环境。
- 使用前建议自行备份 `config.toml`。
- 本项目不会上传或收集任何本地配置、令牌及账户信息。

## 开源许可

本项目基于 [MIT License](LICENSE) 开源。
