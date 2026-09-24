# Project handoff for contributors and coding agents

## Purpose and provenance

This is the public source for Codex Reset Reminder, whose application bundle is still named `CodexNotch.app`. It extends [fengdwx/codex-notch](https://github.com/fengdwx/codex-notch) v0.1.16 under MIT. Preserve the original copyright and permission text in `LICENSE` and the attribution in `NOTICE.md`.

The product has three distinct data domains. Do not infer a temporary benefit reset from an account's ordinary weekly reset time or from reset-credit count.

1. **Account quota**: local Codex credentials from `CODEX_HOME/auth.json` (default `~/.codex/auth.json`) are sent only to ChatGPT usage and reset-credit endpoints.
2. **Public temporary reset announcements**: unauthenticated GET requests to NextReset `/api/status` and `/api/resets`, Codex Resets `/api/v1/resets?limit=100`, and NextReset.org `/api/v1/events.json`; no Codex token, account ID, or private conversation content may be sent there.
3. **Local activity**: Codex session files and the local state database support the task/status UI.

## Product behavior to preserve

- Check the public source at launch and about every 120 seconds while the app runs; catch up after sleep, unlock, and network recovery. A failure must not be presented as a successful check.
- First-run archive discovery establishes a quiet baseline. New or materially updated announcements during active use can produce a macOS notification; updates found while away remain visible and unread in the app.
- Keep independent countdowns for every visible pending announcement. Date/weekday-only previews use America/Los_Angeles: count down to the announced day's midnight, then count down through that day until the next midnight. Both boundaries are estimates, not official times; never encourage exhausting quota solely on the estimate. Exact timestamps keep their deadline. Visible cards and pending details show live weekday + 24-hour HH:mm:ss without month/day; notification clocks are fixed snapshots. Beijing shows only the corresponding cutoff weekday.
- At the end of the announced LA day, hide an unfulfilled top card and show “暂无最新重置预告”; retain the unresolved ledger history. Official started delivery counts: direct reset and banked reset both end the associated countdown. When no other visible preview exists, show “暂无最新重置预告（今天已重置）” until the delivery's LA day ends. Thereafter, the empty top card shows “暂无最新重置预告（距离上次重置已过N天HH:mm:ss）”, omitting days when zero and ticking each second from the most recent known general delivery (not its estimated deadline or the local check time). Without known delivery evidence, omit the elapsed value. This is a public rollout signal, not proof of individual account receipt. Cancellation stays in history. Do not infer delivery from weekly quota or credit counts.
- Prefer explicit announcement-to-delivery evidence. A fallback association may use only one compatible official preview on the same LA target date, excluding targeted compensation and conflicting types. Persist and explain inferred relations; do not silently rematch the same delivery. Auxiliary feed failure must not erase evidence or replay notices. Preserve visible attribution links for all public sources.
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
