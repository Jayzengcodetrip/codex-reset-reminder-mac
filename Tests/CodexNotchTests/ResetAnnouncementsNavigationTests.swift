import XCTest
@testable import CodexNotch

@MainActor
final class ResetAnnouncementsNavigationTests: XCTestCase {
    func testOpeningUndatedSummaryDoesNotAcknowledgeAnyRecord() async {
        let navigation = ResetAnnouncementsNavigation()
        var acknowledged: [String] = []
        navigation.selectRecord(id: "previous-selection") { acknowledged.append($0) }
        navigation.filter = .away

        navigation.showUndatedAnnouncements()

        XCTAssertEqual(navigation.filter, .undated)
        XCTAssertNil(navigation.selectedID)
        XCTAssertEqual(acknowledged, ["previous-selection"])
    }

    func testRepeatedSummaryNavigationUpdatesExistingWindowStateWithoutAcknowledgement() async {
        let navigation = ResetAnnouncementsNavigation()
        var acknowledged: [String] = []
        navigation.showUndatedAnnouncements()
        navigation.selectRecord(id: "undated") { acknowledged.append($0) }
        navigation.filter = .unread

        navigation.showUndatedAnnouncements()

        XCTAssertEqual(navigation.filter, .undated)
        XCTAssertNil(navigation.selectedID)
        XCTAssertEqual(acknowledged, ["undated"])
    }

    func testSelectingARecordAcknowledgesOnlyThatRecordAndKeepsFilter() async {
        let navigation = ResetAnnouncementsNavigation()
        navigation.filter = .away
        var acknowledged: [String] = []

        navigation.selectRecord(id: "chosen") { acknowledged.append($0) }

        XCTAssertEqual(navigation.filter, .away)
        XCTAssertEqual(navigation.selectedID, "chosen")
        XCTAssertEqual(acknowledged, ["chosen"])
    }

    func testFollowingLaterDeliveryOpensAllFilterAndAcknowledgesOnlyDelivery() async {
        let navigation = ResetAnnouncementsNavigation()
        navigation.showUndatedAnnouncements()
        var acknowledged: [String] = []

        navigation.showDelivery(id: "later-delivery") { acknowledged.append($0) }

        XCTAssertEqual(navigation.filter, .all)
        XCTAssertEqual(navigation.selectedID, "later-delivery")
        XCTAssertEqual(acknowledged, ["later-delivery"])
    }

    func testUndatedFilterFollowsActiveSummaryWhileOtherFiltersRetainArchivedUnread() async {
        func record(_ id: String, unread: Bool, away: Bool = false) -> ResetRecord {
            let announcement = ResetAnnouncement(id: id, title: id, summary: "", sourceURL: nil,
                announcedAt: nil, scheduledFor: nil, kind: "regular", scope: "broad", status: "scheduled")
            return ResetRecord(id: id, announcement: announcement, isUnread: unread, occurredWhileAway: away)
        }
        let newer = record("newer-active", unread: true)
        let older = record("older-active", unread: false)
        let archived = record("archived-unresolved", unread: true, away: true)
        let records = [newer, older, archived]
        let active = [older.announcement, newer.announcement]
        let navigation = ResetAnnouncementsNavigation()

        navigation.showUndatedAnnouncements()
        XCTAssertEqual(navigation.visibleRecords(from: records, undated: active).map(\.id),
                       ["older-active", "newer-active"])
        navigation.filter = .all
        XCTAssertEqual(navigation.visibleRecords(from: records, undated: active).map(\.id), records.map(\.id))
        navigation.filter = .unread
        XCTAssertEqual(navigation.visibleRecords(from: records, undated: active).map(\.id),
                       ["newer-active", "archived-unresolved"])
        navigation.filter = .away
        XCTAssertEqual(navigation.visibleRecords(from: records, undated: active).map(\.id), ["archived-unresolved"])
        XCTAssertTrue(archived.isUnread)
        XCTAssertEqual(archived.announcement.status, "scheduled")
    }
}
