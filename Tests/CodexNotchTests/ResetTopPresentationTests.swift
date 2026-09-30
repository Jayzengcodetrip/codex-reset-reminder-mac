import Foundation
import XCTest
@testable import CodexNotch

final class ResetTopPresentationTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func post(_ id: String = "tuesday", scheduled: String? = "2026-09-23T06:59:00Z",
                      status: String? = "scheduled", kind: String = "regular",
                      published: String = "2026-09-22T04:31:32Z", delivery: String? = nil,
                      title: String = "周二重置预告") -> ResetAnnouncement {
        var announcement = ResetAnnouncement(id: id, title: title, summary: title, sourceURL: nil,
            announcedAt: date(published), scheduledFor: scheduled.map(date),
            kind: kind, scope: "all", status: status)
        announcement.deliveryAt = delivery.map(date)
        return announcement
    }

    private func record(_ post: ResetAnnouncement) -> ResetRecord {
        ResetRecord(id: post.id, announcement: post, isUnread: false, occurredWhileAway: false)
    }

    private func state(pending: [ResetAnnouncement] = [], records: [ResetAnnouncement] = [],
                       at: String) -> ResetTopPresentation {
        .make(pending: pending, records: records.map(record), now: date(at))
    }

    func testElapsedClockFormatsEveryRequestedExampleAndDayBoundary() {
        for (seconds, expected) in [(271, "00:04:31"), (83071, "23:04:31"),
                                    (86791, "1天00:06:31"), (504451, "5天20:07:31"),
                                    (86399, "23:59:59"), (86400, "1天00:00:00")] {
            XCTAssertEqual(ResetTopPresentation.elapsedText(seconds: seconds, language: .chinese), expected)
        }
    }

    func testElapsedClockUsesLatestGeneralDeliveryNotCheckOrExpiredPreview() {
        let previous = post("previous", scheduled: nil, status: "rolling_out", delivery: "2026-09-22T06:00:00Z")
        let latest = post("latest", scheduled: nil, status: "rolling_out", delivery: "2026-09-22T06:59:59Z")
        var targeted = post("targeted", scheduled: nil, status: "rolling_out", delivery: "2026-09-22T07:00:00Z")
        targeted.scope = "limited"
        let snapshot = state(pending: [], records: [previous, latest, targeted], at: "2026-09-22T07:04:30Z")
        XCTAssertFalse(snapshot.didResetToday)
        XCTAssertEqual(snapshot.emptyText(language: .chinese), "暂无最新重置预告（距离上次重置已过00:04:31）")
        XCTAssertEqual(state(records: [latest], at: "2026-09-22T07:04:31Z").secondsSinceLastDelivery, 272)
    }

    func testDateOnlyCardSurvivesBothCountdownsUntilTheFinalSecond() {
        let notice = post()
        let expected: [(String, String)] = [
            ("2026-09-22T06:59:59Z", "距预告日开始还剩 0小时0分1秒"),
            ("2026-09-22T07:00:00Z", "预告日内还剩 24小时0分0秒"),
            ("2026-09-23T06:59:59Z", "预告日内还剩 0小时0分1秒")
        ]
        for (instant, text) in expected {
            let result = state(pending: [notice], at: instant)
            XCTAssertEqual(result.announcements, [notice])
            XCTAssertFalse(result.didResetToday)
            XCTAssertEqual(ResetAnnouncementSummary.countdownText(for: notice, now: date(instant), language: .chinese), text)
        }
    }

    func testExpiredUnfulfilledNoticeOnlyDisappearsFromTopAndDoesNotBecomeCompleted() {
        let notice = post()
        let records = [record(notice)]
        let result = ResetTopPresentation.make(pending: [notice], records: records,
                                               now: date("2026-09-23T07:00:00Z"))
        XCTAssertTrue(result.announcements.isEmpty)
        XCTAssertFalse(result.didResetToday)
        XCTAssertEqual(result.emptyText(language: .chinese), "暂无最新重置预告")
        XCTAssertEqual(records.first?.announcement.status, "scheduled")
        XCTAssertEqual(ResetPendingAnnouncements.pending(from: records), [notice])
    }

    func testCompletionBannerExpiresAtLosAngelesMidnightWithoutAnotherSourceCheck() {
        let completed = post(status: "completed", delivery: "2026-09-22T20:00:00Z")
        let today = state(records: [completed], at: "2026-09-23T06:59:59Z")
        XCTAssertTrue(today.didResetToday)
        XCTAssertEqual(today.emptyText(language: .chinese), "暂无最新重置预告（今天已重置）")
        let tomorrow = state(records: [completed], at: "2026-09-23T07:00:00Z")
        XCTAssertFalse(tomorrow.didResetToday)
        XCTAssertEqual(tomorrow.emptyText(language: .chinese), "暂无最新重置预告（距离上次重置已过11:00:00）")
    }

    func testTodayUsesLosAngelesCalendarEvenWhenBeijingHasChangedDates() {
        let completed = post(status: "completed", delivery: "2026-09-22T15:59:59Z")
        XCTAssertTrue(state(records: [completed], at: "2026-09-22T16:00:01Z").didResetToday)
        XCTAssertTrue(state(records: [completed], at: "2026-09-23T06:59:59Z").didResetToday)
        XCTAssertFalse(state(records: [completed], at: "2026-09-23T07:00:00Z").didResetToday)
    }

    func testExactTimeWaitsUntilItsLosAngelesDayEnds() {
        let exact = post(scheduled: "2026-09-22T19:30:00Z", title: "周二 12:30 PDT 重置")
        XCTAssertEqual(state(pending: [exact], at: "2026-09-22T19:30:00Z").announcements, [exact])
        XCTAssertEqual(ResetScheduleTiming.phase(for: exact, now: date("2026-09-22T19:30:00Z")), .afterExact)
        XCTAssertEqual(state(pending: [exact], at: "2026-09-23T06:59:59Z").announcements, [exact])
        XCTAssertTrue(state(pending: [exact], at: "2026-09-23T07:00:00Z").announcements.isEmpty)
    }

    func testUnknownScheduleRemainsInUndatedGroupWithoutInventingExpiry() {
        let unknown = post(scheduled: nil, status: "watch")
        let result = state(pending: [unknown], at: "2026-10-01T07:00:00Z")
        XCTAssertTrue(result.announcements.isEmpty)
        XCTAssertEqual(result.undatedAnnouncements, [unknown])
        XCTAssertTrue(result.archivedUndated.isEmpty)
    }

    func testLaterGeneralDeliveryArchivesTwoOlderUndatedPreviewsOnlyInPresentation() {
        let first = official(post("1001", scheduled: nil, status: "watch", published: "2026-09-21T10:00:00Z"))
        let second = official(post("1002", scheduled: nil, status: "announced", published: "2026-09-22T10:00:00Z"))
        let delivered = official(post("2001", scheduled: nil, status: "rolling_out", kind: "banked",
                                      published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        let records = [first, second, delivered]
        let result = state(pending: [second, first], records: records, at: "2026-09-22T21:00:00Z")
        XCTAssertTrue(result.announcements.isEmpty)
        XCTAssertTrue(result.undatedAnnouncements.isEmpty)
        XCTAssertEqual(result.archivedUndated, [first.id: delivered, second.id: delivered])
        XCTAssertEqual(ResetPendingAnnouncements.pending(from: records.map(record)).map(\.id), [first.id, second.id])
        XCTAssertNil(delivered.relatedAnnouncementIDs)
        XCTAssertEqual(first.status, "watch")
        XCTAssertEqual(second.status, "announced")
    }

    func testUndatedAfterDeliveryStaysActiveAndGroupsSortOldestFirst() {
        let earlier = official(post("1001", scheduled: nil, published: "2026-09-22T21:00:00Z"))
        let later = official(post("1002", scheduled: nil, published: "2026-09-22T22:00:00Z"))
        let sameInstant = official(post("1003", scheduled: nil, published: "2026-09-22T20:00:00Z"))
        let delivered = official(post("2001", scheduled: nil, status: "completed",
                                      published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        let result = state(pending: [later, earlier, sameInstant], records: [delivered], at: "2026-09-22T23:00:00Z")
        XCTAssertEqual(result.undatedAnnouncements.map(\.id), [sameInstant.id, earlier.id, later.id])
        XCTAssertTrue(result.archivedUndated.isEmpty)
    }

    func testUntrustedFutureTargetedOrIncompleteDeliveryDoesNotArchiveUndated() {
        let preview = official(post("1001", scheduled: nil, published: "2026-09-22T10:00:00Z"))
        let delivered = official(post("2001", scheduled: nil, status: "rolling_out",
                                      published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        var invalid: [ResetAnnouncement] = []
        for source in [nil, "https://example.com/thsottiaux/status/2001", "https://x.com/another/status/2001",
                       "https://x.com/thsottiaux", "http://x.com/thsottiaux/status/2001"] as [String?] {
            var copy = delivered
            copy.sourceURL = source.flatMap(URL.init(string:))
            invalid.append(copy)
        }
        var future = delivered
        future.deliveryAt = date("2026-09-22T22:00:00Z")
        invalid.append(future)
        var unpublished = delivered
        unpublished.announcedAt = date("2026-09-22T22:00:00Z")
        invalid.append(unpublished)
        for scope in ["limited", "affected", "selected"] {
            var copy = delivered
            copy.scope = scope
            invalid.append(copy)
        }
        var compensation = delivered
        compensation.summary = "We have reset usage limits to compensate affected users."
        invalid.append(compensation)
        var pendingDelivery = delivered
        pendingDelivery.status = "scheduled"
        invalid.append(pendingDelivery)
        var unknownDate = delivered
        unknownDate.deliveryAt = nil
        unknownDate.announcedAt = nil
        invalid.append(unknownDate)
        for evidence in invalid {
            let result = state(pending: [preview], records: [evidence], at: "2026-09-22T21:00:00Z")
            XCTAssertEqual(result.undatedAnnouncements, [preview])
            XCTAssertTrue(result.archivedUndated.isEmpty)
        }
        var missingPublication = preview
        missingPublication.announcedAt = nil
        XCTAssertEqual(state(pending: [missingPublication], records: [delivered], at: "2026-09-22T21:00:00Z")
            .undatedAnnouncements, [missingPublication])
    }

    func testUndatedTypeAndExplicitScopeMustBeCompatible() {
        let preview = official(post("1001", scheduled: nil, published: "2026-09-22T10:00:00Z"))
        var banked = official(post("2001", scheduled: nil, status: "rolling_out", kind: "banked",
                                   published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        banked.deliveryKind = "banked"
        // The old regular provider category does not mean an explicitly promised direct reset.
        XCTAssertEqual(state(pending: [preview], records: [banked], at: "2026-09-22T21:00:00Z").archivedUndated[preview.id], banked)
        var directOnly = preview
        directOnly.summary = "A one-time reset is coming."
        XCTAssertEqual(state(pending: [directOnly], records: [banked], at: "2026-09-22T21:00:00Z").undatedAnnouncements, [directOnly])
        var bankedOnly = preview
        bankedOnly.kind = "banked"
        var direct = banked
        direct.kind = "regular"
        direct.deliveryKind = "regular"
        XCTAssertEqual(state(pending: [bankedOnly], records: [direct], at: "2026-09-22T21:00:00Z").undatedAnnouncements, [bankedOnly])
        var both = banked
        both.deliveryKind = "both"
        XCTAssertEqual(state(pending: [directOnly], records: [both], at: "2026-09-22T21:00:00Z").archivedUndated[preview.id], both)
        var codexOnly = preview
        codexOnly.scope = "codex"
        var differentScope = banked
        differentScope.scope = "chatgpt"
        XCTAssertEqual(state(pending: [codexOnly], records: [differentScope], at: "2026-09-22T21:00:00Z").undatedAnnouncements, [codexOnly])
    }

    func testDatedNoticeNeverUsesUndatedArchivalRuleAndCanReturnAfterDateAdded() throws {
        var preview = official(post("1001", scheduled: nil, status: "watch", published: "2026-09-22T10:00:00Z"))
        let delivered = official(post("2001", scheduled: nil, status: "rolling_out",
                                      published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        XCTAssertNotNil(state(pending: [preview], records: [delivered], at: "2026-09-22T21:00:00Z").archivedUndated[preview.id])
        preview.title = "周三重置预告"
        preview.summary = "A reset on Wednesday."
        preview.scheduledFor = date("2026-09-24T06:59:00Z")
        let result = state(pending: [preview], records: [delivered], at: "2026-09-22T21:00:00Z")
        XCTAssertEqual(result.announcements, [preview])
        XCTAssertTrue(result.undatedAnnouncements.isEmpty)
        XCTAssertTrue(result.archivedUndated.isEmpty)
    }

    func testDeliveryScopeCoversPreviewDirectionallyAndRejectsUnknownExplicitScopes() {
        let preview = official(post("1001", scheduled: nil, published: "2026-09-22T10:00:00Z"))
        let delivered = official(post("2001", scheduled: nil, status: "completed",
                                      published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        for (previewScope, deliveryScope, shouldArchive) in [
            ("broad", "chatgpt", false), ("all", "chatgpt", false),
            ("global", "codex", false), ("unspecified", "chatgpt", false),
            ("codex", "chatgpt", false), ("chatgpt", "codex", false),
            ("codex", "all", true), ("chatgpt", "broad", true),
            ("codex", "codex", true), ("chatgpt", "chatgpt", true),
            ("all", "unrecognized-segment", false), ("unrecognized-segment", "all", false),
            ("unrecognized-segment", "unrecognized-segment", false)
        ] {
            var scopedPreview = preview
            scopedPreview.scope = previewScope
            var scopedDelivery = delivered
            scopedDelivery.scope = deliveryScope
            let result = state(pending: [scopedPreview], records: [scopedDelivery], at: "2026-09-22T21:00:00Z")
            XCTAssertEqual(result.archivedUndated[preview.id] != nil, shouldArchive,
                           "Preview \(previewScope), delivery \(deliveryScope)")
            XCTAssertEqual(result.undatedAnnouncements.isEmpty, shouldArchive)
        }
    }

    func testUndatedProjectionSurvivesReloadWithoutChangingLedgerOrNotifyingOnEmptyPolls() throws {
        let preview = official(post("1001", scheduled: nil, status: "watch", published: "2026-09-22T10:00:00Z"))
        let delivered = official(post("2001", scheduled: nil, status: "rolling_out",
                                      published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        func snapshot(_ rows: [ResetAnnouncement]) -> NextResetSnapshot {
            NextResetSnapshot(announcements: rows, sourceCheckedAt: nil, sourceIsFresh: true)
        }
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([preview]), at: date("2026-09-22T10:01:00Z"), occurredWhileAway: false)
        _ = ledger.ingest(snapshot([delivered]), at: date("2026-09-22T20:01:00Z"), occurredWhileAway: false)
        let originalLedger = ledger
        let before = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: date("2026-09-22T21:00:00Z"))
        XCTAssertEqual(before.archivedUndated[preview.id], delivered)
        XCTAssertEqual(ledger, originalLedger)
        ledger = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertTrue(ledger.ingest(snapshot([]), at: date("2026-09-22T21:00:01Z"), occurredWhileAway: true).isEmpty)
        XCTAssertTrue(ledger.ingest(snapshot([preview, delivered]), at: date("2026-09-22T21:00:02Z"), occurredWhileAway: true).isEmpty)
        let after = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records, now: date("2026-09-22T21:00:00Z"))
        XCTAssertEqual(after, before)
        XCTAssertEqual(ledger.records, originalLedger.records)
        XCTAssertEqual(ledger.versions, originalLedger.versions)
        XCTAssertEqual(ledger.pendingAnnouncements, [preview])
        XCTAssertNil(ledger.records.first(where: { $0.id == delivered.id })?.announcement.relatedAnnouncementIDs)
    }

    private func official(_ post: ResetAnnouncement) -> ResetAnnouncement {
        var result = post
        result.sourceURL = URL(string: "https://x.com/thsottiaux/status/\(post.id)")
        return result
    }

    func testAccountReceiptAdvancesClockAndArchivesOlderUndatedWithoutGlobalCompletion() {
        let preview = official(post("1001", scheduled: nil, status: "watch", published: "2026-09-26T21:41:35Z"))
        let previousPublic = official(post("2001", scheduled: nil, status: "rolling_out",
                                           published: "2026-09-26T18:17:54Z", delivery: "2026-09-26T18:17:54Z"))
        let receipt = AccountResetReceipt(grantedAt: date("2026-09-29T18:46:26Z").addingTimeInterval(0.050805),
                                          title: "Full reset", description: "A complimentary reset credit.")
        let now = date("2026-09-30T00:50:00Z")
        let result = ResetTopPresentation.make(pending: [preview], records: [preview, previousPublic].map(record),
                                               now: now, accountReceipt: receipt)
        XCTAssertEqual(result.latestDeliveryOrigin, .accountReceipt)
        XCTAssertEqual(result.secondsSinceLastDelivery, Int(now.timeIntervalSince(receipt.grantedAt)))
        XCTAssertTrue(result.didResetToday)
        XCTAssertEqual(result.emptyText(language: .chinese), "暂无最新重置预告（今天已收到重置券）")
        XCTAssertTrue(result.undatedAnnouncements.isEmpty)
        XCTAssertTrue(result.archivedUndated.isEmpty)
        XCTAssertEqual(result.archivedForAccountReceipt, [preview.id: receipt])
        XCTAssertNil(preview.relatedAnnouncementIDs)
        XCTAssertEqual(preview.status, "watch")
        let tomorrow = ResetTopPresentation.make(pending: [preview], records: [previousPublic].map(record),
                                                 now: date("2026-09-30T07:00:00Z"), accountReceipt: receipt)
        XCTAssertFalse(tomorrow.didResetToday)
        XCTAssertEqual(tomorrow.emptyText(language: .chinese), "暂无最新重置预告（距离上次收到重置券已过12:13:33）")
    }

    func testAccountReceiptKeepsDatedNewerAndExplicitlyIncompatiblePreviews() {
        let receipt = AccountResetReceipt(grantedAt: date("2026-09-29T18:46:26Z"))
        let now = date("2026-09-30T00:50:00Z")
        let original = official(post("1001", scheduled: nil, status: "watch", published: "2026-09-26T21:41:35Z"))
        var incompatible: [ResetAnnouncement] = []
        var direct = original
        direct.summary = "A one-time reset is coming."
        incompatible.append(direct)
        var combined = original
        combined.summary = "A one-time reset and a banked reset are coming."
        incompatible.append(combined)
        var explicitDirect = original
        explicitDirect.summary = "A direct reset is coming."
        incompatible.append(explicitDirect)
        var directType = original
        directType.kind = "automatic_global"
        incompatible.append(directType)
        var targeted = original
        targeted.scope = "limited"
        incompatible.append(targeted)
        var compensation = original
        compensation.summary = "A reset to compensate affected users."
        incompatible.append(compensation)
        var newer = original
        newer.announcedAt = receipt.grantedAt.addingTimeInterval(1)
        incompatible.append(newer)
        var sameInstant = original
        sameInstant.announcedAt = receipt.grantedAt
        incompatible.append(sameInstant)
        var missingPublication = original
        missingPublication.announcedAt = nil
        incompatible.append(missingPublication)
        var otherProduct = original
        otherProduct.scope = "chatgpt"
        incompatible.append(otherProduct)
        var unknownScope = original
        unknownScope.scope = "unknown-segment"
        incompatible.append(unknownScope)
        var untrustedPreview = original
        untrustedPreview.sourceURL = URL(string: "https://example.com/thsottiaux/status/1001")
        incompatible.append(untrustedPreview)
        for preview in incompatible {
            let result = ResetTopPresentation.make(pending: [preview], records: [], now: now, accountReceipt: receipt)
            XCTAssertEqual(result.undatedAnnouncements, [preview])
            XCTAssertTrue(result.archivedForAccountReceipt.isEmpty)
        }
        var dated = original
        dated.title = "周三重置预告"
        dated.summary = "A reset on Wednesday."
        dated.scheduledFor = date("2026-10-01T06:59:00Z")
        let result = ResetTopPresentation.make(pending: [dated], records: [], now: now, accountReceipt: receipt)
        XCTAssertEqual(result.announcements, [dated])
        XCTAssertTrue(result.archivedForAccountReceipt.isEmpty)
    }

    func testCompensationReceiptCannotAdvanceGeneralClockOrArchiveGenericPreview() {
        let preview = official(post("1001", scheduled: nil, status: "watch", published: "2026-09-26T21:41:35Z"))
        let receipt = AccountResetReceipt(grantedAt: date("2026-09-29T18:46:26Z"),
                                          title: "Compensation credit", description: "Credit for affected users.")
        let result = ResetTopPresentation.make(pending: [preview], records: [], now: date("2026-09-30T00:50:00Z"), accountReceipt: receipt)
        XCTAssertFalse(ResetDeliveryEvidence.isGeneralAccountReceipt(receipt))
        XCTAssertNil(result.latestDeliveryOrigin)
        XCTAssertNil(result.secondsSinceLastDelivery)
        XCTAssertFalse(result.didResetToday)
        XCTAssertEqual(result.undatedAnnouncements, [preview])
        XCTAssertTrue(result.archivedForAccountReceipt.isEmpty)
    }

    func testLatestTimeChoosesNewerPublicOrPersonalEvidenceAndRejectsFutureReceipt() {
        let receipt = AccountResetReceipt(grantedAt: date("2026-09-29T18:46:26Z"))
        var publicDelivery = official(post("2001", scheduled: nil, status: "completed",
                                           published: "2026-09-29T20:00:00Z", delivery: "2026-09-29T20:00:00Z"))
        let now = date("2026-09-30T00:00:00Z")
        let laterPublic = ResetTopPresentation.make(pending: [], records: [record(publicDelivery)], now: now, accountReceipt: receipt)
        XCTAssertEqual(laterPublic.latestDeliveryOrigin, .publicAnnouncement)
        XCTAssertEqual(laterPublic.secondsSinceLastDelivery, 14_400)
        XCTAssertEqual(laterPublic.emptyText(language: .chinese), "暂无最新重置预告（今天已重置）")
        publicDelivery.deliveryAt = receipt.grantedAt
        let sameInstant = ResetTopPresentation.make(pending: [], records: [record(publicDelivery)], now: now, accountReceipt: receipt)
        XCTAssertEqual(sameInstant.latestDeliveryOrigin, .accountReceipt)
        let future = AccountResetReceipt(grantedAt: now.addingTimeInterval(1))
        let withoutTrustedReceipt = ResetTopPresentation.make(pending: [], records: [], now: now, accountReceipt: future)
        XCTAssertNil(withoutTrustedReceipt.latestDeliveryOrigin)
        XCTAssertNil(withoutTrustedReceipt.secondsSinceLastDelivery)
        XCTAssertFalse(withoutTrustedReceipt.didResetToday)
    }

    func testAccountReceiptKeepsExistingPublicArchivalReasonSeparate() {
        let preview = official(post("1001", scheduled: nil, published: "2026-09-22T10:00:00Z"))
        let delivered = official(post("2001", scheduled: nil, status: "completed",
                                      published: "2026-09-22T20:00:00Z", delivery: "2026-09-22T20:00:00Z"))
        let receipt = AccountResetReceipt(grantedAt: date("2026-09-29T18:46:26Z"))
        let result = ResetTopPresentation.make(pending: [preview], records: [record(delivered)],
                                               now: date("2026-09-30T00:50:00Z"), accountReceipt: receipt)
        XCTAssertEqual(result.archivedUndated[preview.id], delivered)
        XCTAssertTrue(result.archivedForAccountReceipt.isEmpty)
        XCTAssertEqual(result.latestDeliveryOrigin, .accountReceipt)
    }

    func testAccountReceiptProjectionReloadAndPollsLeaveAnnouncementLedgerUntouched() throws {
        let preview = official(post("1001", scheduled: nil, status: "watch", published: "2026-09-26T21:41:35Z"))
        let receipt = AccountResetReceipt(grantedAt: date("2026-09-29T18:46:26Z"), title: "Full reset", description: "A free credit.")
        func snapshot(_ rows: [ResetAnnouncement]) -> NextResetSnapshot {
            NextResetSnapshot(announcements: rows, sourceCheckedAt: nil, sourceIsFresh: true)
        }
        var ledger = ResetLedger()
        _ = ledger.ingest(snapshot([preview]), at: date("2026-09-27T00:00:00Z"), occurredWhileAway: false)
        let previous = ledger
        let expected = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records,
                                                 now: date("2026-09-30T00:50:00Z"), accountReceipt: receipt)
        XCTAssertEqual(ledger, previous)
        ledger = try JSONDecoder().decode(ResetLedger.self, from: JSONEncoder().encode(ledger))
        let restoredReceipt = try JSONDecoder().decode(AccountResetReceipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertTrue(ledger.ingest(snapshot([]), at: date("2026-09-30T00:49:00Z"), occurredWhileAway: true).isEmpty)
        XCTAssertTrue(ledger.ingest(snapshot([preview]), at: date("2026-09-30T00:50:00Z"), occurredWhileAway: true).isEmpty)
        let restored = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records,
                                                 now: date("2026-09-30T00:50:00Z"), accountReceipt: restoredReceipt)
        XCTAssertEqual(restored, expected)
        XCTAssertEqual(ledger.records, previous.records)
        XCTAssertEqual(ledger.versions, previous.versions)
        XCTAssertEqual(ledger.pendingAnnouncements, [preview])
        var dated = preview
        dated.title = "周三重置预告"
        dated.summary = "A reset on Wednesday."
        dated.scheduledFor = date("2026-10-01T06:59:00Z")
        _ = ledger.ingest(snapshot([dated]), at: date("2026-09-30T00:51:00Z"), occurredWhileAway: false)
        let updated = ResetTopPresentation.make(pending: ledger.pendingAnnouncements, records: ledger.records,
                                                now: date("2026-09-30T00:51:00Z"), accountReceipt: restoredReceipt)
        XCTAssertEqual(updated.announcements, [dated])
        XCTAssertTrue(updated.archivedForAccountReceipt.isEmpty)
    }

    func testCompletingOneNoticeDoesNotHideAnother() {
        let completed = post(status: "completed", delivery: "2026-09-22T20:00:00Z")
        let other = post("wednesday", scheduled: "2026-09-24T06:59:00Z", title: "周三重置预告")
        let result = state(pending: [other], records: [completed, other], at: "2026-09-22T21:00:00Z")
        XCTAssertEqual(result.announcements, [other])
        XCTAssertTrue(result.didResetToday)
        let expiredSibling = state(pending: [post(), other], at: "2026-09-23T07:00:00Z")
        XCTAssertEqual(expiredSibling.announcements, [other])
    }

    func testEachSupportedDeliveryStateCountsForRegularAndBanked() {
        for kind in ["regular", "banked"] {
            for status in ["completed", "confirmed", "propagated", "rolling_out", " COMPLETED "] {
                let delivered = post(status: status, kind: kind, delivery: "2026-09-22T20:00:00Z")
                let result = state(pending: [delivered], records: [delivered], at: "2026-09-22T21:00:00Z")
                XCTAssertTrue(result.didResetToday, "\(kind) \(status)")
                XCTAssertTrue(result.announcements.isEmpty)
            }
        }
        for status in ["scheduled", "pending", "cancelled", "canceled"] {
            let notDelivered = post(status: status, delivery: "2026-09-22T20:00:00Z")
            XCTAssertFalse(state(records: [notDelivered], at: "2026-09-22T21:00:00Z").didResetToday)
        }
    }

    func testFutureDeliveryEvidenceDoesNotCountEarly() {
        let future = post(status: "completed", delivery: "2026-09-22T22:00:00Z")
        XCTAssertFalse(state(records: [future], at: "2026-09-22T21:00:00Z").didResetToday)
        XCTAssertTrue(state(records: [future], at: "2026-09-22T22:00:00Z").didResetToday)
    }

    func testOldCacheDoesNotTreatAFirstCheckOrOriginalAnnouncementTimeAsDelivery() throws {
        let datedOriginal = post(status: "completed", published: "2026-09-22T09:00:00Z")
        let oldCompletion = post("old-completion", scheduled: nil, status: "completed",
                                 published: "2026-09-21T20:00:00Z")
        let rows = [record(datedOriginal), record(oldCompletion)]
        let encoded = try JSONEncoder().encode(rows)
        let restored = try JSONDecoder().decode([ResetRecord].self, from: encoded)
        XCTAssertFalse(ResetTopPresentation.make(pending: [], records: restored,
            now: date("2026-09-22T21:00:00Z")).didResetToday)
        let freshCompletionPost = post("completion-post", scheduled: nil, status: "completed",
                                       published: "2026-09-22T20:00:00Z")
        XCTAssertTrue(state(records: [freshCompletionPost], at: "2026-09-22T21:00:00Z").didResetToday)
    }

    func testDayBoundariesRespectSpringAndFallDaylightSavingChanges() {
        let fixtures: [(String, String, String, String)] = [
            ("2026-03-09T06:59:00Z", "2026-03-08T08:30:00Z", "2026-03-09T06:59:59Z", "2026-03-09T07:00:00Z"),
            ("2026-11-02T07:59:00Z", "2026-11-01T07:30:00Z", "2026-11-02T07:59:59Z", "2026-11-02T08:00:00Z")
        ]
        for (scheduled, deliveredAt, lastSecond, nextMidnight) in fixtures {
            let pending = post(scheduled: scheduled, title: "周日重置预告")
            let completed = post(scheduled: scheduled, status: "completed", delivery: deliveredAt,
                                 title: "周日重置预告")
            XCTAssertEqual(state(pending: [pending], at: lastSecond).announcements, [pending])
            XCTAssertTrue(state(pending: [pending], at: nextMidnight).announcements.isEmpty)
            XCTAssertTrue(state(records: [completed], at: lastSecond).didResetToday)
            XCTAssertFalse(state(records: [completed], at: nextMidnight).didResetToday)
        }
    }
}
