# Standalone elapsed-clock restart

A reset can reach an account without an earlier public preview. The existing per-preview confirmation has no target in that case. Add a small Restart timer button beside the elapsed label, also available before any delivery is known.

Persist an optional `manualTimerRestartedAt` in the existing schema-one ledger. It is a local clock anchor, not a fabricated announcement or a completion relation. Each explicit click replaces the anchor after atomic save succeeds. Keep network status, announcements, unread flags, versions, credits and quota unchanged. Feed ingestion starts from the current ledger, so an in-flight response cannot discard a click. Bad loads block the write; save failures retain the last visible clock.

Projection compares the valid local anchor with existing delivery signals by time; older signals cannot replace it, newer independent evidence may. Use a distinct manualTimerRestart origin and omit its home footnote. The current user value is never reset merely by installing an update.

The ordinary no-preview card is 48pt rather than 64pt, with existing font sizes. Add only the rows required by unread updates and a same-day public delivery label. Use matching size calculations in the panel coordinator and rendered content. Validate Chinese/English, no history, restart, reload, credits, and multiple previews using synthetic UI data before installing.
