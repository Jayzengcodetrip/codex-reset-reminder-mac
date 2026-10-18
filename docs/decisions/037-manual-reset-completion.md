---
status: active
owner: local-customization
created_at: 2026-10-18
contracts: [RESET-MANUAL-COMPLETION-001]
---

# Explicit manual reset completion

Automatic public-message and account recovery detection can miss a reset. A user who has verified that it happened needs a direct local fallback.

The scheduled card has a separate “确认已重置” button beside the time. It is a sibling of the history-opening button, avoiding nested controls. History also supports individual undated/expired pending previews and provides undo. No additional confirmation dialog is required because the action is reversible.

Optional `ResetRecord.manualCompletedAt` preserves schema-one compatibility and records the actual click time. Original-post identity includes persisted URL aliases. Save succeeds before observable state changes; failed saves retain the previous display and expose a separate local-operation error. It does not mark the announcement read or emit a notification. A manually completed identity remains closed across refreshes and same-post revisions, which are still retained in history.

The elapsed footer uses manual provenance. A later official completion explicitly tied to the same event does not move that clock. An independent newer delivery, credit grant, or confirmed account recovery can still replace it. Undo clears only manual metadata and derives the display from current remaining evidence.

Rejected alternatives: editing official status/deliveryAt, using an estimated deadline as the manual time, confirming all pending previews, clicking the user's real preview during acceptance testing, and inferring that the operation actually redeems a credit.

Verification uses synthetic persistence, aliases, in-flight refresh and presentation cases plus an isolated native window. Production installation retains the user's actual pending preview for their own click.
