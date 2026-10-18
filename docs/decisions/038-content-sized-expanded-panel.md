---
status: active
owner: local-customization
created_at: 2026-10-18
contracts: [NOTCH-EXPANDED-DENSITY-001]
---

# Fit the expanded panel to its visible content

The empty announcement occupied 96pt, a one-line manual elapsed clock still
reserved a two-line footer, and the quota canvas retained legacy allowances.
Flexible vertical spacers distributed the unused space through the panel.

Use a 64pt empty card, a 16pt manual elapsed row (30pt when a provenance line is
present), and 6pt announcement section gaps. Keep dated countdown cards at 138pt
and the 284pt announcement cap so dense content remains legible and scrollable.

The quota base derives from fixed visible rows and gaps, totaling 132pt. The
view uses those same values. A second quota row, credit expiry rows and recent
conversations add their existing measured content heights. Replace flexible
vertical spacers with fixed gaps, retain the top attachment, 420pt width and
existing text sizes, and let settings controls follow content.

For a 32pt camera area, no preview, one weekly quota, collapsed credits and a
manual elapsed clock, the panel is 258pt high instead of 348pt. Synthetic native
checks cover unread/error and English text, multiple dated previews with internal
scrolling, an undated summary, five-hour quota, credit expansion and conversations.
The actual installed state must also be inspected before claiming acceptance.

Rejected alternatives: shrinking all text, merely clipping the old canvas,
removing useful quota/expiry information, changing compact-camera geometry, and
storing a user preference for what should be automatic content sizing.
