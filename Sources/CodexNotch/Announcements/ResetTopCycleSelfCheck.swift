import Foundation

/// Deterministic integration checks for the top-card cycle, including the real
/// source evidence parser, announcement ledger and JSON persistence. No XCTest,
/// network, account credentials, notifications or machine clock are required.
enum ResetTopCycleSelfCheck {
    static func run() throws -> Int {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(message: message) }
            checks += 1
        }
        func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
        func post(_ id: String, scheduled: String? = "2026-09-23T06:59:00Z",
                  title: String = "周二重置预告", published: String = "2026-09-22T04:31:32Z") -> ResetAnnouncement {
            ResetAnnouncement(id: id, title: title, summary: "I promised a reset for Tuesday.",
                sourceURL: URL(string: "https://x.com/thsottiaux/status/\(id)"),
                announcedAt: date(published), scheduledFor: scheduled.map(date),
                kind: "regular", scope: "unspecified", status: "scheduled")
        }
        func snapshot(_ rows: [ResetAnnouncement]) -> NextResetSnapshot {
            NextResetSnapshot(announcements: rows, sourceCheckedAt: nil, sourceIsFresh: true)
        }
        func top(_ ledger: ResetLedger, _ instant: String) -> ResetTopPresentation {
            ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records,
                                      now: date(instant))
        }
        func delivery(_ id: String, text: String) throws -> ResetAnnouncement {
            let row: [String: Any] = [
                "id": id, "announced_at": "2026-09-22T20:00:00Z", "text": text,
                "source": ["type": "x_post", "author": "thsottiaux",
                           "url": "https://x.com/thsottiaux/status/\(id)"]
            ]
            let data = try JSONSerialization.data(withJSONObject: ["data": [row]])
            guard let result = ResetDeliveryEvidence.announcements(eventsData: nil, historyData: data).first else {
                throw Failure(message: "Synthetic official delivery text was not recognized")
            }
            return result
        }
        let first = post("1001")
        let second = post("2001", scheduled: "2026-09-24T06:59:00Z", title: "周三重置预告")
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([first]), at: date("2026-09-22T04:32:00Z"), occurredWhileAway: true)
        for (instant, countdown) in [
            ("2026-09-22T06:59:59Z", "距预告日开始还剩 0小时0分1秒"),
            ("2026-09-22T07:00:00Z", "预告日内还剩 24小时0分0秒"),
            ("2026-09-23T06:59:59Z", "预告日内还剩 0小时0分1秒")
        ] {
            try check(top(ledger, instant).announcements.map(\.id) == [first.id], "Expected active countdown at \(instant)")
            try check(ResetAnnouncementSummary.countdownText(for: first, now: date(instant), language: .chinese) == countdown,
                      "Incorrect countdown at \(instant)")
        }
        let expired = top(ledger, "2026-09-23T07:00:00Z")
        try check(expired.announcements.isEmpty && !expired.didResetToday, "Expiry must show empty without claiming delivery")
        try check(expired.emptyText(language: .chinese) == "暂无最新重置预告", "Expired empty text mismatch")
        try check(ledger.pendingAnnouncements.map(\.id) == [first.id], "Top-card expiry must preserve unresolved history")
        _ = ledger.ingest(snapshot([second]), at: date("2026-09-22T10:00:00Z"), occurredWhileAway: false)
        try check(top(ledger, "2026-09-22T20:01:00Z").announcements.count == 2, "Independent dates must coexist")
        try check(top(ledger, "2026-09-23T07:00:00Z").announcements.map(\.id) == [second.id], "One expired date must leave the next date visible")

        for (kind, text) in [
            ("banked", "We are loading a banked reset into all accounts."),
            ("regular", "We have reset usage limits for all Codex users.")
        ] {
            let issued = try delivery("1002", text: text)
            try check(issued.deliveryKind == kind && issued.status == "rolling_out", "Both official reset types must have delivery evidence")
            var deliveredLedger = ledger
            _ = deliveredLedger.ingest(snapshot([issued]), at: date("2026-09-22T20:01:00Z"), occurredWhileAway: false)
            let savedDelivery = deliveredLedger.records.first { $0.id == issued.id }?.announcement
            try check(savedDelivery?.relatedAnnouncementIDs?.contains(first.id) == true, "Unique compatible announced day must link to delivery")
            try check(deliveredLedger.pendingAnnouncements.map(\.id) == [second.id], "Delivery must close only its corresponding notice")
            let active = top(deliveredLedger, "2026-09-22T20:01:00Z")
            try check(active.announcements.map(\.id) == [second.id] && active.didResetToday, "Another active notice must remain despite today's delivery")
            try check(top(deliveredLedger, "2026-09-23T06:59:59Z").didResetToday, "Today badge must survive Beijing date rollover")
            try check(!top(deliveredLedger, "2026-09-23T07:00:00Z").didResetToday, "Today badge must end at LA midnight")
            var single = ResetLedger()
            _ = single.ingest(snapshot([first]), at: date("2026-09-22T04:32:00Z"), occurredWhileAway: true)
            _ = single.ingest(snapshot([issued]), at: date("2026-09-22T20:01:00Z"), occurredWhileAway: false)
            try check(top(single, "2026-09-22T20:01:00Z").emptyText(language: .chinese) == "暂无最新重置预告（今天已重置）",
                      "Delivered empty state must show today's reset")
            let encoded = try JSONEncoder().encode(single)
            var restored = try JSONDecoder().decode(ResetLedger.self, from: encoded)
            _ = restored.ingest(snapshot([first]), at: date("2026-09-22T21:00:00Z"), occurredWhileAway: true)
            try check(restored.pendingAnnouncements.isEmpty, "An old source snapshot after reload must not revive a linked delivered notice")
            try check(!top(restored, "2026-09-24T12:00:00Z").didResetToday, "Historical delivery loaded later must not become today's reset")
        }

        // A completion may enrich the same original post instead of a new one.
        var samePost = first
        samePost.status = "rolling_out"
        samePost.deliveryAt = date("2026-09-22T20:00:00Z")
        samePost.deliveryKind = "banked"
        var revised = ResetLedger()
        _ = revised.ingest(snapshot([first]), at: date("2026-09-22T04:32:00Z"), occurredWhileAway: true)
        _ = revised.ingest(snapshot([samePost]), at: date("2026-09-22T20:01:00Z"), occurredWhileAway: false)
        revised = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(revised))
        _ = revised.ingest(snapshot([first]), at: date("2026-09-22T21:00:00Z"), occurredWhileAway: true)
        try check(revised.pendingAnnouncements.isEmpty, "Old same-post scheduled snapshot must not undo persisted completion")
        try check(top(revised, "2026-09-22T21:00:00Z").didResetToday, "Same-post completion date must survive reload")
        var legacy = first
        legacy.status = "completed"
        legacy.deliveryAt = nil
        var legacyLedger = ResetLedger()
        legacyLedger.records = [ResetRecord(id: legacy.id, announcement: legacy, isUnread: false, occurredWhileAway: false)]
        legacyLedger = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(legacyLedger))
        try check(!top(legacyLedger, "2026-09-22T05:00:00Z").didResetToday, "Legacy preannouncement post time is not a delivery date")

        for (scheduled, beforeMidnight, midnight) in [
            ("2026-03-09T06:59:00Z", "2026-03-09T06:59:59Z", "2026-03-09T07:00:00Z"),
            ("2026-11-02T07:59:00Z", "2026-11-02T07:59:59Z", "2026-11-02T08:00:00Z")
        ] {
            let notice = post("3001", scheduled: scheduled, title: "周日重置预告", published: "2026-01-01T00:00:00Z")
            var dstLedger = ResetLedger()
            _ = dstLedger.ingest(snapshot([notice]), at: date("2026-01-01T00:00:01Z"), occurredWhileAway: true)
            try check(top(dstLedger, beforeMidnight).announcements.count == 1, "DST final second must remain visible")
            try check(top(dstLedger, midnight).announcements.isEmpty, "DST midnight must hide expired notice")
        }
        let exact = post("4001", scheduled: "2026-09-22T19:30:00Z", title: "周二 12:30 PDT 重置")
        try check(ResetTopPresentation.make(pending: [exact], records: [], now: date("2026-09-22T19:30:00Z")).announcements.count == 1,
                  "Exact deadline keeps waiting through its announced day")
        try check(ResetTopPresentation.make(pending: [exact], records: [], now: date("2026-09-23T07:00:00Z")).announcements.isEmpty,
                  "Exact deadline stops displaying at its LA day end")
        let unknown = post("5001", scheduled: nil)
        let undated = ResetTopPresentation.make(pending: [unknown], records: [], now: date("2026-10-01T07:00:00Z"))
        try check(undated.announcements.isEmpty && undated.undatedAnnouncements == [unknown],
                  "Unknown date belongs to its own active group without an invented expiry")

        let olderUndated = post("6001", scheduled: nil, published: "2026-09-21T10:00:00Z")
        let secondUndated = post("6002", scheduled: nil, published: "2026-09-22T10:00:00Z")
        let newerUndated = post("6003", scheduled: nil, published: "2026-09-22T21:00:00Z")
        let broadDelivery = try delivery("6004", text: "We are loading a banked reset into all accounts.")
        var undatedLedger = ResetLedger()
        _ = undatedLedger.ingest(snapshot([secondUndated, olderUndated]), at: date("2026-09-22T10:01:00Z"), occurredWhileAway: false)
        try check(top(undatedLedger, "2026-09-22T19:00:00Z").undatedAnnouncements.map(\.id) == ["6001", "6002"],
                  "Undated notices must remain oldest-first before delivery")
        _ = undatedLedger.ingest(snapshot([broadDelivery]), at: date("2026-09-22T20:01:00Z"), occurredWhileAway: false)
        let savedUndated = undatedLedger
        let archived = top(undatedLedger, "2026-09-22T20:01:00Z")
        try check(archived.announcements.isEmpty && archived.undatedAnnouncements.isEmpty,
                  "Later general delivery must clear old undated notices from both home groups")
        try check(archived.archivedUndated == [olderUndated.id: broadDelivery, secondUndated.id: broadDelivery],
                  "Both old undated notices retain their presentation-only delivery reason")
        try check(undatedLedger == savedUndated && undatedLedger.pendingAnnouncements.count == 2,
                  "Presentation archival must not change the ledger or its unresolved state")
        try check(undatedLedger.records.first(where: { $0.id == broadDelivery.id })?.announcement.relatedAnnouncementIDs == nil,
                  "An undated archival reason must not fabricate a completion relationship")
        undatedLedger = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(undatedLedger))
        try check(top(undatedLedger, "2026-09-22T20:01:00Z") == archived,
                  "Undated grouping must survive ledger reload")
        try check(undatedLedger.ingest(snapshot([]), at: date("2026-09-22T20:02:00Z"), occurredWhileAway: true).isEmpty,
                  "Empty polls must not notify after undated archival")
        try check(undatedLedger.ingest(snapshot([olderUndated, secondUndated, broadDelivery]),
                                      at: date("2026-09-22T20:03:00Z"), occurredWhileAway: true).isEmpty,
                  "Unchanged polls must not notify after undated archival")
        _ = undatedLedger.ingest(snapshot([newerUndated]), at: date("2026-09-22T21:01:00Z"), occurredWhileAway: false)
        try check(top(undatedLedger, "2026-09-22T21:01:00Z").undatedAnnouncements == [newerUndated],
                  "A preview published after delivery must remain active")
        var gainedDate = olderUndated
        gainedDate.title = "周三重置预告"
        gainedDate.summary = "A reset on Wednesday."
        gainedDate.scheduledFor = date("2026-09-24T06:59:00Z")
        _ = undatedLedger.ingest(snapshot([gainedDate]), at: date("2026-09-22T21:02:00Z"), occurredWhileAway: false)
        let afterDateAdded = top(undatedLedger, "2026-09-22T21:02:00Z")
        try check(afterDateAdded.announcements == [gainedDate] && afterDateAdded.archivedUndated[gainedDate.id] == nil,
                  "Adding a real date must move a formerly archived preview back to its countdown")
        var excludedDeliveries: [ResetAnnouncement] = []
        for source in [nil, "https://example.com/thsottiaux/status/6004", "https://x.com/not_official/status/6004"] as [String?] {
            var untrusted = broadDelivery
            untrusted.sourceURL = source.flatMap(URL.init(string:))
            excludedDeliveries.append(untrusted)
        }
        var futureDelivery = broadDelivery
        futureDelivery.deliveryAt = date("2026-09-22T22:00:00Z")
        excludedDeliveries.append(futureDelivery)
        var targetedDelivery = broadDelivery
        targetedDelivery.scope = "limited"
        excludedDeliveries.append(targetedDelivery)
        for excluded in excludedDeliveries {
            try check(!ResetDeliveryEvidence.canArchiveUndated(olderUndated, after: excluded, now: date("2026-09-22T21:00:00Z")),
                      "Future, targeted or untrusted delivery must not archive an undated preview")
        }
        var missingPublication = olderUndated
        missingPublication.announcedAt = nil
        try check(!ResetDeliveryEvidence.canArchiveUndated(missingPublication, after: broadDelivery, now: date("2026-09-22T21:00:00Z")),
                  "Undated notices without publication time cannot be ordered against delivery")
        var directPromise = olderUndated
        directPromise.summary = "A one-time reset is coming."
        try check(!ResetDeliveryEvidence.canArchiveUndated(directPromise, after: broadDelivery, now: date("2026-09-22T21:00:00Z")),
                  "An explicitly direct-only preview is incompatible with a banked-only delivery")
        for (previewScope, deliveryScope, shouldArchive) in [
            ("broad", "chatgpt", false), ("all", "chatgpt", false),
            ("codex", "all", true), ("chatgpt", "broad", true),
            ("codex", "chatgpt", false), ("all", "unknown-segment", false),
            ("unknown-segment", "all", false), ("unknown-segment", "unknown-segment", false)
        ] {
            var scopedPreview = olderUndated
            scopedPreview.scope = previewScope
            var scopedDelivery = broadDelivery
            scopedDelivery.scope = deliveryScope
            try check(ResetDeliveryEvidence.canArchiveUndated(scopedPreview, after: scopedDelivery,
                now: date("2026-09-22T21:00:00Z")) == shouldArchive,
                "Delivery scope must cover preview directionally: \(previewScope) -> \(deliveryScope)")
        }
        for (seconds, expected) in [(271, "00:04:31"), (83071, "23:04:31"),
                                    (86791, "1天00:06:31"), (504451, "5天20:07:31"),
                                    (86399, "23:59:59"), (86400, "1天00:00:00")] {
            try check(ResetTopPresentation.elapsedText(seconds: seconds, language: .chinese) == expected,
                      "Elapsed time must use zero-padded 24-hour durations and whole days")
        }
        return checks
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { "Top reset cycle: " + message }
    }
}
