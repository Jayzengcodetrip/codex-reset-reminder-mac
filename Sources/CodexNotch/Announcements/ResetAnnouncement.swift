import Foundation

/// Public announcement content only. A post's publication time is never a reset deadline.
struct ResetAnnouncement: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var summary: String
    var sourceURL: URL?
    var announcedAt: Date?
    var scheduledFor: Date?
    var kind: String
    var scope: String
    var status: String?
    var deliveryAt: Date? = nil
    var relatedAnnouncementIDs: [String]? = nil
    var deliveryKind: String? = nil
    var completionEvidence: String? = nil

    func hasSameMaterialContent(as other: ResetAnnouncement) -> Bool {
        title == other.title && summary == other.summary
            && scheduledFor == other.scheduledFor && kind == other.kind
            && scope == other.scope && status == other.status
            && deliveryAt == other.deliveryAt && Set(relatedAnnouncementIDs ?? []) == Set(other.relatedAnnouncementIDs ?? [])
            && deliveryKind == other.deliveryKind
        // completionEvidence describes provenance, not a new reset or a changed deadline.
        // Keep it in the saved details without reopening or notifying the announcement.
    }

    /// Starting delivery already completes the user's reminder. A richer original
    /// post or a stronger completion label for the same delivery is a quiet update.
    func supplementsKnownDelivery(_ other: ResetAnnouncement) -> Bool {
        let deliveredStatuses: Set<String> = ["rolling_out", "completed", "confirmed", "propagated"]
        func delivered(_ value: ResetAnnouncement) -> Bool {
            deliveredStatuses.contains(value.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")
        }
        return deliveryAt != nil && deliveryAt == other.deliveryAt
            && delivered(self) && delivered(other)
            && scheduledFor == other.scheduledFor && kind == other.kind && scope == other.scope
            && deliveryKind == other.deliveryKind
            && Set(relatedAnnouncementIDs ?? []) == Set(other.relatedAnnouncementIDs ?? [])
            && ResetDeliveryEvidence.isGeneralDelivery(self) == ResetDeliveryEvidence.isGeneralDelivery(other)
    }
}

struct ResetRecord: Codable, Identifiable, Equatable {
    let id: String
    var announcement: ResetAnnouncement
    var isUnread: Bool
    var occurredWhileAway: Bool
}

struct NextResetSnapshot: Equatable {
    let announcements: [ResetAnnouncement]
    let sourceCheckedAt: Date?
    let sourceIsFresh: Bool
}
