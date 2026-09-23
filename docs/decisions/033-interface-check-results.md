---
status: active
contract_ids: [RESET-ANNOUNCEMENTS-002, NOTCH-MOTION-003, PRIVACY-BOUNDARY-005, PACKAGE-VERIFY-006]
supersedes: []
superseded_by: null
owner: local-customization
created_at: 2026-09-22
last_verified_commit: null
---

# Interface results instead of provider review diagnostics

Change (L2): the main card and announcement window show whether the app successfully
checked the interface, whether a pending reset/new update exists, and the last local
successful check in Beijing time. Remove the provider X review timestamp and freshness
warnings from daily UI. The user's clarification supersedes only the source-status
presentation requirement in decision 032 and contract RESET-ANNOUNCEMENTS-001.

Preserve: pending countdown after read, unknown/elapsed/terminal time semantics,
120-second polling, awake notifications, silent catch-up, unread persistence,
source metadata, fixed 96-point main card, quota and credits, login/visibility
preferences, and account-data isolation. Out of scope: API provider changes, new
monitoring channels, geometry refactors, credit redemption, and remote publication.

A completely decoded and atomically saved response is a successful interface check
even when upstream X browser-review metadata is delayed. Retain real local errors.
Never convert failed fetch/decode/save into no new announcements. The user-facing
result is explicitly scoped to the interface; it is not a claim of complete X coverage.

Acceptance: reproduce stale-metadata-as-error with a runtime guard, then pass the same
guard plus status positive/negative checks, package/signature verification and real
window inspection. Full XCTest remains subject to this machine's installed tools.
