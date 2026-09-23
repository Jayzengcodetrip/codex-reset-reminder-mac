# Codex 重置提醒（CodexNotch）

一款免费的原生 Mac 小应用：查看 Codex 剩余额度、每周重置倒计时和重置券到期时间，并在公开来源出现新的临时重置预告时提醒你。

[**下载最新版**](https://github.com/Jayzengcodetrip/codex-reset-reminder-mac/releases/latest) · [查看源码](https://github.com/Jayzengcodetrip/codex-reset-reminder-mac) · [English](README.md)

> 适用于 **macOS 14 或更新版本、Apple Silicon（arm64）Mac**。这是社区制作的应用，不是 OpenAI、Codex、X 或 NextReset 的官方产品。

## 它能做什么

| 你想知道的 | 应用显示的内容 |
| --- | --- |
| 临时重置什么时候来 | 公开接口有预告时间时，在窗口里显示**北京时间和剩余倒计时**；有两条尚未完成的预告时，两条都保留。没有公布时间时，明确显示时间待公布。 |
| 有没有新预告 | 检查完成后显示检查结果；有新公告或实质更新时保留公告记录。在电脑使用期间收到更新，可通过 macOS 通知提醒。 |
| 本周额度还有多少 | 展示账户接口返回的周额度百分比、重置时刻和倒计时；接口提供五小时额度时一并展示。 |
| 重置券有几张、何时到期 | 展示可用次数；展开后查看接口返回的每张重置券到期时间。 |

应用启动时检查一次，此后运行期间约每 **2 分钟**检查公开接口；睡眠唤醒、解锁或网络恢复后会补查。你不在电脑前发现的更新会留在窗口的未读记录中。第一次启动会建立安静的历史基线，不会把既有旧公告全部弹成新通知。窗口可通过鼠标移到屏幕顶部展开，也可用 **⌥⌘N** 收起或恢复。退出应用后，检查也会停止。

提醒依据 [NextReset](https://nextreset.net/) 的公开数据，并非直接读取 X 的付费实时 API。**提醒速度取决于站方何时捕获和发布消息、网络连接以及本机轮询时间；无法保证 Tibo 发布后五分钟内必达。**界面里的预告时间属于来源给出的时间，不等于官方执行完成的证明。若接口暂时不可用，应用会保留已取得的记录并提示检查失败，不会把旧记录伪装成刚刚确认的新预告。

## 安装

1. 在 [GitHub Releases 下载页](https://github.com/Jayzengcodetrip/codex-reset-reminder-mac/releases/latest)下载名称含 `macOS-arm64` 的 **DMG**。如果不方便使用 DMG，也可以下载同版 **ZIP**。
2. 打开 DMG，把 `CodexNotch.app` 拖进“应用程序”；ZIP 则先解压，再把应用移进“应用程序”。安装后请从该位置启动，方便登录后自动启动功能正常工作。
3. 先在这台 Mac 上登录并使用 Codex。应用会读取本机 `~/.codex/auth.json`；若你的 Codex 目录不同，需要在启动应用前设置 `CODEX_HOME`。
4. 第一次启动时，按需允许系统通知。想收到桌面弹窗，还要在 macOS 的“系统设置 → 通知”里允许本应用显示横幅。应用设置里有“测试通知”，可用于检查系统通知是否送达。

如果已运行原版 CodexNotch 或此前的本地定制版，请先退出旧应用，避免两份程序同时提醒。本公开版使用独立应用标识，原来的显示偏好与登录项可能需要重新设置。

无需安装 Xcode、Swift 或命令行工具。应用默认尝试注册“登录后自动启动”，你可以在应用设置中关闭；macOS 也可能要求你在“系统设置 → 通用 → 登录项与扩展”中允许它。

**首次打开被 macOS 拦下？** 当前安装包使用 ad-hoc 签名，**尚未经过 Apple Developer ID 签名及公证**。请先确认你下载的是本仓库的 Release，必要时对照随包提供的 `.sha256` 文件。尝试打开应用后，到“系统设置 → 隐私与安全性”找到“仍要打开 / Open Anyway”，再确认打开。这是针对该应用的单次例外；不要为此全局关闭 macOS 安全检查。步骤参见 [Apple 官方说明](https://support.apple.com/en-gb/102445)。

## 看懂提醒

- **临时重置预告**：有确切的未来时间时显示北京时刻与倒计时。公告被标记为完成或取消后，不再继续显示过时倒计时；单纯点开、标记已读或预定时刻经过，不会擅自把预告判作完成。
- **“已检查接口，暂无新重置预告”**：表示这一轮检查没有发现新的预告，**不代表之前尚未完成的预告消失**；已有倒计时仍会显示。检查正在进行或失败时，界面会显示对应状态。
- **本周重置和重置券**：来自你自己的账户数据，与临时福利预告是不同信息。重置券的可用次数与到期时间可能因账户接口状态而暂时缺失；不要把临时重置预告等同于获得了一张重置券。

## 数据与隐私

| 数据 | 读取位置 / 请求地址 | 用途 |
| --- | --- | --- |
| Codex 登录令牌与账户 ID | 本机 `CODEX_HOME/auth.json`，默认 `~/.codex/auth.json` | 仅用于请求 `chatgpt.com/backend-api/wham/usage` 和 `chatgpt.com/backend-api/wham/rate-limit-reset-credits`。 |
| 公开预告 | `https://nextreset.net/api/status` 与 `https://nextreset.net/api/resets` | 检查预告、更新和状态；请求**不附带 Codex 登录令牌**。 |
| 任务活动与最近对话标题 | 本机 Codex sessions 文件和 `state_5.sqlite` | 展示本机任务状态与简短标题。 |
| 已读和公告历史 | 本机 `~/Library/Application Support/CodexNotch/reset-announcements.json` | 重启后保留公开公告及未读状态；不包含账户令牌或额度响应。 |
| 手动检查应用更新 | GitHub 公开 Release 元数据 | 仅在手动检查时读取版本信息。 |

账户额度使用 ChatGPT 的内部接口，接口结构和可用性可能变化。请不要在 issue、截图或日志中上传 `auth.json`、令牌、账户 ID 或私人对话内容。应用不提供云同步、远程推送，也不需要付费 X API。

## 从源码构建

需要 macOS 14+、Xcode 15 / Swift 5.9 或更新版本：

```sh
swift test
./scripts/build_app.sh
open dist/CodexNotch.app
```

创建待分发的 DMG、ZIP 与各自的 SHA-256 文件：

```sh
./scripts/release.sh
```

发布脚本会运行测试、构建应用并检查签名与磁盘映像。通过脚本检查不等于苹果公证，也不能替代在真实 Mac 上验证通知、睡眠唤醒、悬停窗口和安装体验。

## 来源与许可

本项目基于 [fengdwx/codex-notch](https://github.com/fengdwx/codex-notch) 的 **v0.1.16** 源码继续开发，保留了原作者的 MIT 许可与版权声明。这里的临时重置公告、倒计时及相关交互是后续扩展。详见 [LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。
