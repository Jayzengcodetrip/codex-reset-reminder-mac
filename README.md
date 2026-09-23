# Codex Reset Reminder (CodexNotch)

A free, native Mac app that shows your Codex quota, weekly reset countdown, reset-credit expiry times, and public announcements of temporary resets.

[**Download the latest Mac release**](https://github.com/Jayzengcodetrip/codex-reset-reminder-mac/releases/latest) · [简体中文](README.zh-CN.md)

**Requirements:** macOS 14 or later, Apple Silicon (`arm64`), and a local Codex sign-in. This community app is not an official product of OpenAI, Codex, X, or NextReset.

## What it shows

- An announced temporary reset's Beijing-time target and live countdown when the public source provides a valid time. Multiple still-pending announcements retain separate countdowns. An announcement without a published time says that its time is unknown.
- New or materially changed announcements in macOS notifications while you are using the Mac; updates found after wake, unlock, or network recovery remain unread in the app.
- Remaining weekly quota, its reset time, available five-hour quota when returned by the account API, and each available reset credit's expiry when provided.
- A small notch or top-of-screen panel that expands on hover and can be hidden or restored with **Option–Command–N**.

The app checks the public source on launch and roughly every **two minutes** while running. Its first check establishes a quiet baseline for older announcements. It uses [NextReset](https://nextreset.net/)'s public API, not the paid X API. Delivery depends on the third-party source, connectivity, and polling; **a five-minute alert after an original X post is not guaranteed**. A posted target time is not proof that a reset has completed. Failed checks are shown as failures while previously saved announcements remain available.

## Install

1. Open [the Releases page](https://github.com/Jayzengcodetrip/codex-reset-reminder-mac/releases/latest) and download the `macOS-arm64` **DMG**, or the matching ZIP as an alternative.
2. Drag `CodexNotch.app` from the DMG into **Applications**. For a ZIP, unzip it first and then move the app into **Applications**.
3. Sign in to Codex on that Mac, then launch the app. It reads `~/.codex/auth.json` by default; a nonstandard Codex directory can be selected with `CODEX_HOME` before launch.
4. Allow notifications if you want desktop banners. The app offers a test notification. Launch at login is enabled by default and can be turned off in its settings; macOS may require approval under **System Settings → General → Login Items & Extensions**.

If you run the upstream CodexNotch or an earlier local build, quit it before launching this edition to avoid duplicate reminders. This edition has its own bundle identifier, so display preferences and login-item settings may need to be set again.

No Xcode or Swift installation is required for the downloaded app.

The current build is **ad-hoc signed, not Apple Developer ID signed or notarized**. If macOS blocks the first launch, verify that the file came from this repository's Release (the release includes `.sha256` checksums), try opening it, then use **System Settings → Privacy & Security → Open Anyway** and confirm. Do not disable macOS security checks globally. See [Apple's instructions](https://support.apple.com/en-gb/102445).

## Data and trust boundary

The app reads your local `CODEX_HOME/auth.json` token and sends it only to ChatGPT's usage and reset-credit endpoints (`chatgpt.com/backend-api/wham/usage` and `/rate-limit-reset-credits`). The public announcement requests to `https://nextreset.net/api/status` and `/api/resets` do **not** include that token. It reads local Codex session data for task activity and brief conversation titles. Public announcement history and unread flags are stored at `~/Library/Application Support/CodexNotch/reset-announcements.json`, without account tokens or quota responses. A manual update check reads public GitHub Release metadata.

ChatGPT usage endpoints are internal and may change. NextReset is an independent, third-party source that can lag or fail. Never post your `auth.json`, tokens, account ID, or private conversations in an issue.

## Build and license

On macOS 14+ with Xcode 15 / Swift 5.9 or newer:

```sh
swift test
./scripts/build_app.sh
./scripts/release.sh
```

The release script creates DMG and ZIP archives plus SHA-256 files. Script checks are not Apple notarization or a substitute for real-device notification and window testing.

This project is based on [fengdwx/codex-notch](https://github.com/fengdwx/codex-notch) **v0.1.16** and retains the original MIT copyright and license. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
