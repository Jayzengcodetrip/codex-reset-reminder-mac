import Foundation
import XCTest
@testable import CodexNotch

final class ResetDeliveryEvidenceTests: XCTestCase {
    func testBegunBankedAndPastDirectDeliveryHaveSourceTime() throws {
        let result = parse([
            post("1001", text: "We are loading a banked reset into all accounts of our Plus, Pro and Business users."),
            post("1002", text: "We have reset usage limits for all Codex users.")
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.id == "1001" })?.deliveryKind, "banked")
        XCTAssertEqual(result.first(where: { $0.id == "1002" })?.deliveryKind, "regular")
        XCTAssertTrue(result.allSatisfy { $0.deliveryAt == date("2026-09-22T18:23:37Z") && $0.status == "rolling_out" })
    }

    func testTypesAndFutureSentencesDoNotOverrideExplicitAction() {
        let result = parse([
            post("1001", text: "We have added a banked reset to everyone's account. You can use it later.", kind: "regular"),
            post("1002", text: "We have reset usage limits for all Codex users. And another one will come later in the day."),
            post("1003", text: "I have reset everyone's Codex usage limits. This is a hard reset given some users had stacked up to three banked resets.")
        ])
        XCTAssertEqual(result.first(where: { $0.id == "1001" })?.deliveryKind, "banked")
        XCTAssertEqual(result.first(where: { $0.id == "1002" })?.deliveryKind, "regular")
        XCTAssertEqual(result.first(where: { $0.id == "1003" })?.deliveryKind, "regular")
    }

    func testFutureNegatedIndirectAndUnknownTextDoesNotBecomeDelivery() {
        let invalid = [
            "We will do the full banked reset today. Lands end of day.",
            "We will give one banked reset for every day you don't have access. First one will land in 3 hours.",
            "We are not loading a banked reset into accounts.",
            "We have not reset usage limits.",
            "Someone said we have reset usage limits for all users.",
            "If we have reset usage limits, you should see it.",
            "I hope we have reset usage limits.",
            "There is a banked reset update."
        ]
        XCTAssertTrue(parse(invalid.enumerated().map { post(String(1100 + $0.offset), text: $0.element, kind: "banked") }).isEmpty)
    }

    func testMalformedAndNonofficialRowsAreIndividuallyIgnored() {
        var bad = post("1001", text: "We have reset usage limits.")
        bad["announced_at"] = "yesterday"
        var wrongAuthor = post("1002", text: "We have reset usage limits.")
        wrongAuthor["source"] = ["type": "x_post", "author": "someoneelse", "url": "https://x.com/thsottiaux/status/1002"]
        var wrongURL = post("1003", text: "We have reset usage limits.")
        wrongURL["source"] = ["type": "x_post", "author": "thsottiaux", "url": "https://example.com/thsottiaux/status/1003"]
        XCTAssertEqual(parse([bad, wrongAuthor, wrongURL, post("1004", text: "We have reset usage limits.")]).map(\.id), ["1004"])
        let result = ResetDeliveryEvidence.announcements(eventsData: Data("bad".utf8), historyData: data(["data": ["latest_reset": post("1005", text: "We are loading a banked reset into accounts.")]]))
        XCTAssertEqual(result.map(\.id), ["1005"])
    }

    func testExplicitDirectAndBankedEventRelations() throws {
        let events = [event("1002", parent: "1001", kind: "automatic_global"), event("2002", parent: "2001", kind: "banked")]
        let result = ResetDeliveryEvidence.announcements(eventsData: data(["events": events]), historyData: nil)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first(where: { $0.id == "1002" })?.relatedAnnouncementIDs, ["1001"])
        XCTAssertEqual(result.first(where: { $0.id == "2002" })?.relatedAnnouncementIDs, ["2001"])
        XCTAssertEqual(result.first(where: { $0.id == "2002" })?.deliveryKind, "banked")
    }

    func testLandedBankedIsDeliveryButWillLandIsNot() {
        let result = parse([
            post("1001", text: "The banked reset has landed. Happy coding!"),
            post("1002", text: "The banked reset will land tonight."),
            post("1003", text: "Someone told me the banked reset has landed.")
        ])
        XCTAssertEqual(result.map(\.id), ["1001"])
        XCTAssertEqual(result.first?.deliveryKind, "banked")
    }

    func testUnconfirmedAndSecondaryEventsCannotCloseAnything() {
        var expired = event("1002", parent: "1001", kind: "banked")
        expired["lifecycle"] = "expired_unconfirmed"
        var secondary = event("2002", parent: "2001", kind: "banked")
        secondary["evidence"] = [["role": "confirmation", "tier": "secondary", "verificationStatus": "primary_verified", "sourceUrl": "https://x.com/thsottiaux/status/2002", "publishedAt": "2026-09-22T18:23:37Z"]]
        XCTAssertTrue(ResetDeliveryEvidence.announcements(eventsData: data(["events": [expired, secondary]]), historyData: nil).isEmpty)
    }

    func testUniqueUntypedSameDayAnnouncementCanMatchBanked() throws {
        let delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts.")]).first)
        let result = ResetDeliveryEvidence.associate([delivery], pending: [planned("1001")])
        XCTAssertEqual(result.first?.relatedAnnouncementIDs, ["1001"])
        XCTAssertTrue(result.first?.completionEvidence?.contains("仅有一条") == true)
    }

    func testAmbiguousOtherDayRestrictedAndCompensationStayUnlinked() throws {
        let delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts.")]).first)
        XCTAssertNil(ResetDeliveryEvidence.associate([delivery], pending: [planned("1001"), planned("1003")]).first?.relatedAnnouncementIDs)
        var tomorrow = planned("1001")
        tomorrow.scheduledFor = date("2026-09-24T06:59:00Z")
        XCTAssertNil(ResetDeliveryEvidence.associate([delivery], pending: [tomorrow]).first?.relatedAnnouncementIDs)
        var explicitDirect = planned("1001")
        explicitDirect.summary = "There will be a one-time reset on Tuesday."
        XCTAssertNil(ResetDeliveryEvidence.associate([delivery], pending: [explicitDirect]).first?.relatedAnnouncementIDs)
        var compensation = delivery
        compensation.summary += " This is compensation for affected users."
        XCTAssertNil(ResetDeliveryEvidence.associate([compensation], pending: [planned("1001")]).first?.relatedAnnouncementIDs)
    }

    func testExplicitLinkSurvivesAssociationAndDuplicateAliasesCountOnce() throws {
        var delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts.")]).first)
        delivery.relatedAnnouncementIDs = ["1000"]
        XCTAssertEqual(ResetDeliveryEvidence.associate([delivery], pending: [planned("1001")]).first?.relatedAnnouncementIDs, ["1000"])
        delivery.relatedAnnouncementIDs = nil
        var alias = planned("alias")
        alias.sourceURL = URL(string: "https://twitter.com/thsottiaux/status/1001")
        XCTAssertEqual(ResetDeliveryEvidence.associate([delivery], pending: [planned("1001"), alias]).first?.relatedAnnouncementIDs, ["1001", "alias"])
    }

    func testTargetedOrCompensationAnnouncementCannotMatchGeneralDelivery() throws {
        let delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts.")]).first)
        for scope in ["limited", "affected", "targeted", "partial"] {
            var candidate = planned("1001")
            candidate.scope = scope
            XCTAssertNil(ResetDeliveryEvidence.associate([delivery], pending: [candidate]).first?.relatedAnnouncementIDs)
        }
        var compensation = planned("1001")
        compensation.summary = "On Tuesday we will compensate affected users with a reset."
        XCTAssertNil(ResetDeliveryEvidence.associate([delivery], pending: [compensation]).first?.relatedAnnouncementIDs)
    }

    func testEnrichmentKeepsSourceTitleDeadlineAndExplicitRelationWithFullText() throws {
        let fullText = "We are loading a banked reset into all accounts. This paragraph is complete."
        let result = ResetDeliveryEvidence.announcements(eventsData: data(["events": [event("1002", parent: "1001", kind: "banked")]]), historyData: data(["data": [post("1002", text: fullText)]]))
        XCTAssertEqual(result.first?.summary, fullText)
        XCTAssertEqual(result.first?.relatedAnnouncementIDs, ["1001"])
        var base = planned("1002")
        base.title = "原接口中文标题"
        let merged = ResetDeliveryEvidence.merge(base: [base], supplements: result)
        XCTAssertEqual(merged.first?.title, base.title)
        XCTAssertEqual(merged.first?.scheduledFor, base.scheduledFor)
        XCTAssertEqual(merged.first?.deliveryAt, result.first?.deliveryAt)
        XCTAssertEqual(merged.first?.summary, fullText)
    }

    func testTargetedDeliveriesRemainInHistoryWithoutGeneralResetClaim() throws {
        let delivered = parse([
            post("1002", text: "Added a banked reset to 500k users of Codex."),
            post("1003", text: "We have reset usage limits to compensate affected users.")
        ])
        XCTAssertEqual(delivered.count, 2)
        XCTAssertTrue(delivered.allSatisfy { $0.scope == "limited" })
        XCTAssertTrue(delivered.allSatisfy { !ResetDeliveryEvidence.isGeneralDelivery($0) })
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot(delivered), at: date("2026-09-22T20:00:00Z"), occurredWhileAway: false)
        XCTAssertEqual(ledger.records.count, 2)
        let broad = try XCTUnwrap(parse([post("1004", text: "We are loading a banked reset into all accounts.")]).first)
        XCTAssertTrue(ResetDeliveryEvidence.isGeneralDelivery(broad))
    }

    func testLedgerDoesNotReassignDeliveryWhenAnotherPreviewArrivesLate() throws {
        let delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts.")]).first)
        let now = date("2026-09-22T20:00:00Z")
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([planned("1001")]), at: now, occurredWhileAway: false)
        _ = ledger.ingest(snapshot([planned("1001"), delivery]), at: now, occurredWhileAway: false)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "1002" })?.announcement.relatedAnnouncementIDs, ["1001"])
        XCTAssertTrue(ledger.pendingAnnouncements.isEmpty)
        let changes = ledger.ingest(snapshot([planned("1001"), planned("1003"), delivery]), at: now, occurredWhileAway: false)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "1002" })?.announcement.relatedAnnouncementIDs, ["1001"])
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), ["1003"])
        XCTAssertEqual(changes.map(\.id), ["1003"])
    }

    func testLedgerUsesCorrectedTargetAndIgnoresKnownOldSchedule() throws {
        let delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts.")]).first)
        let now = date("2026-09-22T20:00:00Z")
        let original = planned("1001")
        var revised = original
        revised.title = "周四重置预告"
        revised.summary = "A reset on Thursday."
        revised.scheduledFor = date("2026-09-25T06:59:00Z")
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([original]), at: now, occurredWhileAway: false)
        _ = ledger.ingest(snapshot([revised, delivery]), at: now, occurredWhileAway: false)
        XCTAssertNil(ledger.records.first(where: { $0.id == "1002" })?.announcement.relatedAnnouncementIDs)
        XCTAssertEqual(ledger.pendingAnnouncements.first?.scheduledFor, revised.scheduledFor)
        let changes = ledger.ingest(snapshot([original, delivery]), at: now, occurredWhileAway: false)
        XCTAssertTrue(changes.isEmpty)
        XCTAssertNil(ledger.records.first(where: { $0.id == "1002" })?.announcement.relatedAnnouncementIDs)
        XCTAssertEqual(ledger.pendingAnnouncements.first?.scheduledFor, revised.scheduledFor)
    }

    func testLedgerAuxiliaryFailurePreservesFullTextAndDoesNotNotifyAgain() throws {
        let delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts. Complete original text.")]).first)
        let now = date("2026-09-22T20:00:00Z")
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([planned("1001")]), at: now, occurredWhileAway: false)
        _ = ledger.ingest(snapshot([planned("1001"), delivery]), at: now, occurredWhileAway: false)
        ledger.markRead(id: "1002")
        let previousVersions = ledger.versions["1002"]
        var sparse = delivery
        sparse.status = nil
        sparse.summary = "原帖摘录：We are loading…"
        sparse.kind = "regular"
        sparse.scope = "broad"
        sparse.deliveryAt = nil
        sparse.deliveryKind = nil
        sparse.relatedAnnouncementIDs = nil
        sparse.completionEvidence = nil
        XCTAssertTrue(ledger.ingest(snapshot([sparse]), at: now, occurredWhileAway: false).isEmpty)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "1002" })?.announcement.summary, delivery.summary)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "1002" })?.isUnread, false)
        XCTAssertEqual(ledger.versions["1002"], previousVersions)
        XCTAssertTrue(ledger.pendingAnnouncements.isEmpty)
        XCTAssertTrue(ledger.ingest(snapshot([delivery]), at: now, occurredWhileAway: false).isEmpty)
    }

    func testExplicitCancellationIsNotOverwrittenBySavedDelivery() throws {
        let delivery = try XCTUnwrap(parse([post("1002", text: "We are loading a banked reset into all accounts.")]).first)
        let now = date("2026-09-22T20:00:00Z")
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([planned("1001")]), at: now, occurredWhileAway: false)
        _ = ledger.ingest(snapshot([delivery]), at: now, occurredWhileAway: false)
        var cancelled = delivery
        cancelled.status = "cancelled"
        cancelled.summary = "发放已取消。"
        cancelled.deliveryAt = nil
        cancelled.relatedAnnouncementIDs = nil
        _ = ledger.ingest(snapshot([cancelled]), at: now, occurredWhileAway: false)
        let current = try XCTUnwrap(ledger.records.first(where: { $0.id == "1002" })?.announcement)
        XCTAssertEqual(current.status, "cancelled")
        XCTAssertEqual(current.summary, "发放已取消。")
        XCTAssertTrue(!ResetDeliveryEvidence.isGeneralDelivery(current))
        _ = ledger.ingest(snapshot([delivery]), at: now, occurredWhileAway: false)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "1002" })?.announcement.status, "cancelled")
    }

    func testFullTextFailureWithEventFeedStillOnlineDoesNotDowngradeOrNotify() throws {
        let eventData = data(["events": [event("1002", parent: "1001", kind: "banked")]])
        let originalText = "We are loading a banked reset into all accounts. This is the complete source text."
        let full = ResetDeliveryEvidence.announcements(eventsData: eventData,
            historyData: data(["data": [post("1002", text: originalText)]]))
        var base = try XCTUnwrap(full.first)
        base.title = "接口中文标题"
        base.summary = "原帖摘录：We are loading…"
        base.deliveryAt = nil
        base.deliveryKind = nil
        base.relatedAnnouncementIDs = nil
        base.completionEvidence = nil
        base.status = nil
        let combined = ResetDeliveryEvidence.merge(base: [base], supplements: full)
        let eventOnly = ResetDeliveryEvidence.merge(base: [base], supplements:
            ResetDeliveryEvidence.announcements(eventsData: eventData, historyData: nil))
        var ledger = ResetLedger()
        let now = date("2026-09-22T20:00:00Z")
        _ = ledger.ingest(snapshot(combined), at: now, occurredWhileAway: false)
        XCTAssertTrue(ledger.ingest(snapshot(eventOnly), at: now, occurredWhileAway: false).isEmpty)
        XCTAssertEqual(ledger.records.first?.announcement.summary, originalText)
        let textOnly = ResetDeliveryEvidence.merge(base: [base], supplements:
            ResetDeliveryEvidence.announcements(eventsData: nil,
                historyData: data(["data": [post("1002", text: originalText)]])))
        XCTAssertTrue(ledger.ingest(snapshot(textOnly), at: now, occurredWhileAway: false).isEmpty)
        XCTAssertEqual(ledger.records.first?.announcement.status, "completed")
    }

    func testDeliveryEvidenceUpgradeBaselinePreservesFlagsAndStillReportsNewMessages() throws {
        let cutoff = date("2026-09-22T20:00:00Z")
        let deliveries = parse((4001...4004).map {
            post(String($0), text: "We are loading a banked reset into all accounts. Original text \($0).")
        })
        func delivery(_ id: String) -> ResetAnnouncement { deliveries.first(where: { $0.id == id })! }
        func ordinary(_ id: String) -> ResetAnnouncement {
            var result = delivery(id)
            result.summary = "旧接口摘要"
            result.status = nil
            result.deliveryAt = nil
            result.deliveryKind = nil
            result.relatedAnnouncementIDs = nil
            result.completionEvidence = nil
            return result
        }
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([ordinary("4001")]), at: cutoff, occurredWhileAway: false)
        // An ordinary successful poll with auxiliary failure does not establish that baseline.
        _ = ledger.ingest(snapshot([ordinary("4001")]), at: cutoff.addingTimeInterval(60), occurredWhileAway: true)
        XCTAssertNil(ledger.deliveryEvidenceBaselineCompleted)
        _ = ledger.ingest(snapshot([ordinary("4002")]), at: cutoff.addingTimeInterval(120), occurredWhileAway: true)
        let oldRead = try XCTUnwrap(ledger.records.first(where: { $0.id == "4001" }))
        let oldUnread = try XCTUnwrap(ledger.records.first(where: { $0.id == "4002" }))
        // Loading a schema-one ledger without this new optional field still works.
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
        saved.removeValue(forKey: "deliveryEvidenceBaselineCompleted")
        ledger = try JSONDecoder().decode(ResetLedger.self, from: data(saved))
        var genuinelyNew = delivery("4004")
        genuinelyNew.deliveryAt = cutoff.addingTimeInterval(180)
        genuinelyNew.announcedAt = genuinelyNew.deliveryAt
        var lateOrdinary = ordinary("4001")
        lateOrdinary = ResetAnnouncement(id: "4005", title: lateOrdinary.title, summary: lateOrdinary.summary,
            sourceURL: URL(string: "https://x.com/thsottiaux/status/4005"), announcedAt: lateOrdinary.announcedAt,
            scheduledFor: nil, kind: "regular", scope: "unspecified", status: nil)
        let changes = ledger.ingest(snapshot([delivery("4001"), delivery("4002"), delivery("4003"), genuinelyNew, lateOrdinary]),
                                    at: cutoff.addingTimeInterval(240), occurredWhileAway: true)
        XCTAssertEqual(Set(changes.map(\.id)), Set(["4004", "4005"]))
        XCTAssertEqual(ledger.deliveryEvidenceBaselineCompleted, true)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "4001" })?.isUnread, oldRead.isUnread)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "4001" })?.occurredWhileAway, oldRead.occurredWhileAway)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "4002" })?.isUnread, oldUnread.isUnread)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "4002" })?.occurredWhileAway, oldUnread.occurredWhileAway)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "4003" })?.isUnread, false)
        XCTAssertEqual(ledger.records.first(where: { $0.id == "4003" })?.occurredWhileAway, false)
        var laterRevision = delivery("4001")
        laterRevision.summary += " A material follow-up after the baseline."
        XCTAssertEqual(ledger.ingest(snapshot([laterRevision]), at: cutoff.addingTimeInterval(360), occurredWhileAway: false).map(\.id), ["4001"])
    }

    private func snapshot(_ announcements: [ResetAnnouncement]) -> NextResetSnapshot {
        NextResetSnapshot(announcements: announcements, sourceCheckedAt: date("2026-09-22T20:00:00Z"), sourceIsFresh: true)
    }

    private func planned(_ id: String) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "周二重置预告", summary: "I promised a reset for Tuesday.",
                          sourceURL: URL(string: "https://x.com/thsottiaux/status/\(id)"),
                          announcedAt: date("2026-09-22T04:31:32Z"), scheduledFor: date("2026-09-23T06:59:00Z"),
                          kind: "regular", scope: "unspecified", status: "scheduled")
    }
    private func post(_ id: String, text: String, kind: String = "regular") -> [String: Any] {
        ["id": id, "reset_type": kind, "announced_at": "2026-09-22T18:23:37Z", "text": text,
         "source": ["type": "x_post", "author": "thsottiaux", "url": "https://x.com/thsottiaux/status/\(id)"]]
    }
    private func event(_ id: String, parent: String, kind: String) -> [String: Any] {
        ["eventId": "synthetic-\(id)", "lifecycle": "confirmed", "verificationStatus": "primary_verified", "resetType": kind,
         "confirmedAt": "2026-09-22T18:23:37Z", "evidence": [
            ["role": "announcement", "tier": "primary", "verificationStatus": "primary_verified", "sourceUrl": "https://x.com/thsottiaux/status/\(parent)", "publishedAt": "2026-09-22T04:31:32Z"],
            ["role": "confirmation", "tier": "primary", "verificationStatus": "primary_verified", "sourceUrl": "https://x.com/thsottiaux/status/\(id)", "publishedAt": "2026-09-22T18:23:37Z"]
         ]]
    }
    private func parse(_ posts: [[String: Any]]) -> [ResetAnnouncement] {
        ResetDeliveryEvidence.announcements(eventsData: nil, historyData: data(["data": posts]))
    }
    private func data(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
    private func date(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }
}
