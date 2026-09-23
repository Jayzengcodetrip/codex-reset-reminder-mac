---
status: active
contract_ids: [RESET-ANNOUNCEMENTS-004, NOTCH-MOTION-003, PRIVACY-BOUNDARY-005, PACKAGE-VERIFY-006]
supersedes: [034-numbered-reset-preannouncements]
superseded_by: null
owner: local-customization
created_at: 2026-09-22
last_verified_commit: null
---

# Simple check result and concurrent countdowns

The user cancelled ordinal labels and round tracking after reviewing the numbered
version. The final L2 change keeps every independent pending countdown and uses the
unified result “已检查接口，暂无新重置预告” when the latest successful check found no
additional preannouncement. A new independent pending identity produces a new-discovery
result for that check and can notify under the existing awake/catch-up policy.
Unread counts and existing pending cards do not mean the latest check found a new one.

Preserve public history, read flags, prior material versions, explicit terminal-state
semantics, countdown clocks, source-time attribution, interface errors, quota/credit
semantics, camera lane geometry, privacy and user preferences. No new persistent
numbering fields or channels are introduced. Older optional ordinal metadata is ignored
on decoding and omitted on the next ordinary successful save, without touching records.

Derive active identities from current records plus their already-saved public versions.
Deduplicate the same ID/original post; never treat shared profile URLs or broad scopes
as event identity. Once tracked as pending, missing/unknown state stays pending until
explicit completion/cancellation. Each countdown uses its own deadline, so an update to
one cannot remove another. Two cards fit in a 200-point area; extras scroll there.
This bounds expansion while retaining the weekly quota and credit section.

The Settings summary shortcut opens the existing expanded panel without synthesizing
a pointer-hover event. Credit disclosure therefore accepts an explicit click while
the runtime is started and the panel is expanded; it must not require a prior hover
callback. Compact/stopped states still reject disclosure. The persistent notch-display
preference remains unchanged.

Acceptance includes unchanged checks with existing countdowns, two independent deadlines,
single-ID time correction, alias deduplication, completion of only one, failed-save
recovery, pre-numbered ledger compatibility, bundle validation and real-window inspection.
