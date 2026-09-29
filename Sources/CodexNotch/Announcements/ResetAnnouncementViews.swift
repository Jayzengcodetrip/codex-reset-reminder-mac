import SwiftUI

enum ResetAnnouncementFilter: String, CaseIterable {
    case all, undated, unread, away
}

/// The coordinator keeps this state when a window is hidden or brought forward.
/// Navigating to a list never acknowledges records; only opening a specific record does.
@MainActor
final class ResetAnnouncementsNavigation: ObservableObject {
    @Published var filter = ResetAnnouncementFilter.all
    @Published private(set) var selectedID: String?

    func showUndatedAnnouncements() {
        filter = .undated
        selectedID = nil
    }

    func selectRecord(id: String, markRead: (String) -> Void) {
        selectedID = id
        markRead(id)
    }

    func showDelivery(id: String, markRead: (String) -> Void) {
        filter = .all
        selectRecord(id: id, markRead: markRead)
    }

    func visibleRecords(from records: [ResetRecord], undated: [ResetAnnouncement]) -> [ResetRecord] {
        if filter == .undated {
            // Match the summary's active entries and their publication order.
            return undated.compactMap { announcement in records.first { $0.id == announcement.id } }
        }
        return records.filter { record in
            switch filter {
            case .all: return true
            case .undated: return false // Handled above to preserve the summary's order.
            case .unread: return record.isUnread
            case .away: return record.isUnread && record.occurredWhileAway
            }
        }
    }
}

/// Merely opening this window deliberately leaves every unread record intact.
/// A record is acknowledged only by selecting that record's details.
struct ResetAnnouncementsView: View {
    @ObservedObject var monitor: ResetMonitor
    @ObservedObject var navigation: ResetAnnouncementsNavigation
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage { AppLanguage.fromStoredValue(languageRaw) }

    private func label(_ chinese: String, _ english: String) -> String {
        language.localized(chinese: chinese, english: english)
    }

    private var presentation: ResetTopPresentation {
        ResetTopPresentation.make(pending: monitor.pendingAnnouncements, records: monitor.records, now: .now)
    }

    private var visibleRecords: [ResetRecord] {
        navigation.visibleRecords(from: monitor.records, undated: presentation.undatedAnnouncements)
    }

    private var selectedRecord: ResetRecord? {
        monitor.records.first { $0.id == navigation.selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            checkStatus
            if monitor.awayUnreadCount > 0 {
                Label(
                    label("离开期间，Tibo 有 \(monitor.awayUnreadCount) 条新的重置动态", "\(monitor.awayUnreadCount) new Tibo reset updates arrived while you were away"),
                    systemImage: "moon.zzz.fill"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.09))
            }
            Divider()
            HSplitView {
                archiveList
                    .frame(minWidth: 210, idealWidth: 225, maxWidth: 270)
                Group {
                    if let record = selectedRecord {
                        ResetAnnouncementDetailView(
                            announcement: record.announcement, language: language,
                            laterDelivery: presentation.archivedUndated[record.id],
                            onOpenDelivery: { delivery in
                                navigation.showDelivery(id: delivery.id, markRead: monitor.markRead)
                            }
                        )
                    } else {
                        detailPlaceholder
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 8) {
                Link("NextReset", destination: URL(string: "https://nextreset.net")!)
                Link("Codex Resets", destination: URL(string: "https://codex-resets.com")!)
                Link("NextReset.org", destination: URL(string: "https://nextreset.org")!)
                Text(label("· 按公开接口更新提醒", "· Alerts follow public sources"))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 600, idealWidth: 660, minHeight: 560, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(monitor.unreadCount > 0 ? Color.orange : Color.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(label("重置动态", "Reset updates"))
                    .font(.system(size: 21, weight: .semibold))
                Text(monitor.unreadCount > 0
                     ? label("\(monitor.unreadCount) 条未读 · 选择动态后标为已读", "\(monitor.unreadCount) unread · Select an update to mark it read")
                     : label("公告记录会保留，方便回来查看", "Announcement history stays available when you return"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if monitor.isChecking { ProgressView().controlSize(.small) }
            Button {
                monitor.refresh()
            } label: {
                Label(label("刷新", "Refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(monitor.isChecking)
        }
        .padding(20)
    }

    private var checkStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                ResetCheckPresentation.resultText(
                    isChecking: monitor.isChecking, errorMessage: monitor.errorMessage,
                    lastSuccessfulCheck: monitor.lastSuccessfulCheck,
                    hasPending: !monitor.pendingAnnouncements.isEmpty,
                    unreadCount: monitor.unreadCount, language: language,
                    hasNewPreannouncement: monitor.hasNewPreannouncement
                ),
                systemImage: monitor.isChecking ? "arrow.triangle.2.circlepath"
                    : monitor.errorMessage != nil ? "exclamationmark.triangle.fill"
                    : monitor.lastSuccessfulCheck != nil ? "checkmark.circle.fill" : "clock"
            )
            .foregroundStyle(monitor.isChecking ? Color.secondary
                             : monitor.errorMessage != nil ? Color.orange
                             : monitor.lastSuccessfulCheck != nil ? Color.mint : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if !monitor.isChecking, let error = monitor.errorMessage {
                Text(error).foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            statusLine(label("上次成功检查（北京时间）", "Last successful check (Beijing)"), date: monitor.lastSuccessfulCheck)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func statusLine(_ title: String, date: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
            Text(date.map(ResetAnnouncementDisplay.beijingDate) ?? label("尚未确认", "Not confirmed yet"))
                .monospacedDigit()
        }
    }

    private var archiveList: some View {
        VStack(spacing: 0) {
            Picker(label("筛选", "Filter"), selection: $navigation.filter) {
                Text(label("全部", "All")).tag(ResetAnnouncementFilter.all)
                Text(label("待定", "Time pending")).tag(ResetAnnouncementFilter.undated)
                Text(label("未读", "Unread")).tag(ResetAnnouncementFilter.unread)
                Text(label("离开期间", "Away")).tag(ResetAnnouncementFilter.away)
            }
            .pickerStyle(.menu)
            .padding(12)

            if visibleRecords.isEmpty {
                listPlaceholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(visibleRecords) { record in
                            Button {
                                navigation.selectRecord(id: record.id, markRead: monitor.markRead)
                            } label: {
                                recordLabel(record)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(record.announcement.title + (record.isUnread ? label("，未读", ", unread") : ""))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.black.opacity(0.12))
    }

    private func recordLabel(_ record: ResetRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(record.isUnread ? Color.orange : Color.clear)
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                Text(record.announcement.title)
                    .font(.system(size: 12, weight: record.isUnread ? .semibold : .medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if record.isUnread && record.occurredWhileAway {
                Text(label("恢复使用后补查到", "Found during catch-up"))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
                    .padding(.leading, 12)
            }
            if presentation.archivedUndated[record.id] != nil {
                Text(label("后续已有重置 · 本条关联未确认", "A later reset occurred · Link unconfirmed"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
            }
            Text(record.announcement.announcedAt.map(ResetAnnouncementDisplay.beijingDate)
                 ?? label("发布时间未提供", "Publication time unavailable"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(navigation.selectedID == record.id ? Color.white.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private var listPlaceholder: some View {
        VStack(spacing: 9) {
            Image(systemName: monitor.isChecking ? "arrow.clockwise" : "tray")
                .font(.system(size: 23))
            Text(listEmptyText)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listEmptyText: String {
        if navigation.filter == .undated { return label("没有仍待公布时间的预告", "No announcements are awaiting a time") }
        if navigation.filter == .unread { return label("没有未读的已接收动态", "No unread updates among received records") }
        if navigation.filter == .away { return label("没有未读的离开期间动态", "No unread updates received while away") }
        if monitor.isChecking { return label("正在读取公开公告…", "Reading public announcements…") }
        if monitor.lastSuccessfulCheck == nil { return label("尚未完成首次检查", "The first check has not completed") }
        if monitor.errorMessage != nil { return label("本次检查未完成，请查看上方状态", "This check did not complete; see the status above") }
        return label("公开接口暂未返回公告记录", "The public API returned no announcement records")
    }

    private var detailPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.mint.opacity(0.8))
            Text(label("选择一条重置动态", "Select a reset update"))
                .font(.system(size: 16, weight: .semibold))
            Text(label("查看公告、北京时间和原帖。\n打开窗口不会清除未读标记。", "View the announcement, Beijing time and original post.\nOpening this window does not clear unread updates."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

private struct ResetAnnouncementDetailView: View {
    let announcement: ResetAnnouncement
    let language: AppLanguage
    let laterDelivery: ResetAnnouncement?
    let onOpenDelivery: (ResetAnnouncement) -> Void

    private func label(_ chinese: String, _ english: String) -> String {
        language.localized(chinese: chinese, english: english)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text(announcement.title)
                    .font(.system(size: 19, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 7) {
                        if let laterDelivery {
                            Text(label("后续已有重置 · 本条关联未确认", "A later reset occurred · Link unconfirmed"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(label("已从首页待定摘要收起，保留在历史中；这不代表本条预告已完成。",
                                       "This announcement is no longer in the time-pending summary and remains in history. Its completion has not been confirmed."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                onOpenDelivery(laterDelivery)
                            } label: {
                                Label(label("查看后续发放消息", "View the later delivery"), systemImage: "arrow.right.circle")
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 12, weight: .medium))
                        } else {
                            Text(ResetAnnouncementDisplay.timingText(announcement, now: context.date, language: language))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(ResetAnnouncementDisplay.isCompleted(announcement) ? Color.mint : Color.orange)
                            if announcement.scheduledFor != nil,
                               ResetScheduleTiming.phase(for: announcement, now: context.date) != .afterDate {
                                Text(ResetScheduleTiming.targetText(for: announcement, now: context.date, language: language))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                if let beijingWeekday = ResetScheduleTiming.beijingWeekdayText(for: announcement, now: context.date, language: language) {
                                    Text(beijingWeekday)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                if ResetScheduleTiming.target(for: announcement)?.isDateBoundaryEstimate == true {
                                    Text(ResetScheduleTiming.dateBoundaryExplanation(for: announcement, now: context.date, language: language))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    if let risk = ResetScheduleTiming.quotaRiskText(for: announcement, now: context.date, language: language) {
                                        Text(risk)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.orange)
                                    }
                                }
                            }
                        }
                        if !ResetAnnouncementSummary.isTerminal(announcement) {
                            Text(ResetScheduleTiming.losAngelesNowText(context.date, language: language))
                                .font(.system(size: 11, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                }

                if let published = announcement.announcedAt {
                    Text(label("公告发布：", "Announcement posted: ") + ResetAnnouncementDisplay.beijingDate(published) + label(" 北京时间", " Beijing"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if !announcement.summary.isEmpty {
                    Text(announcement.summary)
                        .font(.system(size: 13))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let evidence = announcement.completionEvidence {
                    Text(label("发放判定依据：", "Delivery evidence: ") + evidence)
                        .font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if announcement.deliveryAt != nil {
                    Link("Data from Codex Resets", destination: URL(string: "https://codex-resets.com")!)
                        .font(.system(size: 10))
                }
                if !announcement.scope.isEmpty {
                    Text(label("适用范围：", "Scope: ") + ResetAnnouncementDisplay.scopeText(announcement.scope, language: language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if let source = ResetAnnouncementDisplay.safeSourceURL(announcement.sourceURL) {
                    Link(destination: source) {
                        Label(label("查看原帖", "Open original post"), systemImage: "arrow.up.right.square")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum ResetAnnouncementDisplay {
    static func scopeText(_ scope: String, language: AppLanguage) -> String {
        switch scope.lowercased() {
        case "broad": return language.localized(chinese: "广泛账户，具体以公告为准", english: "Broad; see announcement for eligibility")
        case "limited": return language.localized(chinese: "部分受影响账户", english: "Limited affected accounts")
        case "unspecified", "unknown": return language.localized(chinese: "原公告未明确", english: "Not specified in the original announcement")
        default: return scope
        }
    }
    private static let beijingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func beijingDate(_ date: Date) -> String {
        beijingFormatter.string(from: date)
    }

    static func isCompleted(_ announcement: ResetAnnouncement) -> Bool {
        guard let status = announcement.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return ["completed", "confirmed", "propagated"].contains(status)
    }

    static func timingText(_ announcement: ResetAnnouncement, now: Date, language: AppLanguage) -> String {
        if announcement.status?.lowercased() == "rolling_out" {
            return language.localized(chinese: "官方已开始发放重置福利", english: "Official reset rollout has started")
        }
        if isCompleted(announcement) {
            return language.localized(chinese: "来源已确认重置完成", english: "Source confirms the reset is complete")
        }
        if ["cancelled", "canceled"].contains(announcement.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") {
            return language.localized(chinese: "来源已取消这次重置", english: "Source reports this reset was cancelled")
        }
        guard let target = ResetScheduleTiming.target(for: announcement) else {
            return language.localized(chinese: "公告未提供明确重置时间", english: "No exact reset time was provided")
        }
        if ResetScheduleTiming.phase(for: announcement, now: now) == .afterDate {
            return language.localized(chinese: "预告日已过 · 等待确认", english: "Announced day passed · Awaiting confirmation")
        }
        guard target.countdownDeadline > now else {
            return language.localized(chinese: "预计时间已过，待确认", english: "Expected time has passed; awaiting confirmation")
        }
        return ResetAnnouncementSummary.countdownText(for: announcement, now: now, language: language)
    }

    static func safeSourceURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "nextreset.net"].contains(host) else { return nil }
        return url
    }
}
