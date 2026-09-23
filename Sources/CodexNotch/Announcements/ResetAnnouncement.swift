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

    func hasSameMaterialContent(as other: ResetAnnouncement) -> Bool {
        title == other.title && summary == other.summary
            && scheduledFor == other.scheduledFor && kind == other.kind
            && scope == other.scope && status == other.status
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
