import XCTest
@testable import CodexNotch

@MainActor
final class ResetAnnouncementsNavigationTests: XCTestCase {
    func testOpeningUndatedSummarySwitchesToPendingFilterAndClearsSelection() async {
        let navigation = ResetAnnouncementsNavigation()
        navigation.selectRecord(id: "previous-selection")

        navigation.showUndatedAnnouncements()

        XCTAssertEqual(navigation.filter, .undated)
        XCTAssertNil(navigation.selectedID)
    }

    func testSelectingARecordPreservesFilter() async {
        let navigation = ResetAnnouncementsNavigation()
        navigation.filter = .undated

        navigation.selectRecord(id: "chosen")

        XCTAssertEqual(navigation.filter, .undated)
        XCTAssertEqual(navigation.selectedID, "chosen")
    }

    func testFollowingLaterDeliveryOpensAllFilterAndSelectsDelivery() async {
        let navigation = ResetAnnouncementsNavigation()
        navigation.showUndatedAnnouncements()

        navigation.showDelivery(id: "later-delivery")

        XCTAssertEqual(navigation.filter, .all)
        XCTAssertEqual(navigation.selectedID, "later-delivery")
    }

    func testPendingFilterFollowsActivePreviewsWhileAllFilterRetainsHistory() async {
        func record(_ id: String) -> ResetRecord {
            let announcement = ResetAnnouncement(id: id, title: id, summary: "", sourceURL: nil,
                announcedAt: nil, scheduledFor: nil, kind: "regular", scope: "broad", status: "scheduled")
            return ResetRecord(id: id, announcement: announcement, isUnread: false, occurredWhileAway: false)
        }
        let newer = record("newer-active")
        let older = record("older-active")
        let archived = record("archived-unresolved")
        let records = [newer, older, archived]
        let active = [older.announcement, newer.announcement]
        let navigation = ResetAnnouncementsNavigation()

        navigation.showUndatedAnnouncements()
        XCTAssertEqual(navigation.visibleRecords(from: records, activePending: active).map(\.id),
                       ["older-active", "newer-active"])
        navigation.filter = .all
        XCTAssertEqual(navigation.visibleRecords(from: records, activePending: active).map(\.id), records.map(\.id))
        XCTAssertEqual(ResetAnnouncementFilter.allCases, [.all, .undated])
    }
}
