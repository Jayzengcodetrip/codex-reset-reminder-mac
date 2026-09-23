---
status: superseded
contract_ids: [RESET-ANNOUNCEMENTS-003, NOTCH-MOTION-003, PRIVACY-BOUNDARY-005, PACKAGE-VERIFY-006]
supersedes: []
superseded_by: 035-concurrent-reset-countdowns
owner: local-customization
created_at: 2026-09-22
last_verified_commit: null
---

# Number pending preannouncements by round

Change (L2): persist stable numbers for independent pending announcements, show those
numbers in main cards, archive rows and notifications, and make the successful check
result refer to the next number. The user explicitly chose restarting at 1 after all
pending announcements in the round complete or are cancelled. This supersedes the
generic pending wording of decision 033 and contract RESET-ANNOUNCEMENTS-002.

Preserve: per-announcement countdowns, unknown/elapsed/terminal semantics, quota and
credits, read history, atomic public-state save, source-time attribution, polling,
catch-up/notification rules, login/display preferences and authentication boundaries.
Out of scope: paid services, new data sources, auto-redemption, remote publication and
changes to the physical camera lane. Each main card keeps its existing height; up to
two pending cards are visible together, with scrolling for more, so quota/credit
content keeps space. Root geometry derives the bounded added height from active count.

Numbers are local to a round and based on first tracking of independent post identities.
Content revisions and same original-post aliases do not constitute another reset.
Historical completed records are not retroactively given pending numbers. Older saved
ledgers remain readable; derived migration is saved only after a successful candidate
write. Failed writes must not advance real state or send a notification.

Acceptance: migration/read/restart/revision/alias, next-number text, multiple pending
countdowns, elapsed pending, explicit completion/cancellation, new-round reset, and
failed-save recovery checks; required build and package validation plus live UI.
