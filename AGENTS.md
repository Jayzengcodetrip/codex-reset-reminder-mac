# Project handoff for contributors and coding agents

## Purpose and provenance

This is the public source for Codex Reset Reminder, whose application bundle is still named `CodexNotch.app`. It extends [fengdwx/codex-notch](https://github.com/fengdwx/codex-notch) v0.1.16 under MIT. Preserve the original copyright and permission text in `LICENSE` and the attribution in `NOTICE.md`.

The product has three distinct data domains. Do not infer a temporary benefit reset from an account's ordinary weekly reset time or from reset-credit count.

1. **Account quota and credit receipts**: local Codex credentials from `CODEX_HOME/auth.json` (default `~/.codex/auth.json`) are sent only to ChatGPT usage and reset-credit endpoints. A past, exact reset-credit `granted_at` is evidence that this account received a credit, not that it was redeemed or that every account received one. Cache that timestamp and optional title/description locally under a hash of the account ID, never a raw account ID or token.
2. **Public temporary reset announcements**: unauthenticated GET requests to NextReset `/api/status` and `/api/resets`, Codex Resets `/api/v1/resets?limit=100`, and NextReset.org `/api/v1/events.json`; no Codex token, account ID, or private conversation content may be sent there.
3. **Local activity**: Codex session files and the local state database support the task/status UI.

## Product behavior to preserve

- Check the public source at launch and about every 120 seconds while the app runs; catch up after sleep, unlock, and network recovery. A failure must not be presented as a successful check.
- First-run archive discovery establishes a quiet baseline. New or materially updated announcements during active use can produce a macOS notification; updates found while away remain visible and unread in the app.
- Changes to provenance wording alone never reopen an announcement. More source text or a stronger completion label for the same known delivery is saved silently; changed delivery time/type/scope, new preview relations and cancellation remain meaningful. History is ordered by publication date, with separate unread/away filters.
- Keep independent countdowns for every visible **dated** pending announcement. Date/weekday-only previews use America/Los_Angeles: count down to the announced day's midnight, then count down through that day until the next midnight. Both boundaries are estimates, not official times; never encourage exhausting quota solely on the estimate. Exact timestamps keep their deadline. Visible cards and pending details show live weekday + 24-hour HH:mm:ss without month/day; notification clocks are fixed snapshots. Beijing shows only the corresponding cutoff weekday.
- Pending previews with no usable date have no invented countdown. Combine current undated previews into one small top summary with the newest original-post excerpt and its publication time; keep their separate history entries. If a later, credible, same-scope compatible official delivery exists, an older undated preview may leave the home summary only. Keep it unresolved in history with “后续已有重置 · 本条关联未确认” and a clear history entry point. A later compatible exact credit grant for this account may likewise remove only that older undated preview from home; history instead says “本账户已收到重置券 · 本条关联未确认” and shows the actual grant time. Neither path claims completion or a verified relation. A newer preview remains visible, and an older preview that later gains a usable date returns as its own countdown.
- At the end of the announced LA day, hide an unfulfilled dated top card and show “暂无最新重置预告” only if no other dated or undated preview remains; retain the unresolved ledger history. Official started delivery counts: direct reset and banked reset both end the **associated** countdown. With no visible preview, show “暂无最新重置预告（今天已重置）” until the public delivery's LA day ends, or use the plain “暂无最新重置预告” headline when the latest signal is an exact account credit grant; identify the received credit once in the elapsed-time footer. Present elapsed time since the latest credible public delivery or this account's exact credit grant as a separate live signal, including when previews remain visible and on a same-day empty home card. Label the origin clearly: a public rollout is not proof of individual receipt, and an account credit grant requires manual redemption. Omit elapsed time without either timestamp. Never derive it from an estimated deadline, a local check, a future `granted_at`, weekly quota or credit counts. Cancellation stays in history.
- Prefer explicit announcement-to-delivery evidence. A fallback association may use only one compatible official **dated** preview on the same LA target date, excluding targeted compensation and conflicting types. Persist and explain inferred relations; do not silently rematch the same delivery. Hiding an older undated preview from home after a later compatible public delivery or account credit grant is a presentation decision, never an inferred association or ledger completion. An account grant must not invent an official post link, change read state, or trigger an announcement notification. Auxiliary feed failure must not erase evidence or replay notices. Preserve visible attribution links for all public sources.
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
- The status feed's `watch` field may contain a standalone provider forecast with `level`, `window`/`excerpt` and observation/expiry times but no event identity or source post. Ignore only that recognized non-announcement shape; preserve real flat/wrapped watch events and fail malformed official announcements. Never turn a provider forecast's window or expiry into an official reset deadline.
- Before publishing a release, verify the archive names, bundle metadata, checksums, clean-machine installation, Gatekeeper first-launch instructions, launch-at-login behavior, notifications, and the top-of-screen panel. Report any untested item as untested.
