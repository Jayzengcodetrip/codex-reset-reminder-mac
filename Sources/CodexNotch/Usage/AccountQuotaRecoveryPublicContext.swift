import Foundation

/// Only recognized, broad, official direct-reset completions can help explain a
/// personal recovery. This projection never changes the announcement ledger.
enum AccountQuotaRecoveryPublicContext {
    static func completions(from records: [ResetRecord], now: Date) -> [AccountQuotaPublicCompletion] {
        records.compactMap { record in
            let announcement = record.announcement
            let kind = (announcement.deliveryKind ?? announcement.kind)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let scope = announcement.scope
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ResetDeliveryEvidence.isGeneralDelivery(announcement),
                  ["regular", "automatic_global"].contains(kind),
                  ["", "unspecified", "broad", "all", "global", "general", "codex"].contains(scope),
                  let source = announcement.sourceURL,
                  BoundedResetLinkResolver.officialPostDestination(source.absoluteString) != nil,
                  let time = ResetDeliveryEvidence.deliveryTimestamp(announcement), time <= now else { return nil }
            return AccountQuotaPublicCompletion(id: announcement.id, deliveredAt: time)
        }
    }
}
