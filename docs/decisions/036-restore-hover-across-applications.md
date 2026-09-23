---
status: active
contract_ids: [NOTCH-VISIBILITY-050, RESET-ANNOUNCEMENTS-004, NOTCH-MOTION-003, PRIVACY-BOUNDARY-005]
supersedes: []
superseded_by: null
owner: local-customization
created_at: 2026-09-22
last_verified_commit: null
---

# Restore the requested panel after application and fullscreen transitions

## Scope and evidence

L2 change: repair cross-application availability of both the enabled status panel
and the disabled display's transparent hover sensor after app/Space/display changes.
Preserve NOTCH-VISIBILITY-049's hidden preference, compact sensor bounds, fallback
and hardware-mirror exclusions, existing window level, downward expansion, quota,
credits, multiple reset countdowns, notification rules, and account-data boundaries.
Visual redesign, higher system window levels, global window enumeration, permanent
polling, activating the app, and changing the user's saved preference are out of scope.

The user confirmed that the hidden top hover entry works on the desktop but does
not open over other application windows. The user subsequently excluded DOTA2 from
the investigation; this change targets generic cross-application visibility only.
Live inspection found notchDisplayEnabled=0 and an alive idle main thread. Preserve
that preference; a closed display must retain an effective hover recovery entry.

The panel already joins all Spaces and native fullscreen, but lacked the additional
canJoinAllApplications collection behavior documented for floating/system overlays
in the installed Apple SDK's NSWindow.h. Restoration previously ran once on the next
main loop. A transition completing later could reorder the panel after that attempt;
switches between non-Codex apps also shared the same boolean state and did not force
a new layout render. These are concrete coverage gaps, not a proven event trace.

## Decision

Add canJoinAllApplications alongside the existing compatible collection flags.
After app/Space or display transitions, schedule only a bounded recovery sequence
(next main loop, 250 ms, 750 ms). Before each attempt refresh the current layout and
then use the latest requested mode. A replacement transition invalidates the old
sequence. Hiding for fallback, mirroring, stopping, or deallocation cancels pending
attempts so stale callbacks cannot recreate a withdrawn panel. Hidden display still
means only the transparent compact hover sensor until the user enters it.

Retain nonactivating/non-key behavior and popUpMenu level. Do not call activate,
change the display preference, or attach restoration to the one-second clock.

## Verification

Use deterministic scheduling fixtures covering a late transition after the initial
attempt, bounded attempts, latest-request replacement, cancellation, cancellation
during relayout and no new timer work after the window settles. Keep panel-policy
tests for all-app/all-space/fullscreen flags and transparent recovery/fallback.
Run the formal application's --verify-window-restoration and --verify-reset-behavior,
bundle checks and the full verification script. Missing XCTest on this machine must
be reported rather than presenting the self-checks as the full test suite.

Real-machine acceptance should observe hidden hover over normal windows and a native
fullscreen transition while retaining preference 0. Physical-notch motion, monitor changes and hardware mirroring must be listed as
unverified unless actually exercised. Do not require a game-specific reproduction.
