# Codex Reset Reminder (CodexNotch)

A free, native Mac app that shows your Codex quota, weekly reset countdown, reset-credit expiry times, and public announcements of temporary resets.

[**Download the latest Mac release**](https://github.com/Jayzengcodetrip/codex-reset-reminder-mac/releases/latest) · [简体中文](README.zh-CN.md)

**Requirements:** macOS 14 or later, Apple Silicon (`arm64`), and a local Codex sign-in. This community app is not an official product of OpenAI, Codex, X, or NextReset.

## What it shows

- For a date-only or weekday-only temporary-reset announcement such as “Tuesday”, the app shows three phases in the Los Angeles reference time zone: a seconds-level countdown from the post until Tuesday `00:00:00`, the **earliest possible window**; a new seconds-level countdown for Tuesday itself, ending at Wednesday `00:00:00`; then return the top card to “No new reset announcements”, retaining the unresolved record in history. At Monday `23:59:59` the first countdown has one second left; at Tuesday `23:59:59` the second has one second left. These are calendar estimates, not published reset minutes. **Neither countdown is a recommendation to use up your quota: if the reset is delayed, spending everything early could leave you without quota while you wait.** A live Los Angeles clock shows only the weekday and 24-hour `HH:mm:ss` while the preview card is visible and in pending record details. A macOS notification labels its fixed clock snapshot “Los Angeles at notification”; the card and detail clocks are live. During a countdown, Beijing is shown only as the corresponding cutoff weekday, without an estimated clock time. Explicitly timed announcements count down to their stated time; multiple pending announcements keep independent phases. An announcement without a usable date says that its time is unknown.
- New or materially changed announcements in macOS notifications while you are using the Mac; updates found after wake, unlock, or network recovery remain unread in the app.
- Source-evidence wording and richer details about the same known delivery are saved quietly. History stays in publication order, with unread updates available in their own filter.
- Remaining weekly quota, its reset time, available five-hour quota when returned by the account API, and each available reset credit's expiry when provided.
- A small notch or top-of-screen panel that expands on hover and can be hidden or restored with **Option–Command–N**.

The app checks the public source on launch and roughly every **two minutes** while running. Its first check establishes a quiet baseline for older announcements. It uses [NextReset](https://nextreset.net/) for public announcements, [Codex Resets](https://codex-resets.com/) for official post text, and [NextReset.org](https://nextreset.org/) for linked event evidence. No paid X API key is needed. Delivery depends on the third-party source, connectivity, and polling; **a five-minute alert after an original X post is not guaranteed**. Los Angeles is an app reference time zone, not an official reset time zone. The Tuesday start and end boundaries are estimates, not published execution times; the first countdown is measured from the original post time even if the source is checked later. Passing either estimate does not prove that a reset has completed. Failed checks are shown as failures while previously saved announcements remain available.

When the official post announces that a direct reset or banked-reset distribution has started, the matching countdown ends. With no other active preview, the card says **“No new reset announcements (reset delivered today)”** until Los Angeles midnight. Thereafter, the empty card includes the elapsed time since the latest known general delivery, updating every second as `HH:mm:ss` or `Nd HH:mm:ss`. Without a known delivery time, no elapsed value is invented. This means official rollout has started, not that every account has received it. Explicit source relations take precedence. Otherwise, only a unique compatible announcement on the same Los Angeles target day can be matched; details disclose this inference. Ambiguous matches or targeted compensation are not used to close a broad preview. Expiry only hides the card; account refreshes and credit-count changes do not establish delivery. Stored evidence survives auxiliary-source failures.

## Install

1. Open [the Releases page](https://github.com/Jayzengcodetrip/codex-reset-reminder-mac/releases/latest) and download the `macOS-arm64` **DMG**, or the matching ZIP as an alternative.
2. Drag `CodexNotch.app` from the DMG into **Applications**. For a ZIP, unzip it first and then move the app into **Applications**.
3. Sign in to Codex on that Mac, then launch the app. It reads `~/.codex/auth.json` by default; a nonstandard Codex directory can be selected with `CODEX_HOME` before launch.
4. Allow notifications if you want desktop banners. The app offers a test notification. Launch at login is enabled by default and can be turned off in its settings; macOS may require approval under **System Settings → General → Login Items & Extensions**.

If you run the upstream CodexNotch or an earlier local build, quit it before launching this edition to avoid duplicate reminders. This edition has its own bundle identifier, so display preferences and login-item settings may need to be set again.

No Xcode or Swift installation is required for the downloaded app.

The current build is **ad-hoc signed, not Apple Developer ID signed or notarized**. If macOS blocks the first launch, verify that the file came from this repository's Release (the release includes `.sha256` checksums), try opening it, then use **System Settings → Privacy & Security → Open Anyway** and confirm. Do not disable macOS security checks globally. See [Apple's instructions](https://support.apple.com/en-gb/102445).

## Data and trust boundary

The app reads your local `CODEX_HOME/auth.json` token and sends it only to ChatGPT's usage and reset-credit endpoints (`chatgpt.com/backend-api/wham/usage` and `/rate-limit-reset-credits`). The public announcement requests to `https://nextreset.net/api/status` and `/api/resets`, plus `https://codex-resets.com/api/v1/resets?limit=100` and `https://nextreset.org/api/v1/events.json`, do **not** include that token. It reads local Codex session data for task activity and brief conversation titles. Public announcement history and unread flags are stored at `~/Documents/Codex/QuotaReminderState/announcements.json`, without account tokens or quota responses. A manual update check reads public GitHub Release metadata.

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
