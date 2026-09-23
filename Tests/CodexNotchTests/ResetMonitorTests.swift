import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetMonitorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAwakeNewAnnouncementNotifiesOnceAndAcknowledgementSurvivesRestart() async throws {
        let store = MemoryResetStore()
        var posts = [announcement("old")]
        let monitor = makeMonitor(store: store) { posts }
        var notifications: [[ResetRecord]] = []
        monitor.onNotify = { notifications.append($0) }
        await refresh(monitor)
        XCTAssertTrue(notifications.isEmpty)
        posts.append(announcement("new"))
        await refresh(monitor)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(monitor.unreadCount, 1)
        XCTAssertEqual(monitor.awayUnreadCount, 0)
        await refresh(monitor)
        XCTAssertEqual(notifications.count, 1)
        monitor.markRead(id: "new")
        let restarted = makeMonitor(store: store) { posts }
        await refresh(restarted)
        XCTAssertEqual(restarted.unreadCount, 0)
    }

    func testFailedSaveNeverAdvancesInMemoryOrNotifiesAndRetryFindsUpdate() async throws {
        let store = MemoryResetStore()
        var posts = [announcement("old")]
        var clock = now
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            NextResetSnapshot(announcements: posts, sourceCheckedAt: self.now, sourceIsFresh: true)
        }, now: { clock }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        var notifications = 0
        monitor.onNotify = { _ in notifications += 1 }
        await refresh(monitor)
        let priorCheck = monitor.lastSuccessfulCheck
        store.failSave = true
        clock.addTimeInterval(120)
        posts.append(announcement("new"))
        await refresh(monitor)
        XCTAssertEqual(monitor.records.map(\.id), ["old"])
        XCTAssertEqual(monitor.lastSuccessfulCheck, priorCheck)
        XCTAssertNotNil(monitor.errorMessage)
        XCTAssertEqual(notifications, 0)
        store.failSave = false
        await refresh(monitor)
        XCTAssertEqual(monitor.unreadCount, 1)
        XCTAssertEqual(monitor.awayUnreadCount, 1)
    }

    func testRestartSilentlyCatchesUpAllPostsIncludingLateInsertedOldTimestamp() async {
        let store = MemoryResetStore()
        let monitor = makeMonitor(store: store) { [self.announcement("baseline")] }
        await refresh(monitor)
        var delayed = announcement("late-indexed")
        delayed.announcedAt = now.addingTimeInterval(-86400)
        let restarted = makeMonitor(store: store) { [self.announcement("baseline"), delayed, self.announcement("new")] }
        var notifications = 0
        restarted.onNotify = { _ in notifications += 1 }
        await refresh(restarted)
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(restarted.awayUnreadCount, 2)
        XCTAssertEqual(restarted.unreadCount, 2)
    }

    func testFetchFailureKeepsLastSuccessfulCheckAndExistingUnread() async {
        let store = MemoryResetStore()
        var fail = false
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            if fail { throw URLError(.notConnectedToInternet) }
            return NextResetSnapshot(announcements: [self.announcement("old")], sourceCheckedAt: self.now, sourceIsFresh: true)
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        await refresh(monitor)
        fail = true
        await refresh(monitor)
        XCTAssertEqual(monitor.lastSuccessfulCheck, now)
        XCTAssertEqual(monitor.records.count, 1)
        XCTAssertFalse(monitor.sourceIsFresh)
        XCTAssertNotNil(monitor.errorMessage)
    }

    func testFailedAcknowledgementDoesNotLoseUnread() async {
        let store = MemoryResetStore()
        var posts = [announcement("old")]
        let monitor = makeMonitor(store: store) { posts }
        await refresh(monitor)
        posts.append(announcement("new"))
        await refresh(monitor)
        store.failSave = true
        monitor.markRead(id: "new")
        XCTAssertEqual(monitor.unreadCount, 1)
        XCTAssertNotNil(monitor.errorMessage)
    }

    func testDelayedProviderDiagnosticsDoNotBecomeInterfaceFailureOrSuppressNewNotice() async {
        let store = MemoryResetStore()
        var posts = [announcement("old")]
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            NextResetSnapshot(announcements: posts, sourceCheckedAt: self.now.addingTimeInterval(-86400), sourceIsFresh: false)
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
        var notifications = 0
        monitor.onNotify = { notifications += $0.count }
        await refresh(monitor)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertEqual(monitor.lastSuccessfulCheck, now)
        XCTAssertFalse(monitor.sourceIsFresh)
        XCTAssertEqual(store.ledger?.sourceIsFresh, false)
        posts.append(announcement("new"))
        await refresh(monitor)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(monitor.unreadCount, 1)
    }

    func testRefreshBurstWaitsForMinimumSourceInterval() async {
        let store = MemoryResetStore()
        var fetchCount = 0
        var clock = now
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            fetchCount += 1
            return NextResetSnapshot(announcements: [], sourceCheckedAt: self.now, sourceIsFresh: true)
        }, now: { clock }, idleSeconds: { 0 }, minimumRefreshInterval: 60)
        defer { monitor.stop() }
        await refresh(monitor)
        await refresh(monitor)
        await refresh(monitor)
        XCTAssertEqual(fetchCount, 1)
        clock.addTimeInterval(60)
        await refresh(monitor)
        XCTAssertEqual(fetchCount, 2)
    }

    func testIdleMacSuppressesPopupAndKeepsAwayBadge() async {
        let store = MemoryResetStore()
        var posts = [announcement("old")]
        let monitor = ResetMonitor(store: store, fetchSnapshot: {
            NextResetSnapshot(announcements: posts, sourceCheckedAt: self.now, sourceIsFresh: true)
        }, now: { self.now }, idleSeconds: { 600 }, minimumRefreshInterval: 0)
        var notifications = 0
        monitor.onNotify = { _ in notifications += 1 }
        await refresh(monitor)
        posts.append(announcement("new"))
        await refresh(monitor)
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(monitor.awayUnreadCount, 1)
    }

    private func makeMonitor(store: MemoryResetStore, posts: @escaping () -> [ResetAnnouncement]) -> ResetMonitor {
        ResetMonitor(store: store, fetchSnapshot: {
            NextResetSnapshot(announcements: posts(), sourceCheckedAt: self.now, sourceIsFresh: true)
        }, now: { self.now }, idleSeconds: { 0 }, minimumRefreshInterval: 0)
    }
    private func refresh(_ monitor: ResetMonitor) async {
        monitor.refresh()
        for _ in 0..<100 {
            if !monitor.isChecking { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Local fixture refresh did not finish")
    }
    private func announcement(_ id: String) -> ResetAnnouncement {
        ResetAnnouncement(id: id, title: "额度更新", summary: "原帖适用条件", sourceURL: nil,
                          announcedAt: now, scheduledFor: nil, kind: "regular", scope: "unspecified", status: nil)
    }
}

private final class MemoryResetStore: ResetLedgerStoring {
    var ledger: ResetLedger?
    var failSave = false
    func load() throws -> ResetLedger? { ledger }
    func save(_ value: ResetLedger) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        ledger = value
    }
}
