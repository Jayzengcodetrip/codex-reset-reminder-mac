import Foundation

/// This ledger contains public source content and acknowledgement state, never account data.
struct ResetLedger: Codable, Equatable {
    var schemaVersion = 1
    var baselineCompleted = false
    var records: [ResetRecord] = []
    var versions: [String: [ResetAnnouncement]] = [:]
    var lastSuccessfulCheck: Date?
    var sourceCheckedAt: Date?
    var sourceIsFresh = false
    var pendingAnnouncements: [ResetAnnouncement] {
        ResetPendingAnnouncements.pending(from: records, versions: versions)
    }

    /// Returns changes that may be notified only after the complete candidate ledger is saved.
    mutating func ingest(_ snapshot: NextResetSnapshot, at now: Date, occurredWhileAway: Bool) -> [ResetRecord] {
        let establishingBaseline = !baselineCompleted
        var changed: [ResetRecord] = []
        var index = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
        for incoming in snapshot.announcements {
            var announcement = incoming
            if let existingIndex = index[announcement.id] {
                let prior = records[existingIndex]
                // A historical archive row may omit a previously explicit completion status.
                if announcement.status == nil {
                    announcement.status = prior.announcement.status
                }
                if !announcement.hasSameMaterialContent(as: prior.announcement) {
                    // Stale intermediary caches must not replay a previously seen version.
                    if versions[announcement.id, default: []].contains(where: { incoming.hasSameMaterialContent(as: $0) || announcement.hasSameMaterialContent(as: $0) }) { continue }
                    versions[announcement.id, default: [prior.announcement]].append(announcement)
                    let record = ResetRecord(id: announcement.id, announcement: announcement, isUnread: true,
                                             occurredWhileAway: prior.isUnread && prior.occurredWhileAway || occurredWhileAway)
                    records[existingIndex] = record
                    changed.append(record)
                } else {
                    // Non-material source metadata may improve without replaying a notification.
                    records[existingIndex].announcement = announcement
                }
            } else {
                let pending = announcement.status?.lowercased() == "scheduled"
                    || announcement.scheduledFor.map { $0 > now } == true
                let unread = !establishingBaseline || pending
                let record = ResetRecord(id: announcement.id, announcement: announcement, isUnread: unread,
                                         occurredWhileAway: unread && occurredWhileAway)
                index[announcement.id] = records.count
                records.append(record)
                versions[announcement.id] = [announcement]
                if unread && !establishingBaseline { changed.append(record) }
            }
        }
        records.sort { lhs, rhs in
            if lhs.isUnread != rhs.isUnread { return lhs.isUnread }
            let left = lhs.announcement.announcedAt ?? .distantPast
            let right = rhs.announcement.announcedAt ?? .distantPast
            return left == right ? lhs.id > rhs.id : left > right
        }
        baselineCompleted = true
        lastSuccessfulCheck = now
        sourceCheckedAt = snapshot.sourceCheckedAt
        sourceIsFresh = snapshot.sourceIsFresh
        return changed
    }

    mutating func markRead(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].isUnread = false
        records[index].occurredWhileAway = false
    }
}

protocol ResetLedgerStoring {
    func load() throws -> ResetLedger?
    func save(_ ledger: ResetLedger) throws
}

struct ResetLedgerStore: ResetLedgerStoring {
    let url: URL

    func load() throws -> ResetLedger? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let ledger = try JSONDecoder().decode(ResetLedger.self, from: Data(contentsOf: url))
        guard ledger.schemaVersion == 1 else { throw NextResetError.invalidSavedState }
        return ledger
    }

    func save(_ ledger: ResetLedger) throws {
        let data = try JSONEncoder().encode(ledger)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
