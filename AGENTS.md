# Codex 重置提醒 · 公开源码

CodexNotch 是 SwiftUI 和 AppKit 编写的 macOS 14+ 辅助应用。公开版本支持 Apple Silicon。产品版本和构建号见 `Resources/Info.plist`，用户指南见 [中文 README](README.zh-CN.md)，本版改动见 [v0.2.18 发布说明](docs/releases/v0.2.18.md)。

## 源码与验证

- `Sources/CodexNotch/App/`、`UI/`、`Window/` 分别负责运行调度、界面和顶部窗口。实际窗口交互需要在 Mac 上验证。
- `Sources/CodexNotch/Announcements/` 负责公开预告、历史、通知与计时。公开发放、账户到账、人工确认、手动收起和独立重新计时各自保存。手动收起仅影响首页和「待定」，历史可恢复。保留旧账本及各项人工时间戳。
- `Sources/CodexNotch/Usage/` 负责账户额度与重置券。账户凭证仅用于账户接口，查询公开公告使用匿名请求。测试使用合成数据及临时账本。
- 查看相关 `Tests/CodexNotchTests/`、`docs/contracts/behavior-contracts.yaml` 和 `docs/decisions/` 后再改功能。在 macOS 上运行 `./scripts/check_contracts.sh`、`python3 scripts/test_prune_release_artifacts.py` 和 `./scripts/verify.sh`。构建后的可执行文件支持 `--verify-reset-behavior` 与 `--verify-window-restoration`。
- 发布说明放在 `docs/releases/v<版本>.md`。GitHub 的 macOS 工作流运行测试后，从同一份源码生成 DMG、ZIP 与 SHA-256 校验文件。正式发布须经项目所有者授权。Apple 公证状态、系统通知和全新 Mac 的安装体验按实际验证情况说明。
- 保留上游 MIT 许可及 `NOTICE.md` 署名。提交或发布前核对文件，排除本机凭证、账户资料、私人会话、真实账本与个人备份。
