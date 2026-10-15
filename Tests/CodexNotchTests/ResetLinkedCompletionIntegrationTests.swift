import Foundation
import XCTest
@testable import CodexNotch

final class ResetLinkedCompletionIntegrationTests: XCTestCase {
    private let shortURL = URL(string: "https://t.co/SyntheticReset")!
    private let previewURL = URL(string: "https://twitter.com/thsottiaux/status/8001")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func data(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }

    private func confirmation() throws -> ResetAnnouncement {
        let events = data(["events": [[
            "eventId": "synthetic-event", "resetType": "automatic_global", "lifecycle": "scheduled",
            "verificationStatus": "primary_verified", "announcementAt": "2026-07-15T10:00:00Z",
            "sourceUrl": previewURL.absoluteString, "summary": ["en": "A scheduled automatic reset"],
            "evidence": [["role": "timing_update", "tier": "primary",
                          "verificationStatus": "primary_verified", "sourceUrl": previewURL.absoluteString,
                          "publishedAt": "2026-07-15T10:00:00Z"]]
        ]]])
        let history = data(["data": [[
            "id": "8002", "reset_type": "regular", "announced_at": "2026-07-15T11:00:00Z",
            "text": "Done and dusted \(shortURL.absoluteString)",
            "source": ["type": "x_post", "author": "thsottiaux",
                       "url": "https://x.com/thsottiaux/status/8002"]
        ]]])
        return try XCTUnwrap(ResetDeliveryEvidence.announcements(
            eventsData: events, historyData: history, resolvedLinks: [shortURL: previewURL]).first)
    }

    private func snapshot(_ values: [ResetAnnouncement]) -> NextResetSnapshot {
        NextResetSnapshot(announcements: values, sourceCheckedAt: nil, sourceIsFresh: true)
    }

    func testPreviouslyFetchedShortReplyAdvancesClockAndCompletesItsLinkedPreview() throws {
        let completed = try confirmation()
        var raw = completed
        raw.status = nil; raw.deliveryAt = nil; raw.deliveryKind = nil
        raw.relatedAnnouncementIDs = nil; raw.completionEvidence = nil
        let prior = ResetAnnouncement(id: "7999", title: "Earlier delivery", summary: "We have reset usage limits.",
            sourceURL: URL(string: "https://x.com/thsottiaux/status/7999"),
            announcedAt: date("2026-07-13T11:00:00Z"), scheduledFor: nil,
            kind: "regular", scope: "all", status: "completed",
            deliveryAt: date("2026-07-13T11:00:00Z"))
        let preview = ResetAnnouncement(id: "8001", title: "Reset ahead", summary: "Landing within the next 2 hours",
            sourceURL: previewURL, announcedAt: date("2026-07-15T10:00:00Z"),
            scheduledFor: date("2026-07-15T12:00:00Z"), kind: "regular", scope: "all", status: "scheduled")
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([prior, preview, raw]), at: date("2026-07-15T11:01:00Z"), occurredWhileAway: false)
        let before = ResetTopPresentation.make(pending: ledger.pendingAnnouncements,
            records: ledger.records, now: date("2026-07-15T11:01:00Z"))
        XCTAssertEqual(before.secondsSinceLastDelivery, 2 * 86400 + 60)

        let changed = ledger.ingest(snapshot([completed]), at: date("2026-07-15T11:01:00Z"), occurredWhileAway: false)
        XCTAssertEqual(changed.map(\.id), ["8002"])
        let after = ResetTopPresentation.make(pending: ledger.pendingAnnouncements,
            records: ledger.records, now: date("2026-07-15T11:01:00Z"))
        XCTAssertEqual(after.secondsSinceLastDelivery, 60)
        XCTAssertEqual(after.latestDeliveryOrigin, .publicAnnouncement)
        XCTAssertFalse(ledger.pendingAnnouncements.contains { $0.id == preview.id })
        XCTAssertEqual(ledger.records.first { $0.id == "8002" }?.announcement.relatedAnnouncementIDs, ["8001"])

        ledger.markRead(id: "8002")
        XCTAssertTrue(ledger.ingest(snapshot([completed]), at: date("2026-07-15T11:02:00Z"), occurredWhileAway: false).isEmpty)
        var reloaded = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(ledger))
        // Simulate an unavailable optional resolver/context feed and then an absent record.
        XCTAssertTrue(reloaded.ingest(snapshot([raw]), at: date("2026-07-15T11:03:00Z"), occurredWhileAway: false).isEmpty)
        XCTAssertTrue(reloaded.ingest(snapshot([]), at: date("2026-07-15T11:04:00Z"), occurredWhileAway: false).isEmpty)
        let restored = ResetTopPresentation.make(pending: reloaded.pendingAnnouncements,
            records: reloaded.records, now: date("2026-07-15T11:04:00Z"))
        XCTAssertEqual(restored.secondsSinceLastDelivery, 240)
        XCTAssertFalse(reloaded.records.first { $0.id == "8002" }!.isUnread)
        XCTAssertFalse(reloaded.pendingAnnouncements.contains { $0.id == preview.id })
    }
}
