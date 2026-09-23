---
status: active
contract_ids: [RESET-ANNOUNCEMENTS-001, NOTCH-MOTION-003, PRIVACY-BOUNDARY-005, PACKAGE-VERIFY-006]
supersedes: []
superseded_by: null
owner: local-customization
created_at: 2026-09-12
last_verified_commit: null
---

# Free public reset announcements in the native quota app

The user chose NextReset public-interface timing instead of a five-minute guarantee from Tibo's original post. Reuse the existing quota and per-credit expiration display. Add a fixed 80pt announcement entry beneath the compact top lane, a camera-safe unread dot, and a separate native details window. This preserves the existing fixed canvas and leaves room for every reset credit.

Public requests use an ephemeral unauthenticated URLSession, and read both status and full archive. No model inference, paid X service, subscription or cloud host is needed. Only public announcements and read flags are persisted in Documents/Codex/QuotaReminderState; existing account tokens remain in their existing in-memory path to ChatGPT. OS notifications are independent of read acknowledgement. Start/wake/unlock/reconnect performs silent catch-up. Login startup uses macOS SMAppService and its ordinary visible approval state.

Risk is L2: user-visible monitoring, notifications, persistence, settings and local packaging. Preserve camera geometry, existing quota and credit semantics, auth boundaries, and session behavior. No redemption, remote publication, auto-updater, or paid service is in scope. Failure must remain visible; the public archive cannot be represented as a complete record of every original X post.

Tests cover baseline, new records, material updates, persisted unread, failed fetch/save, deduplication and truthful time text. Full verification builds and checks the local app. Physical camera clearance, popup delivery and login startup require runtime observation; static images do not verify motion.

## 2026-09-22 status-envelope compatibility repair

The live source introduced `scheduled: {event: {...}, scheduledFor: ...}`. Parsing the
envelope as a flat post rejected the full refresh with `invalidAnnouncement`, hiding
an actionable advance notice even though both HTTP requests succeeded. Normalize
status envelopes before parsing, retain the nested post ID/publication time, and
carry explicit envelope deadline fields. Continue accepting flat posts, merging by
post ID, preserving source-staleness warnings and failing malformed records atomically.

This remains L2: only announcement compatibility, regression checks and local packaging
change. Account authentication, quota semantics, notification/catch-up rules, geometry,
user preferences, persisted read history and remote publication are outside this repair.
The regression is the real envelope shape, with checks for ID deduplication, separate
publication/deadline times, absent deadlines and malformed envelopes. A source-provided
deadline is not independent verification of an exact official reset time.

## 2026-09-22 main-card countdown repair

The main entry previously received unread counts and source health only. Reading a
preannouncement removed its prominence, and a delayed source concealed its known
deadline behind generic check status. Pass an independently selected pending
announcement to the existing expanded card and clock. The card shows a large live
countdown, Beijing deadline and source-time attribution even when read. Keep source
health below these facts. Unknown times remain unknown; elapsed times await explicit
confirmation, and completed or cancelled announcements never have active countdowns.

This L2 change increases the fixed entry from 72 to 96 points (plus existing 8-point
spacing); the existing fixed-canvas geometry helper applies it consistently. Preserve
camera clearance, manual visibility, quota/credit state, acknowledgement and silent
catch-up behavior. No account, network, redemption or publication changes are required.
Acceptance includes read/stale/future regression checks, second-by-second countdown,
notification deadline text, built bundle checks and main-window runtime inspection.

The settings action “查看倒计时” opens the same expanded card through a transient hover state, without writing visibility preferences or acknowledging a record. Mixed notification batches prioritize pending preannouncements, then fall back to the newest update.
