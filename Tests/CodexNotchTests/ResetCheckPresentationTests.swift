import Foundation
import XCTest
@testable import CodexNotch

final class ResetCheckPresentationTests: XCTestCase {
    private let checkedAt = ISO8601DateFormatter().date(from: "2026-09-22T09:22:00Z")!

    func testSuccessfulCheckWithExistingPendingResetUsesUnifiedNoNewText() {
        XCTAssertEqual(ResetCheckPresentation.resultText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: checkedAt, hasPending: true, unreadCount: 0, language: .chinese),
            "已检查接口，暂无新重置预告")
    }

    func testUnreadDataDoesNotBecomeANewDiscovery() {
        for pending in [false, true] {
            for unread in [0, 1, 3] {
                XCTAssertEqual(ResetCheckPresentation.resultText(isChecking: false, errorMessage: nil,
                    lastSuccessfulCheck: checkedAt, hasPending: pending, unreadCount: unread, language: .chinese),
                    "已检查接口，暂无新重置预告")
            }
        }
    }

    func testOnlyActualNewPreannouncementUsesDiscoveryText() {
        XCTAssertEqual(ResetCheckPresentation.resultText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: checkedAt, hasPending: true, unreadCount: 0, language: .chinese,
            hasNewPreannouncement: true), "已检查接口，发现新重置预告")
        XCTAssertEqual(ResetCheckPresentation.compactText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: checkedAt, hasPending: true, unreadCount: 0, language: .chinese,
            hasNewPreannouncement: true), "17:22（北京）已检查接口，发现新重置预告")
    }

    func testFailedUnknownAndRunningChecksCannotClaimDiscoveryOrAbsence() {
        let cases: [(checking: Bool, error: String?, success: Date?, expected: String)] = [
            (false, "Timeout", checkedAt, "检查遇到问题"),
            (false, "Timeout", nil, "检查遇到问题"),
            (false, nil, nil, "等待首次检查"),
            (true, "Previous failure", checkedAt, "正在检查接口…")
        ]
        for state in cases {
            for hasNew in [false, true] {
                XCTAssertEqual(ResetCheckPresentation.resultText(isChecking: state.checking,
                    errorMessage: state.error, lastSuccessfulCheck: state.success,
                    hasPending: true, unreadCount: 1, language: .chinese, hasNewPreannouncement: hasNew),
                    state.expected)
                XCTAssertEqual(ResetCheckPresentation.compactText(isChecking: state.checking,
                    errorMessage: state.error, lastSuccessfulCheck: state.success,
                    hasPending: true, unreadCount: 1, language: .chinese, hasNewPreannouncement: hasNew),
                    state.expected)
            }
        }
    }

    func testCompactTimestampIsTheActualSuccessfulCheckInBeijingTime() {
        XCTAssertEqual(ResetCheckPresentation.compactText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: checkedAt, hasPending: true, unreadCount: 3, language: .chinese),
            "17:22（北京）已检查接口，暂无新重置预告")
        XCTAssertEqual(ResetCheckPresentation.compactText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: checkedAt, hasPending: true, unreadCount: 3, language: .english),
            "17:22 Beijing · Feed checked; no new reset announcements")
    }

    func testEnglishResultDependsOnNewDiscoveryOnly() {
        XCTAssertEqual(ResetCheckPresentation.resultText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: checkedAt, hasPending: true, unreadCount: 2, language: .english),
            "Feed checked; no new reset announcements")
        XCTAssertEqual(ResetCheckPresentation.resultText(isChecking: false, errorMessage: nil,
            lastSuccessfulCheck: checkedAt, hasPending: true, unreadCount: 0, language: .english,
            hasNewPreannouncement: true), "Feed checked; new reset announcement found")
    }

    func testExecutableRegressionChecks() throws {
        XCTAssertEqual(try ResetCheckPresentation.runSelfChecks(), 34)
    }
}
