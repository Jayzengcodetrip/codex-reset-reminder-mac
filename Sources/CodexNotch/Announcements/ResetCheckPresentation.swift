import Foundation

/// Describes this app's latest interface check. Saved announcements remain on their own cards.
enum ResetCheckPresentation {
    static func resultText(isChecking: Bool, errorMessage: String?, lastSuccessfulCheck: Date?,
                           hasPending: Bool, unreadCount: Int, language: AppLanguage,
                           hasNewPreannouncement: Bool = false) -> String {
        if let interruption = interruptionText(isChecking: isChecking, errorMessage: errorMessage,
                                               lastSuccessfulCheck: lastSuccessfulCheck, language: language) {
            return interruption
        }
        // Existing pending or unread records do not mean this particular check discovered a new reset.
        return successText(hasNewPreannouncement: hasNewPreannouncement, language: language)
    }

    static func compactText(isChecking: Bool, errorMessage: String?, lastSuccessfulCheck: Date?,
                            hasPending: Bool, unreadCount: Int, language: AppLanguage,
                            hasNewPreannouncement: Bool = false) -> String {
        if let interruption = interruptionText(isChecking: isChecking, errorMessage: errorMessage,
                                               lastSuccessfulCheck: lastSuccessfulCheck, language: language) {
            return interruption
        }
        guard let lastSuccessfulCheck else {
            return language.localized(chinese: "等待首次检查", english: "Waiting for first check")
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: lastSuccessfulCheck)
        let result = successText(hasNewPreannouncement: hasNewPreannouncement, language: language)
        return language.localized(chinese: "\(time)（北京）\(result)", english: "\(time) Beijing · \(result)")
    }

    private static func interruptionText(isChecking: Bool, errorMessage: String?,
                                         lastSuccessfulCheck: Date?, language: AppLanguage) -> String? {
        if isChecking {
            return language.localized(chinese: "正在检查接口…", english: "Checking feed…")
        }
        if let errorMessage, !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return language.localized(chinese: "检查遇到问题", english: "Check failed")
        }
        guard lastSuccessfulCheck != nil else {
            return language.localized(chinese: "等待首次检查", english: "Waiting for first check")
        }
        return nil
    }

    private static func successText(hasNewPreannouncement: Bool, language: AppLanguage) -> String {
        if hasNewPreannouncement {
            return language.localized(chinese: "已检查接口，发现新重置预告",
                                      english: "Feed checked; new reset announcement found")
        }
        return language.localized(chinese: "已检查接口，暂无新重置预告",
                                  english: "Feed checked; no new reset announcements")
    }

    /// Pure presentation regression checks; no network, saved-state writes or notifications.
    static func runSelfChecks() throws -> Int {
        let checkedAt = ISO8601DateFormatter().date(from: "2026-09-22T09:22:00Z")!
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw PresentationCheckError(message: message) }
            count += 1
        }
        func result(checking: Bool = false, error: String? = nil, date: Date? = checkedAt,
                    pending: Bool = false, unread: Int = 0, language: AppLanguage = .chinese,
                    hasNew: Bool = false) -> String {
            resultText(isChecking: checking, errorMessage: error, lastSuccessfulCheck: date,
                       hasPending: pending, unreadCount: unread, language: language,
                       hasNewPreannouncement: hasNew)
        }
        func compact(checking: Bool = false, error: String? = nil, date: Date? = checkedAt,
                     pending: Bool = false, unread: Int = 0, language: AppLanguage = .chinese,
                     hasNew: Bool = false) -> String {
            compactText(isChecking: checking, errorMessage: error, lastSuccessfulCheck: date,
                        hasPending: pending, unreadCount: unread, language: language,
                        hasNewPreannouncement: hasNew)
        }
        for pending in [false, true] {
            for unread in [-1, 0, 1, 3] {
                try check(result(pending: pending, unread: unread) == "已检查接口，暂无新重置预告",
                          "Pending and unread records must not be mistaken for newly discovered announcements")
                try check(result(pending: pending, unread: unread, hasNew: true) == "已检查接口，发现新重置预告",
                          "An actual new preannouncement must use the discovery result independently of acknowledgement")
            }
        }
        try check(compact(pending: true, unread: 3) == "17:22（北京）已检查接口，暂无新重置预告",
                  "Compact result retains the actual successful check time and unified no-new text")
        try check(compact(pending: true, hasNew: true) == "17:22（北京）已检查接口，发现新重置预告",
                  "Compact result reports a genuine discovery with its successful check time")
        try check(result(error: " \n ") == result(), "An empty error must not manufacture a failure")
        try check(result(date: nil, pending: true, hasNew: true) == "等待首次检查",
                  "Saved or candidate data cannot invent a first successful check")
        try check(compact(date: nil, hasNew: true) == "等待首次检查",
                  "Compact unknown state must not invent a successful timestamp")
        try check(result(error: "Timeout", pending: true, hasNew: true) == "检查遇到问题",
                  "Failure must override candidate or old new-announcement state")
        try check(result(error: "Timeout", date: nil) == "检查遇到问题",
                  "A first-check failure must be reported as failure")
        try check(compact(error: "Timeout", hasNew: true) == "检查遇到问题",
                  "Compact failure must not reuse an old successful check time")
        try check(result(checking: true, error: "Old error", hasNew: true) == "正在检查接口…",
                  "A running check must not prematurely report discovery or absence")
        try check(compact(checking: true, hasNew: true) == "正在检查接口…",
                  "Compact progress must not claim completion")
        try check(result(pending: true, unread: 2, language: .english) == "Feed checked; no new reset announcements",
                  "English existing pending and unread data must not be treated as new")
        try check(result(language: .english, hasNew: true) == "Feed checked; new reset announcement found",
                  "English discovery must reflect the actual check result")
        try check(compact(language: .english) == "17:22 Beijing · Feed checked; no new reset announcements",
                  "English compact result must identify Beijing time")
        try check(compact(language: .english, hasNew: true) == "17:22 Beijing · Feed checked; new reset announcement found",
                  "English compact discovery must retain the check time")
        try check(result(error: "Timeout", language: .english, hasNew: true) == "Check failed",
                  "English failure must override discovery")
        try check(result(date: nil, language: .english, hasNew: true) == "Waiting for first check",
                  "English unknown state must override discovery")
        try check(result(checking: true, language: .english, hasNew: true) == "Checking feed…",
                  "English progress must override discovery")
        let nextDay = ISO8601DateFormatter().date(from: "2026-09-22T18:05:00Z")!
        try check(compact(date: nextDay).hasPrefix("02:05（北京）"),
                  "Beijing conversion must wrap UTC dates correctly")
        return count
    }

    private struct PresentationCheckError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
