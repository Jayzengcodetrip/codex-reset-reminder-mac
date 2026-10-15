import Foundation
import XCTest
@testable import CodexNotch

final class ResetLinkedCompletionTests: XCTestCase {
    private let shortURL = URL(string: "https://t.co/SyntheticA")!
    private let previewURL = URL(string: "https://x.com/thsottiaux/status/8001")!

    func testShortCompletionUsesVerifiedLinkedPreviewAndExactPublicationTime() throws {
        let completion = try XCTUnwrap(parse().first)
        XCTAssertEqual(completion.id, "8002")
        XCTAssertEqual(completion.status, "completed")
        XCTAssertEqual(completion.deliveryKind, "regular")
        XCTAssertEqual(completion.deliveryAt, date("2026-07-07T18:30:00Z"))
        XCTAssertEqual(completion.announcedAt, completion.deliveryAt)
        XCTAssertEqual(completion.relatedAnnouncementIDs, ["8001"])
        XCTAssertTrue(completion.completionEvidence?.contains("直接引用") == true)
    }

    func testAlreadyExpandedOfficialLinkNeedsNoNetworkAndSupportsBanked() throws {
        let bankedPost = post(text: "It's done. https://twitter.com/thsottiaux/status/8001", kind: "banked")
        let events = [event(kind: "banked", role: "announcement")]
        let result = parse(posts: [bankedPost], events: events, resolved: [:])
        XCTAssertEqual(result.first?.deliveryKind, "banked")
        XCTAssertEqual(result.first?.status, "completed")
        XCTAssertTrue(ResetDeliveryEvidence.shortCompletionLinks(historyData: data(["data": [bankedPost]])).isEmpty)
    }

    func testBareOrUnrelatedShortConfirmationAndFailedResolutionStayUnconfirmed() {
        XCTAssertTrue(parse(posts: [post(text: "Done and dusted")]).isEmpty)
        XCTAssertTrue(parse(resolved: [:]).isEmpty)
        XCTAssertTrue(parse(resolved: [shortURL: URL(string: "https://x.com/thsottiaux/status/8999")!]).isEmpty)
        XCTAssertTrue(parse(events: []).isEmpty)
        XCTAssertTrue(ResetDeliveryEvidence.announcements(eventsData: Data("bad".utf8),
            historyData: data(["data": [post()]]), resolvedLinks: [shortURL: previewURL]).isEmpty)
    }

    func testNegatedHypotheticalQuotedAndExtraClausesDoNotTriggerLookupOrCompletion() {
        let texts = [
            "Not done and dusted https://t.co/SyntheticA",
            "If done and dusted https://t.co/SyntheticA",
            "I hope it's done https://t.co/SyntheticA",
            "Someone said done and dusted https://t.co/SyntheticA",
            "\"Done and dusted\" https://t.co/SyntheticA",
            "Done and dusted tomorrow https://t.co/SyntheticA",
            "Done and dusted https://t.co/SyntheticA but not the reset",
            "Done and dusted https://t.co/SyntheticA https://t.co/Another",
            "Done and dusted? https://t.co/SyntheticA"
        ]
        let rows = texts.map { post(text: $0) }
        XCTAssertTrue(parse(posts: rows).isEmpty)
        XCTAssertTrue(ResetDeliveryEvidence.shortCompletionLinks(historyData: data(["data": rows])).isEmpty)
    }

    func testNonofficialAuthorOrSourceIsRejected() {
        var wrongAuthor = post()
        wrongAuthor["source"] = ["type": "x_post", "author": "other", "url": "https://x.com/thsottiaux/status/8002"]
        var wrongSource = post()
        wrongSource["source"] = ["type": "x_post", "author": "thsottiaux", "url": "https://x.com/other/status/8002"]
        XCTAssertTrue(parse(posts: [wrongAuthor, wrongSource]).isEmpty)
        XCTAssertTrue(ResetDeliveryEvidence.shortCompletionLinks(historyData: data(["data": [wrongAuthor, wrongSource]])).isEmpty)
        XCTAssertTrue(parse(resolved: [shortURL: URL(string: "https://x.com/other/status/8001")!]).isEmpty)
    }

    func testFutureEqualAndSelfReferencesDoNotConfirm() {
        XCTAssertTrue(parse(events: [event(publishedAt: "2026-07-07T19:00:00Z")]).isEmpty)
        XCTAssertTrue(parse(events: [event(publishedAt: "2026-07-07T18:30:00Z")]).isEmpty)
        XCTAssertTrue(parse(posts: [post(id: "8001")]).isEmpty)
    }

    func testEventAndEvidenceMustBeVerifiedTypedScheduledAnnouncement() {
        for (key, value) in [("lifecycle", "cancelled"), ("verificationStatus", "unverified"),
                             ("resetType", "unknown")] {
            var invalid = event()
            invalid[key] = value
            XCTAssertTrue(parse(events: [invalid]).isEmpty, key)
        }
        for (key, value) in [("tier", "secondary"), ("verificationStatus", "unverified"),
                             ("role", "observation"), ("sourceUrl", "https://x.com/other/status/8001")] {
            var invalid = event()
            var item = (invalid["evidence"] as! [[String: Any]])[0]
            item[key] = value
            invalid["evidence"] = [item]
            XCTAssertTrue(parse(events: [invalid]).isEmpty, key)
        }
    }

    func testKnownTypeConflictAndAmbiguousEventKindsRemainUnconfirmed() {
        XCTAssertTrue(parse(events: [event(kind: "banked")]).isEmpty)
        XCTAssertTrue(parse(posts: [post(kind: "banked")]).isEmpty)
        XCTAssertTrue(parse(events: [event(), event(kind: "banked")]).isEmpty)
        var contradictory = event()
        contradictory["targetWindowText"] = "We will give everyone a banked reset."
        XCTAssertTrue(parse(events: [contradictory]).isEmpty)
    }

    func testCompensationAndRestrictedScopesDoNotBecomeGeneralCompletion() {
        for scope in ["targeted", "limited", "individual", "unknown_group"] {
            var limited = event()
            limited["scope"] = scope
            XCTAssertTrue(parse(events: [limited]).isEmpty, scope)
        }
        var compensation = event()
        compensation["summary"] = ["en": "Compensation for affected users."]
        XCTAssertTrue(parse(events: [compensation]).isEmpty)
        var targetedPost = post()
        targetedPost["scope"] = "targeted"
        XCTAssertTrue(parse(posts: [targetedPost]).isEmpty)
        var compensationPost = post()
        compensationPost["title"] = "Reset refund for selected users"
        XCTAssertTrue(parse(posts: [compensationPost]).isEmpty)
    }

    func testUnsafeLinksAreNeverRequestedOrTrusted() {
        let unsafe = ["http://t.co/SyntheticA", "https://other.example/SyntheticA",
                      "https://t.co/a/b", "https://t.co/SyntheticA?x=1", "https://t.co/SyntheticA#part",
                      "https://user:pass@t.co/SyntheticA", "https://t.co:8443/SyntheticA"]
        for link in unsafe {
            let row = post(text: "Done and dusted \(link)")
            XCTAssertTrue(ResetDeliveryEvidence.shortCompletionLinks(historyData: data(["data": [row]])).isEmpty, link)
            XCTAssertTrue(parse(posts: [row], resolved: [URL(string: link)!: previewURL]).isEmpty, link)
        }
        for target in ["http://x.com/thsottiaux/status/8001", "https://evil.example/thsottiaux/status/8001",
                       "https://x.com:8443/thsottiaux/status/8001", "https://user@x.com/thsottiaux/status/8001",
                       "https://x.com/thsottiaux/status/8001?next=evil"] {
            XCTAssertTrue(parse(resolved: [shortURL: URL(string: target)!]).isEmpty, target)
        }
    }

    func testLookupsAreUniqueNewestFirstAndBoundedToFour() {
        var rows = (1...6).map { number -> [String: Any] in
            var row = post(id: String(8100 + number), text: "Done and dusted https://t.co/Synthetic\(number)")
            row["announced_at"] = "2026-07-07T18:0\(number):00Z"
            return row
        }
        rows.append(rows[5])
        let links = ResetDeliveryEvidence.shortCompletionLinks(historyData: data(["data": rows]))
        XCTAssertEqual(links.map(\.absoluteString), (3...6).reversed().map { "https://t.co/Synthetic\($0)" })
    }

    func testOriginalExplicitDirectAndBankedRecognitionDoesNotRequireLinkOrEvents() {
        let rows = [post(id: "8201", text: "We have reset usage limits for all Codex users."),
                    post(id: "8202", text: "We have added a banked reset to everyone's account.", kind: "banked")]
        let result = ResetDeliveryEvidence.announcements(eventsData: nil, historyData: data(["data": rows]))
        XCTAssertEqual(Set(result.map(\.id)), ["8201", "8202"])
        XCTAssertEqual(Set(result.compactMap(\.deliveryKind)), ["regular", "banked"])
    }

    func testLinkedCompletionAdvancesElapsedTimeAndSurvivesAuxiliaryFailureAndReload() throws {
        let sourceTime = date("2026-07-07T18:30:00Z")
        let now = sourceTime.addingTimeInterval(600)
        let preview = ResetAnnouncement(id: "8001", title: "预计两小时内重置", summary: "Landing within two hours.",
            sourceURL: previewURL, announcedAt: date("2026-07-07T17:00:00Z"),
            scheduledFor: date("2026-07-07T19:00:00Z"), kind: "regular", scope: "unspecified", status: "scheduled")
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([preview]), at: sourceTime.addingTimeInterval(-60), occurredWhileAway: false)
        let delivered = try XCTUnwrap(parse().first)
        _ = ledger.ingest(snapshot([delivered]), at: now, occurredWhileAway: false)
        XCTAssertTrue(ledger.pendingAnnouncements.isEmpty)
        var presentation = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now)
        XCTAssertEqual(presentation.secondsSinceLastDelivery, 600)
        XCTAssertEqual(presentation.latestDeliveryOrigin, .publicAnnouncement)
        ledger.markRead(id: delivered.id)
        var sparse = delivered
        sparse.status = nil
        sparse.deliveryAt = nil
        sparse.deliveryKind = nil
        sparse.relatedAnnouncementIDs = nil
        sparse.completionEvidence = nil
        sparse.summary = "第三方接口旧摘要"
        XCTAssertTrue(ledger.ingest(snapshot([sparse]), at: now.addingTimeInterval(30), occurredWhileAway: false).isEmpty)
        ledger = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(ledger))
        presentation = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: now.addingTimeInterval(30))
        XCTAssertEqual(presentation.secondsSinceLastDelivery, 630)
        XCTAssertEqual(ledger.records.first(where: { $0.id == delivered.id })?.isUnread, false)
        XCTAssertEqual(ledger.records.first(where: { $0.id == delivered.id })?.announcement.summary, delivered.summary)
        let laterPreview = ResetAnnouncement(id: "8301", title: preview.title, summary: preview.summary,
            sourceURL: URL(string: "https://x.com/thsottiaux/status/8301")!, announcedAt: now,
            scheduledFor: preview.scheduledFor, kind: preview.kind, scope: preview.scope, status: preview.status)
        _ = ledger.ingest(snapshot([laterPreview]), at: now.addingTimeInterval(60), occurredWhileAway: false)
        XCTAssertEqual(ledger.pendingAnnouncements.map(\.id), ["8301"])
    }

    private func parse(posts: [[String: Any]]? = nil, events: [[String: Any]]? = nil,
                       resolved: [URL: URL]? = nil) -> [ResetAnnouncement] {
        ResetDeliveryEvidence.announcements(eventsData: data(["events": events ?? [event()]]),
            historyData: data(["data": posts ?? [post()]]), resolvedLinks: resolved ?? [shortURL: previewURL])
    }
    private func post(id: String = "8002", text: String = "Done and dusted https://t.co/SyntheticA",
                      kind: String = "regular") -> [String: Any] {
        ["id": id, "reset_type": kind, "announced_at": "2026-07-07T18:30:00Z", "text": text,
         "source": ["type": "x_post", "author": "thsottiaux", "url": "https://x.com/thsottiaux/status/\(id)"]]
    }
    private func event(kind: String = "automatic_global", role: String = "timing_update",
                       publishedAt: String = "2026-07-07T17:00:00Z") -> [String: Any] {
        ["eventId": "synthetic-event", "resetType": kind, "lifecycle": "scheduled",
         "verificationStatus": "primary_verified", "targetWindowText": "Landing within two hours",
         "evidence": [["role": role, "tier": "primary", "verificationStatus": "primary_verified",
                       "sourceUrl": previewURL.absoluteString, "publishedAt": publishedAt]]]
    }
    private func snapshot(_ announcements: [ResetAnnouncement]) -> NextResetSnapshot {
        NextResetSnapshot(announcements: announcements, sourceCheckedAt: date("2026-07-07T18:40:00Z"), sourceIsFresh: true)
    }
    private func data(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value) }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
