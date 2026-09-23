# Project handoff for contributors and coding agents

## Purpose and provenance

This is the public source for Codex Reset Reminder, whose application bundle is still named `CodexNotch.app`. It extends [fengdwx/codex-notch](https://github.com/fengdwx/codex-notch) v0.1.16 under MIT. Preserve the original copyright and permission text in `LICENSE` and the attribution in `NOTICE.md`.

The product has three distinct data domains. Do not infer a temporary benefit reset from an account's ordinary weekly reset time or from reset-credit count.

1. **Account quota**: local Codex credentials from `CODEX_HOME/auth.json` (default `~/.codex/auth.json`) are sent only to ChatGPT usage and reset-credit endpoints.
2. **Public temporary reset announcements**: unauthenticated GET requests to NextReset `/api/status` and `/api/resets`; no Codex token, account ID, or private conversation content may be sent there.
3. **Local activity**: Codex session files and the local state database support the task/status UI.

## Product behavior to preserve

- Check the public source at launch and about every 120 seconds while the app runs; catch up after sleep, unlock, and network recovery. A failure must not be presented as a successful check.
- First-run archive discovery establishes a quiet baseline. New or materially updated announcements during active use can produce a macOS notification; updates found while away remain visible and unread in the app.
- Keep every independently pending announcement. For a weekday-only announcement such as “Tuesday”, use Los Angeles calendar boundaries for three phases: from the post time until Tuesday 00:00:00, count down to the start of the earliest possible window; during Tuesday, count down to Wednesday 00:00:00 (Tuesday 23:59:59 still has one second); from Wednesday 00:00:00 onward, show no countdown, use “预告日已过 · 等待确认”, and wait for confirmation. Both phase boundaries are estimates, not official exact reset times. Neither countdown advises users to exhaust their quota: if execution is delayed, using it all early leaves no quota while waiting. A delayed source check must enter the phase appropriate to the current time without moving the original post time. While pending, always show the live Los Angeles weekday and 24-hour `HH:mm:ss` without month or day, including after both countdowns end. A macOS notification's clock is a snapshot labelled “通知时洛杉矶”, not a live clock; the card and detail use “洛杉矶现在”. Beijing shows only the corresponding cutoff weekday during a countdown, never an estimated clock time. Explicitly timed announcements keep their exact deadline. Read/unread state or elapsed target time alone must not remove one; use explicitly associated source completion or cancellation. Do not assign ordinal numbers to announcements.
- The interface may say “已检查接口，暂无新重置预告” after a successful check even while earlier pending countdowns remain. Keep those countdowns visible.
- Keep weekly quota/reset and reset-credit expiry separate from the public announcement ledger. Source timestamps are not independent proof of completed execution.
- The notch panel's hide/hover behavior and cross-application participation need actual macOS acceptance testing. Logic checks alone do not prove every window, full-screen app, wake, or startup case.

## Build and verification

This is a Swift 5.9 / SwiftUI and AppKit Swift Package for macOS 14+. Public release artifacts are currently Apple Silicon (`arm64`) DMG and ZIP, ad-hoc signed and not notarized.

```sh
swift test
./scripts/build_app.sh
./scripts/verify_app.sh dist/CodexNotch.app
./scripts/release.sh
```

The release script runs tests, builds and verifies the app, and makes DMG/ZIP plus SHA-256 files. If `swift test` is unavailable in a restricted environment, state that limitation explicitly. There are executable self-check modes such as `--verify-reset-behavior`, `--verify-reset-source`, and `--verify-window-restoration`; report them separately from full XCTest and physical UI tests. Do not claim notarization from `codesign --verify` or that packaging alone proves notification delivery.

## Publication and safety

- Public download URL: `https://github.com/Jayzengcodetrip/codex-reset-reminder-mac/releases/latest`. Update-check links in source and release notes must point to this repository, never to an unrelated upstream build.
- Keep secrets and personal data out of commits, fixtures, issue templates, release assets, and logs: `auth.json`, Bearer tokens, account IDs, private rollout content, conversation text, and local state databases. Use synthetic fixtures.
- Public NextReset availability and schema are external dependencies. Bound parsing/network failures and display uncertainty honestly. Never promise that an X post yields a notification within five minutes.
- Before publishing a release, verify the archive names, bundle metadata, checksums, clean-machine installation, Gatekeeper first-launch instructions, launch-at-login behavior, notifications, and the top-of-screen panel. Report any untested item as untested.
