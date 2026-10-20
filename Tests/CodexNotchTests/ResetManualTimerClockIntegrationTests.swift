import Foundation
import XCTest
@testable import CodexNotch

@MainActor
final class ResetManualTimerClockIntegrationTests: XCTestCase {
    func testFractionalClickImmediatelyReplacesOldClockAcrossUpdateAndRenderPaths() {
        let second = Date(timeIntervalSince1970: 1_800_000_000)
        let clickedAt = second.addingTimeInterval(0.75)
        let model = NotchViewModel(state: .hidden, now: second)
        let oldDelivery = ResetAnnouncement(id: "old-delivery", title: "Synthetic delivery",
            summary: "Synthetic fixture", sourceURL: URL(string: "https://x.com/thsottiaux/status/95001"),
            announcedAt: second.addingTimeInterval(-3600), scheduledFor: nil,
            kind: "regular", scope: "broad", status: "completed",
            deliveryAt: second.addingTimeInterval(-3600), deliveryKind: "regular")
        model.resetRecords = [ResetRecord(id: oldDelivery.id, announcement: oldDelivery,
                                          isUnread: false, occurredWhileAway: false)]
        XCTAssertEqual(model.resetTopPresentation.secondsSinceLastDelivery, 3600)

        model.manualTimerRestartedAt = clickedAt
        model.updateClock(now: second.addingTimeInterval(0.8))
        XCTAssertEqual(model.manualTimerRestartedAt, clickedAt)
        XCTAssertEqual(model.resetTopPresentation.latestDeliveryOrigin, .manualTimerRestart)
        XCTAssertEqual(model.resetTopPresentation.secondsSinceLastDelivery, 0,
                       "Flooring the current time must not make this saved click appear to be in the future")

        // A subsequent surface/layout update in that same second must not
        // briefly restore the old official clock either.
        model.update(state: .hidden, now: second.addingTimeInterval(0.9))
        XCTAssertEqual(model.resetTopPresentation.latestDeliveryOrigin, .manualTimerRestart)
        XCTAssertEqual(model.resetTopPresentation.secondsSinceLastDelivery, 0)
        model.updateClock(now: second.addingTimeInterval(2))
        XCTAssertEqual(model.resetTopPresentation.latestDeliveryOrigin, .manualTimerRestart)
        XCTAssertEqual(model.resetTopPresentation.secondsSinceLastDelivery, 1)
        XCTAssertEqual(model.manualTimerRestartedAt, clickedAt)
    }

    func testARealFutureFractionalAnchorRemainsIgnoredInBothClockUpdatePaths() {
        let second = Date(timeIntervalSince1970: 1_800_000_000)
        let model = NotchViewModel(state: .hidden, now: second)
        model.manualTimerRestartedAt = second.addingTimeInterval(0.9)
        model.updateClock(now: second.addingTimeInterval(0.75))
        XCTAssertNil(model.resetTopPresentation.latestDeliveryOrigin)
        XCTAssertNil(model.resetTopPresentation.secondsSinceLastDelivery)
        model.update(state: .hidden, now: second.addingTimeInterval(0.8))
        XCTAssertNil(model.resetTopPresentation.latestDeliveryOrigin)
        XCTAssertNil(model.resetTopPresentation.secondsSinceLastDelivery)
    }
}
