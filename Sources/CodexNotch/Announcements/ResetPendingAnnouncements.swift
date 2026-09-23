import Foundation

/// Derives every still-actionable public preannouncement without ordinal persistence.
enum ResetPendingAnnouncements {
    /// Oldest publication first; acknowledgement and elapsed time do not remove a notice.
    static func pending(from records: [ResetRecord], versions: [String: [ResetAnnouncement]] = [:]) -> [ResetAnnouncement] {
        let current = records.map(\.announcement)
        // Historical URL evidence links an alias even after a later revision omits its URL.
        let evidence = current + versions.values.flatMap { $0 }
        var parents: [String: String] = [:]
        func root(_ identity: String) -> String {
            var value = identity
            while let parent = parents[value], parent != value { value = parent }
            return value
        }
        for announcement in evidence {
            let id = "id:\(announcement.id)"
            if parents[id] == nil { parents[id] = id }
            if let post = postKey(announcement) {
                if parents[post] == nil { parents[post] = post }
                let idRoot = root(id)
                let postRoot = root(post)
                if idRoot != postRoot { parents[idRoot] = postRoot }
            }
        }
        let groups = Dictionary(grouping: current) { root("id:\($0.id)") }
        return groups.values.compactMap { group -> ResetAnnouncement? in
            let terminal = group.filter { announcement in
                if isTerminal(announcement) { return true }
                guard !isExplicitPending(announcement),
                      let previous = lastExplicit(in: versions[announcement.id, default: []]) else { return false }
                return isTerminal(previous)
            }
            return group.filter { announcement in
                guard !isTerminal(announcement), isPending(announcement, history: versions[announcement.id, default: []]) else { return false }
                return !terminal.contains {
                    ($0.announcedAt ?? .distantPast) >= (announcement.announcedAt ?? .distantPast)
                }
            }.sorted { earlier($1, $0) }.first
        }.sorted(by: earlier)
    }

    /// A shared profile/site URL does not identify a particular reset.
    static func sameIdentity(_ left: ResetAnnouncement, _ right: ResetAnnouncement) -> Bool {
        if left.id == right.id { return true }
        guard let leftKey = postKey(left), let rightKey = postKey(right) else { return false }
        return leftKey == rightKey
    }

    private static func isPending(_ announcement: ResetAnnouncement, history: [ResetAnnouncement]) -> Bool {
        if isExplicitPending(announcement) { return true }
        // Only prior explicit evidence keeps an otherwise underspecified revision active.
        // A known terminal version does not become pending merely because later metadata is sparse.
        guard let previous = lastExplicit(in: history) else { return false }
        return !isTerminal(previous)
    }

    private static func lastExplicit(in history: [ResetAnnouncement]) -> ResetAnnouncement? {
        history.reversed().first(where: { isTerminal($0) || isExplicitPending($0) })
    }

    private static func isExplicitPending(_ announcement: ResetAnnouncement) -> Bool {
        !isTerminal(announcement)
            && (announcement.scheduledFor != nil || pendingStatuses.contains(status(announcement)))
    }

    private static func earlier(_ left: ResetAnnouncement, _ right: ResetAnnouncement) -> Bool {
        let leftTime = left.announcedAt ?? .distantPast
        let rightTime = right.announcedAt ?? .distantPast
        return leftTime == rightTime ? left.id < right.id : leftTime < rightTime
    }

    private static let pendingStatuses: Set<String> = ["scheduled", "announced", "watch", "pending"]
    private static let terminalStatuses: Set<String> = ["completed", "confirmed", "propagated", "cancelled", "canceled"]

    private static func status(_ announcement: ResetAnnouncement) -> String {
        announcement.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func isTerminal(_ announcement: ResetAnnouncement) -> Bool {
        terminalStatuses.contains(status(announcement))
    }

    private static func postKey(_ announcement: ResetAnnouncement) -> String? {
        guard let url = announcement.sourceURL, let host = url.host?.lowercased(),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let path = url.path.split(separator: "/")
        guard path.count >= 3, path[path.count - 2] == "status", let postID = path.last,
              !postID.isEmpty, postID.allSatisfy(\.isNumber) else { return nil }
        let xHosts: Set<String> = ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]
        if xHosts.contains(host) { return "post:x:status:\(postID)" }
        return "post:\(host)\(url.path)"
    }

    /// Public fixtures only; runnable without XCTest or a monitoring session.
    static func runSelfChecks() throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw PendingCheckError(message: message) }
            checks += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func post(_ id: String, status: String? = "scheduled", age: TimeInterval = 0,
                  deadline: TimeInterval? = 600, source: String? = nil) -> ResetAnnouncement {
            ResetAnnouncement(id: id, title: "公开重置预告", summary: "测试内容", sourceURL: source.flatMap(URL.init(string:)),
                announcedAt: now.addingTimeInterval(-age), scheduledFor: deadline.map { now.addingTimeInterval($0) },
                kind: "regular", scope: "unspecified", status: status)
        }
        func record(_ announcement: ResetAnnouncement) -> ResetRecord {
            ResetRecord(id: announcement.id, announcement: announcement, isUnread: false, occurredWhileAway: false)
        }
        func snapshot(_ posts: [ResetAnnouncement]) -> NextResetSnapshot {
            NextResetSnapshot(announcements: posts, sourceCheckedAt: now, sourceIsFresh: true)
        }
        var ledger = ResetLedger()
        let first = post("first", age: 100)
        let second = post("second", deadline: 1_200)
        let history = (1...54).map { post("history-\($0)", status: nil, age: 10_000, deadline: nil) }
        _ = ledger.ingest(snapshot(history + [first]), at: now, occurredWhileAway: true)
        try check(ledger.pendingAnnouncements.map(\.id) == [first.id], "Ordinary archive history must not become pending resets")
        ledger.markRead(id: first.id)
        try check(ledger.pendingAnnouncements.map(\.id) == [first.id], "Read acknowledgement must not remove a pending countdown")
        _ = ledger.ingest(snapshot([second]), at: now, occurredWhileAway: false)
        try check(ledger.pendingAnnouncements.map(\.id) == [first.id, second.id], "Independent pending notices must both remain available in publication order")
        try check(ledger.pendingAnnouncements.map(\.scheduledFor) == [first.scheduledFor, second.scheduledFor], "Concurrent preannouncements must keep their own deadlines")
        _ = ledger.ingest(snapshot([]), at: now.addingTimeInterval(10_000), occurredWhileAway: true)
        try check(ledger.pendingAnnouncements.count == 2, "Elapsed time and archive omission must not erase pending notices")
        var revised = first
        revised.summary = "更正后的重置时间"
        revised.scheduledFor = now.addingTimeInterval(2_400)
        _ = ledger.ingest(snapshot([revised]), at: now, occurredWhileAway: false)
        try check(ledger.pendingAnnouncements.count == 2 && ledger.pendingAnnouncements.first?.scheduledFor == revised.scheduledFor,
                  "Same-ID revisions must update their countdown without creating another notice")
        var completed = revised
        completed.status = "completed"
        _ = ledger.ingest(snapshot([completed]), at: now, occurredWhileAway: false)
        try check(ledger.pendingAnnouncements.map(\.id) == [second.id], "Completion must remove only the corresponding pending notice")
        _ = ledger.ingest(snapshot([post("unrelated-completion", status: "completed")]), at: now, occurredWhileAway: false)
        try check(ledger.pendingAnnouncements.map(\.id) == [second.id], "An unrelated completed post must not remove another countdown")
        var cancelled = second
        cancelled.status = "cancelled"
        _ = ledger.ingest(snapshot([cancelled]), at: now, occurredWhileAway: false)
        try check(ledger.pendingAnnouncements.isEmpty, "Only explicit completion or cancellation removes the last pending notice")
        try check(ledger.records.contains(where: { $0.id == first.id }), "Finishing must retain the historical announcement")

        let unknown = post("unknown", status: "watch", deadline: nil)
        let elapsed = post("elapsed", age: 100, deadline: -10)
        try check(pending(from: [record(unknown), record(elapsed)]).map(\.id) == [elapsed.id, unknown.id],
                  "Unknown and elapsed deadlines both remain pending")
        for status in ["completed", "confirmed", "propagated", "cancelled", "canceled", " COMPLETED "] {
            try check(pending(from: [record(post(status, status: status))]).isEmpty,
                      "Explicit terminal status \(status) cannot remain pending")
        }
        var uncertain = unknown
        uncertain.status = "source-format-changed"
        try check(pending(from: [record(uncertain)]).isEmpty, "An unfamiliar status without prior evidence must not fabricate a preannouncement")
        try check(pending(from: [record(uncertain)], versions: [unknown.id: [unknown, uncertain]]).count == 1,
                  "Known pending history must survive later sparse nonterminal metadata")
        var resolvedUnknown = unknown
        resolvedUnknown.status = "confirmed"
        try check(pending(from: [record(uncertain)], versions: [unknown.id: [unknown, resolvedUnknown, uncertain]]).isEmpty,
                  "Sparse metadata must not resurrect a previously confirmed completion")

        let original = post("source-a", age: 100, source: "https://x.com/thsottiaux/status/123456?s=20")
        let alias = post("source-b", source: "https://twitter.com/thsottiaux/status/123456")
        try check(sameIdentity(original, alias), "X/Twitter aliases and query strings must refer to the same original post")
        try check(sameIdentity(first, revised), "An ID-preserving revision must have the same identity")
        try check(!sameIdentity(first, second), "Independent notices must not share an identity")
        try check(pending(from: [record(original), record(alias)]).map(\.id) == [alias.id],
                  "Newer same-post versions must provide one current countdown")
        var aliasDone = alias
        aliasDone.status = "confirmed"
        try check(pending(from: [record(original), record(aliasDone)]).isEmpty,
                  "Linked completion must retire all versions of the same original post")
        var sparseCompletedAlias = aliasDone
        sparseCompletedAlias.status = "source-format-changed"
        sparseCompletedAlias.scheduledFor = nil
        try check(pending(from: [record(original), record(sparseCompletedAlias)], versions: [alias.id: [alias, aliasDone, sparseCompletedAlias]]).isEmpty,
                  "A sparse revision of a known completion must not revive its older same-post pending alias")
        var omittedURL = original
        omittedURL.sourceURL = nil
        try check(pending(from: [record(omittedURL), record(aliasDone)], versions: [original.id: [original, omittedURL]]).isEmpty,
                  "Historical URL evidence must keep a later sparse revision linked to its completion")
        let profileA = post("profile-a", source: "https://x.com/thsottiaux")
        let profileB = post("profile-b", source: "https://x.com/thsottiaux")
        try check(!sameIdentity(profileA, profileB), "A shared profile URL cannot identify a specific reset")
        try check(pending(from: [record(profileA), record(profileB)]).count == 2,
                  "Two notices sharing only a profile URL must stay independent")

        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as! [String: Any]
        encoded["preannouncementSequence"] = ["round": 2, "lastNumber": 3, "assignmentsByID": ["first": ["round": 1, "number": 1]]]
        let migrated = try JSONDecoder().decode(ResetLedger.self, from: JSONSerialization.data(withJSONObject: encoded))
        try check(migrated == ledger, "Removing obsolete numbering must preserve schema-one records, versions and read state")
        let rewritten = try JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as! [String: Any]
        try check(rewritten["preannouncementSequence"] == nil, "The next normal save must omit retired ordinal fields")
        try check(migrated.records.count == ledger.records.count && migrated.versions == ledger.versions,
                  "Ordinal migration must not clean up or remove public history")
        return checks
    }

    private struct PendingCheckError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
