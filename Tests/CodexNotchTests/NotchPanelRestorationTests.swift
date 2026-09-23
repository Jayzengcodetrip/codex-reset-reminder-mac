import XCTest
@testable import CodexNotch

final class NotchPanelRestorationTests: XCTestCase {
    func testLateTransitionAndCancellationScenarios() throws {
        // Exercises the old single-pass failure and the bounded replacement,
        // including cancelled callbacks that were already queued for delivery.
        XCTAssertGreaterThanOrEqual(try NotchPanelRestoration.runSelfChecks(), 15)
    }

    func testRapidSwitchOnlyUsesTheLatestGeometry() {
        var callbacks: [() -> Void] = []
        let restoration = NotchPanelRestoration { _, operation in
            callbacks.append(operation)
            return {}
        }
        var geometry = "previous"
        var rendered: [String] = []
        restoration.request { rendered.append(geometry) }
        geometry = "current"
        restoration.request { rendered.append(geometry) }
        callbacks.forEach { $0() }
        XCTAssertEqual(rendered, ["current", "current", "current"])
    }
}
