import Foundation

/// This ledger contains public source content and acknowledgement state, never account data.
struct ResetLedger: Codable, Equatable {
    var schemaVersion = 1
    var baselineCompleted = false
    /// Optional for schema-one ledgers created before auxiliary delivery sources existed.
    var deliveryEvidenceBaselineCompleted: Bool? = nil
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
        let establishingDeliveryBaseline = deliveryEvidenceBaselineCompleted != true
            && snapshot.announcements.contains { $0.deliveryAt != nil }
        let previousSuccessfulCheck = lastSuccessfulCheck
        var changed: [ResetRecord] = []
        var index = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
        // Restore known delivery relations before matching, so a later, delayed
        // preview cannot steal a delivery already assigned to an earlier one.
        let prepared = snapshot.announcements.map { incoming -> ResetAnnouncement in
            guard let existingIndex = index[incoming.id] else { return incoming }
            let prior = records[existingIndex].announcement
            let enriched = preservingDeliveryEvidence(incoming, prior: prior)
            if !enriched.hasSameMaterialContent(as: prior),
               versions[incoming.id, default: []].contains(where: {
                   incoming.hasSameMaterialContent(as: $0) || enriched.hasSameMaterialContent(as: $0)
               }) { return prior }
            return enriched
        }
        // A same-ID schedule correction must replace its old deadline before
        // unique-candidate matching, even when publication times are identical.
        var combined = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.announcement) })
        for announcement in prepared { combined[announcement.id] = announcement }
        let candidates = ResetPendingAnnouncements.pending(from: combined.values.map {
            ResetRecord(id: $0.id, announcement: $0, isUnread: false, occurredWhileAway: false)
        }, versions: versions)
        for announcement in ResetDeliveryEvidence.associate(prepared, pending: candidates) {
            let historicalDelivery = establishingDeliveryBaseline
                && announcement.deliveryAt.map { delivery in
                    previousSuccessfulCheck.map { delivery <= $0 } ?? false
                } == true
            if let existingIndex = index[announcement.id] {
                let prior = records[existingIndex]
                if !announcement.hasSameMaterialContent(as: prior.announcement) {
                    // Stale intermediary caches must not replay a previously seen version.
                    if versions[announcement.id, default: []].contains(where: { announcement.hasSameMaterialContent(as: $0) }) { continue }
                    versions[announcement.id, default: [prior.announcement]].append(announcement)
                    let record = ResetRecord(
                        id: announcement.id, announcement: announcement,
                        isUnread: historicalDelivery ? prior.isUnread : true,
                        occurredWhileAway: historicalDelivery ? prior.occurredWhileAway
                            : prior.isUnread && prior.occurredWhileAway || occurredWhileAway
                    )
                    records[existingIndex] = record
                    if !historicalDelivery { changed.append(record) }
                } else {
                    // Non-material source metadata may improve without replaying a notification.
                    records[existingIndex].announcement = announcement
                }
            } else {
                let pending = announcement.status?.lowercased() == "scheduled"
                    || announcement.scheduledFor.map { $0 > now } == true
                let unread = !historicalDelivery && (!establishingBaseline || pending)
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
        // Failed/unavailable auxiliary sources must not consume their first-run baseline.
        if establishingDeliveryBaseline { deliveryEvidenceBaselineCompleted = true }
        lastSuccessfulCheck = now
        sourceCheckedAt = snapshot.sourceCheckedAt
        sourceIsFresh = snapshot.sourceIsFresh
        return changed
    }

    private func preservingDeliveryEvidence(_ incoming: ResetAnnouncement,
                                            prior: ResetAnnouncement) -> ResetAnnouncement {
        var result = incoming
        let cancelled = ["cancelled", "canceled"].contains(
            incoming.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        )
        if result.status == nil { result.status = prior.status }
        if result.deliveryAt == nil, prior.deliveryAt != nil {
            result.deliveryAt = prior.deliveryAt
            result.deliveryKind = prior.deliveryKind
            result.relatedAnnouncementIDs = prior.relatedAnnouncementIDs
            result.completionEvidence = prior.completionEvidence
            if !cancelled {
                result.status = prior.status
                // An unavailable auxiliary response is not a content revision.
                // Keep the full original post and its known delivery scope.
                result.summary = prior.summary
                result.kind = prior.kind
                result.scope = prior.scope
            }
        } else if result.relatedAnnouncementIDs?.isEmpty != false,
                  prior.relatedAnnouncementIDs?.isEmpty == false {
            result.relatedAnnouncementIDs = prior.relatedAnnouncementIDs
            result.completionEvidence = prior.completionEvidence ?? result.completionEvidence
        }
        // The event-relation feed can still succeed while the full-text feed
        // is unavailable. Keep known original text over an editorial snippet.
        if !cancelled, prior.deliveryAt != nil,
           ResetDeliveryEvidence.hasOriginalDeliveryText(prior),
           !ResetDeliveryEvidence.hasOriginalDeliveryText(result) {
            result.summary = prior.summary
            if !ResetDeliveryEvidence.isGeneralDelivery(prior) { result.scope = prior.scope }
        }
        if !cancelled, result.status?.lowercased() == "rolling_out",
           ["completed", "confirmed", "propagated"].contains(prior.status?.lowercased() ?? "") {
            // Losing the event feed does not roll an already completed source
            // post backwards to the full-text feed's weaker delivery stage.
            result.status = prior.status
            result.deliveryAt = prior.deliveryAt ?? result.deliveryAt
        }
        return result
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
