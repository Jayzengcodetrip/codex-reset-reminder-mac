import Foundation

/// The actionable reset stays on the main card even after its announcement is read.
/// Source health belongs beside this summary, not in place of a known deadline.
struct ResetAnnouncementSummary: Equatable {
    static func select(from records: [ResetRecord], now: Date) -> ResetAnnouncement? {
        let pending = ResetPendingAnnouncements.pending(from: records)
        return pending.sorted { left, right in
            let leftDeadline = ResetScheduleTiming.target(for: left)?.countdownDeadline
            let rightDeadline = ResetScheduleTiming.target(for: right)?.countdownDeadline
            let leftFuture = leftDeadline.map { $0 > now } == true
            let rightFuture = rightDeadline.map { $0 > now } == true
            if leftFuture != rightFuture { return leftFuture }
            if leftFuture, let leftTime = leftDeadline, let rightTime = rightDeadline,
               leftTime != rightTime { return leftTime < rightTime }
            let leftPublished = left.announcedAt ?? .distantPast
            let rightPublished = right.announcedAt ?? .distantPast
            if leftPublished != rightPublished { return leftPublished > rightPublished }
            let leftTime = leftDeadline ?? .distantPast
            let rightTime = rightDeadline ?? .distantPast
            if leftTime != rightTime { return leftTime > rightTime }
            return left.id < right.id
        }.first
    }

    static func hasPending(in records: [ResetRecord], now: Date) -> Bool {
        select(from: records, now: now) != nil
    }

    static func headline(for announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String {
        let countdown = countdownText(for: announcement, now: now, language: language)
        let phase = ResetScheduleTiming.phase(for: announcement, now: now)
        if isTerminal(announcement) || phase == .afterDate || phase == .afterExact {
            return countdown
        }
        return language.localized(chinese: "临时重置 · \(countdown)", english: "Temporary reset · \(countdown)")
    }

    static func countdownText(for announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String {
        let state = status(announcement)
        if state == "rolling_out" {
            return language.localized(chinese: "官方已开始发放重置福利", english: "Official reset rollout has started")
        }
        if cancelledStatuses.contains(state) {
            return language.localized(chinese: "临时重置已取消", english: "Temporary reset cancelled")
        }
        if completedStatuses.contains(state) {
            return language.localized(chinese: "来源已确认重置完成", english: "Source confirms reset completed")
        }
        guard let phase = ResetScheduleTiming.phase(for: announcement, now: now) else {
            return language.localized(chinese: "时间待公布", english: "Time not announced")
        }
        if phase == .afterDate {
            return language.localized(chinese: "预告日已过 · 等待确认", english: "Announced day passed · Awaiting confirmation")
        }
        guard let deadline = phase.countdownDeadline else {
            return language.localized(chinese: "预计时间已过 · 等待确认", english: "Expected time passed · Awaiting confirmation")
        }
        let remaining = max(1, Int(ceil(deadline.timeIntervalSince(now))))
        let days = remaining / 86_400
        let hours = phase == .duringDate(deadline) ? remaining / 3_600 : remaining % 86_400 / 3_600
        let minutes = remaining % 3_600 / 60
        let seconds = remaining % 60
        if language == .chinese {
            let dayText = days > 0 && phase != .duringDate(deadline) ? "\(days)天" : ""
            let prefix: String
            switch phase {
            case .beforeDate: prefix = "距预告日开始还剩 "
            case .duringDate: prefix = "预告日内还剩 "
            default: prefix = "还剩 "
            }
            return "\(prefix)\(dayText)\(hours)小时\(minutes)分\(seconds)秒"
        }
        let dayText = days > 0 && phase != .duringDate(deadline) ? "\(days)d " : ""
        let prefix: String
        switch phase {
        case .beforeDate: prefix = "Until announced day: "
        case .duringDate: prefix = "In announced day: "
        default: prefix = ""
        }
        return "\(prefix)\(dayText)\(hours)h \(minutes)m \(seconds)s left"
    }

    static func scheduleText(for announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String {
        ResetScheduleTiming.targetText(for: announcement, now: now, language: language)
    }

    private static let completedStatuses: Set<String> = ["completed", "confirmed", "propagated", "rolling_out"]
    private static let cancelledStatuses: Set<String> = ["cancelled", "canceled"]
    private static let pendingStatuses: Set<String> = ["scheduled", "announced", "watch", "pending"]

    private static func status(_ announcement: ResetAnnouncement) -> String {
        announcement.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    static func isTerminal(_ announcement: ResetAnnouncement) -> Bool {
        completedStatuses.contains(status(announcement)) || cancelledStatuses.contains(status(announcement))
    }

    private static func samePost(_ left: ResetAnnouncement, _ right: ResetAnnouncement) -> Bool {
        if left.id == right.id { return true }
        guard let leftURL = left.sourceURL, let rightURL = right.sourceURL else { return false }
        // A non-post site or profile URL is not an event identifier.
        let components = leftURL.path.split(separator: "/")
        guard components.count >= 3, components[components.count - 2] == "status",
              components.last?.allSatisfy(\.isNumber) == true else { return false }
        return leftURL.scheme == rightURL.scheme && leftURL.host == rightURL.host && leftURL.path == rightURL.path
    }

    /// No network, persistence, app lifecycle or notifications; executable without XCTest.
    static func runSelfChecks() throws -> Int {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw SummaryCheckError(message: message) }
            checks += 1
        }
        func record(_ id: String, offset: TimeInterval? = nil, status: String? = "scheduled",
                    age: TimeInterval = 0, unread: Bool = false, source: String? = nil) -> ResetRecord {
            let announcement = ResetAnnouncement(id: id, title: "重置预告", summary: "公开测试数据",
                sourceURL: source.flatMap(URL.init(string:)), announcedAt: now.addingTimeInterval(-age),
                scheduledFor: offset.map { now.addingTimeInterval($0) }, kind: "regular",
                scope: "all", status: status)
            return ResetRecord(id: id, announcement: announcement, isUnread: unread, occurredWhileAway: false)
        }
        let active = record("active", offset: 3_600)
        try check(select(from: [active], now: now)?.id == "active", "Read acknowledgement must not hide an active deadline")
        var unread = active
        unread.isUnread = true
        try check(select(from: [active], now: now) == select(from: [unread], now: now), "Summary must be independent of unread flags")
        let history = record("history", status: "completed", unread: true)
        try check(select(from: [history, active], now: now)?.id == "active", "A completed historical notice must not replace an active deadline")
        let nearest = record("nearest", offset: 60, age: 100)
        try check(select(from: [active, nearest], now: now)?.id == "nearest", "Nearest future deadline must win even when published earlier")
        let unknown = record("unknown", status: "watch")
        try check(select(from: [unknown, active], now: now)?.id == "active", "A known actionable deadline must remain visible beside an undated watch")
        try check(select(from: [record("old", status: "announced", age: 100), unknown], now: now)?.id == "unknown",
                  "Newest pending announcement wins when no future deadline is supplied")
        for state in ["completed", "confirmed", "propagated", "cancelled", "canceled", " COMPLETED "] {
            try check(select(from: [record(state, offset: 3_600, status: state)], now: now) == nil,
                      "Terminal status \(state) must not leave an active countdown")
        }
        let elapsed = record("elapsed", offset: -1)
        try check(select(from: [elapsed], now: now)?.id == "elapsed", "Elapsed scheduled time must remain pending until explicitly resolved")
        try check(headline(for: elapsed.announcement, now: now, language: .chinese) == "预计时间已过 · 等待确认",
                  "Elapsed time must not claim the reset completed")
        try check(headline(for: unknown.announcement, now: now, language: .chinese) == "临时重置 · 时间待公布",
                  "Missing reset time must not be inferred from publication time")
        try check(scheduleText(for: unknown.announcement, now: now, language: .chinese) == "预计时间待公布",
                  "Missing reset time must not display a fabricated clock time")
        let countdown = record("countdown", offset: 80_130)
        try check(countdownText(for: countdown.announcement, now: now, language: .chinese) == "还剩 22小时15分30秒",
                  "Prominent standalone countdown must omit the redundant heading")
        try check(headline(for: countdown.announcement, now: now, language: .chinese) == "临时重置 · 还剩 22小时15分30秒",
                  "Countdown must include exact remaining hours, minutes and seconds")
        try check(headline(for: countdown.announcement, now: now.addingTimeInterval(1), language: .chinese) == "临时重置 · 还剩 22小时15分29秒",
                  "Countdown must progress between clock ticks")
        let deadline = ISO8601DateFormatter().date(from: "2026-09-23T07:00:00Z")!
        var beijing = active.announcement
        beijing.scheduledFor = deadline
        try check(scheduleText(for: beijing, now: now, language: .chinese) == "预计：洛杉矶周三 00:00（接口时间）",
                  "An explicit instant must show Los Angeles clock time without a Beijing minute")
        try check(ResetScheduleTiming.beijingWeekdayText(for: beijing, now: now, language: .chinese) == "对应北京：周三",
                  "The estimate's Beijing conversion must show only its weekday")
        let boundary = ISO8601DateFormatter().date(from: "2026-09-23T06:59:00Z")!
        var dateOnly = active.announcement
        dateOnly.summary = "I promised a reset for Tuesday."
        dateOnly.scheduledFor = boundary
        let beforeDay = ISO8601DateFormatter().date(from: "2026-09-23T06:59:59Z")!.addingTimeInterval(-86_400)
        let dayStart = ISO8601DateFormatter().date(from: "2026-09-22T07:00:00Z")!
        let beforeBoundary = ISO8601DateFormatter().date(from: "2026-09-23T06:59:30Z")!
        let afterBoundary = ISO8601DateFormatter().date(from: "2026-09-23T07:00:00Z")!
        try check(countdownText(for: dateOnly, now: beforeDay, language: .chinese) == "距预告日开始还剩 0小时0分1秒",
                  "A weekday-only announcement must first count down to the announced day's start")
        try check(countdownText(for: dateOnly, now: dayStart, language: .chinese) == "预告日内还剩 24小时0分0秒",
                  "The announced day begins a fresh full-day countdown")
        try check(countdownText(for: dateOnly, now: beforeBoundary, language: .chinese) == "预告日内还剩 0小时0分30秒",
                  "The announced day must count through its final Los Angeles minute")
        try check(countdownText(for: dateOnly, now: afterBoundary, language: .chinese) == "预告日已过 · 等待确认",
                  "Only Los Angeles next-day midnight ends the date-only countdown")
        try check(ResetScheduleTiming.losAngelesNowText(afterBoundary, language: .chinese) == "洛杉矶现在：周三 00:00:00",
                  "The Los Angeles clock must retain weekday and seconds after the estimate")
        let oldSamePost = record("same", offset: -3_600, age: 7_200)
        let completedSamePost = record("same", status: "completed")
        try check(select(from: [oldSamePost, completedSamePost], now: now) == nil,
                  "A newer explicit completion for the same post must retire the preannouncement")
        let source = "https://x.com/thsottiaux/status/123456"
        let linked = record("old-id", offset: -3_600, age: 7_200, source: source)
        let linkedCompletion = record("new-id", status: "completed", source: source)
        try check(select(from: [linked, linkedCompletion], now: now) == nil,
                  "The same original post URL may link a resolved source record")
        try check(select(from: [oldSamePost, history], now: now)?.id == "same",
                  "Unrelated broad reset completion must not retire an unlinked older pending notice")
        try check(!hasPending(in: [history], now: now) && hasPending(in: [active], now: now),
                  "Pending indicator must represent actionable records, not unread history")
        return checks
    }

    private struct SummaryCheckError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
