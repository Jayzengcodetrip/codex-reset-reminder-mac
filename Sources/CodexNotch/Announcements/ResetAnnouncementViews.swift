import SwiftUI

enum ResetAnnouncementFilter: String, CaseIterable {
    case all, undated
}

/// The coordinator keeps this state when a window is hidden or brought forward.
@MainActor
final class ResetAnnouncementsNavigation: ObservableObject {
    @Published var filter = ResetAnnouncementFilter.all
    @Published private(set) var selectedID: String?
    @Published private(set) var accountReceipt: AccountResetReceipt?

    func updateAccountReceipt(_ receipt: AccountResetReceipt?) {
        accountReceipt = receipt
    }

    func showUndatedAnnouncements() {
        filter = .undated
        selectedID = nil
    }

    func selectRecord(id: String) {
        selectedID = id
    }

    func showDelivery(id: String) {
        filter = .all
        selectedID = id
    }

    func visibleRecords(from records: [ResetRecord], activePending: [ResetAnnouncement]) -> [ResetRecord] {
        switch filter {
        case .all:
            return records
        case .undated:
            // Match the active previews in publication order.
            return activePending.compactMap { announcement in records.first { $0.id == announcement.id } }
        }
    }
}

struct ResetAnnouncementsView: View {
    @ObservedObject var monitor: ResetMonitor
    @ObservedObject var navigation: ResetAnnouncementsNavigation
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage { AppLanguage.fromStoredValue(languageRaw) }

    private func label(_ chinese: String, _ english: String) -> String {
        language.localized(chinese: chinese, english: english)
    }

    private var presentation: ResetTopPresentation {
        ResetTopPresentation.make(pending: monitor.pendingAnnouncements, records: monitor.records,
                                  now: .now, accountReceipt: navigation.accountReceipt)
    }

    private func activePending(for currentPresentation: ResetTopPresentation) -> [ResetAnnouncement] {
        (currentPresentation.announcements + currentPresentation.undatedAnnouncements).sorted { lhs, rhs in
            let left = lhs.announcedAt ?? .distantPast
            let right = rhs.announcedAt ?? .distantPast
            return left == right ? lhs.id < rhs.id : left < right
        }
    }

    private func visibleRecords(for currentPresentation: ResetTopPresentation) -> [ResetRecord] {
        navigation.visibleRecords(from: monitor.records, activePending: activePending(for: currentPresentation))
    }

    private var selectedRecord: ResetRecord? {
        monitor.records.first { $0.id == navigation.selectedID }
    }

    var body: some View {
        let currentPresentation = presentation
        VStack(spacing: 0) {
            header(hasActivePreview: currentPresentation.hasActivePreview)
            checkStatus
            Divider()
            HSplitView {
                archiveList(presentation: currentPresentation)
                    .frame(minWidth: 210, idealWidth: 225, maxWidth: 270)
                Group {
                    if let record = selectedRecord {
                        ResetAnnouncementDetailView(
                            announcement: record.announcement, language: language,
                            laterDelivery: currentPresentation.archivedUndated[record.id],
                            laterAccountReceipt: currentPresentation.archivedForAccountReceipt[record.id],
                            manualCompletedAt: record.manualCompletedAt,
                            manualDismissedAt: record.manualDismissedAt,
                            canConfirmManually: monitor.canConfirmResetManually(id: record.id),
                            canDismissManually: monitor.canDismissPreviewManually(id: record.id),
                            onConfirmManually: { monitor.confirmResetManually(id: record.id) },
                            onUndoManualConfirmation: { monitor.undoManualResetConfirmation(id: record.id) },
                            onDismissManually: { monitor.dismissPreviewManually(id: record.id) },
                            onUndoManualDismissal: { monitor.undoManualPreviewDismissal(id: record.id) },
                            onOpenDelivery: { delivery in
                                navigation.showDelivery(id: delivery.id)
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
        .alert(label("操作未保存", "Unable to save"), isPresented: Binding(
            get: { monitor.manualConfirmationErrorMessage != nil },
            set: { if !$0 { monitor.clearManualConfirmationError() } }
        )) {
            Button(label("好", "OK"), role: .cancel) {
                monitor.clearManualConfirmationError()
            }
        } message: {
            Text(monitor.manualConfirmationErrorMessage
                 ?? label("本次操作未能保存，请稍后重试。", "This change could not be saved. Please try again."))
        }
    }

    private func header(hasActivePreview: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: hasActivePreview ? "bell.badge" : "bell")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(hasActivePreview ? Color.orange : Color.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(label("重置动态", "Reset updates"))
                    .font(.system(size: 21, weight: .semibold))
                Text(label("公告记录会保留，方便回来查看", "Announcement history stays available when you return"))
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
                    unreadCount: 0, language: language,
                    hasNewPreannouncement: monitor.hasNewPreannouncement
                ),
                systemImage: monitor.isChecking ? "arrow.triangle.2.circlepath"
                    : monitor.errorMessage != nil ? "exclamationmark.triangle.fill"
                    : monitor.lastSuccessfulCheck != nil ? "checkmark.circle.fill" : "clock"
            )
            .foregroundStyle(monitor.isChecking ? Color.secondary
                             : monitor.errorMessage != nil ? ResetAnnouncementEntriesView.errorColor
                             : monitor.lastSuccessfulCheck != nil ? Color.mint : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if !monitor.isChecking, let error = monitor.errorMessage {
                Text(error).foregroundStyle(ResetAnnouncementEntriesView.errorColor)
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

    private func archiveList(presentation currentPresentation: ResetTopPresentation) -> some View {
        let records = visibleRecords(for: currentPresentation)
        let activeIDs = Set(activePending(for: currentPresentation).map(\.id))
        return VStack(spacing: 0) {
            Picker(label("筛选", "Filter"), selection: $navigation.filter) {
                Text(label("全部", "All")).tag(ResetAnnouncementFilter.all)
                Text(label("待定", "Pending")).tag(ResetAnnouncementFilter.undated)
            }
            .pickerStyle(.menu)
            .padding(12)

            if records.isEmpty {
                listPlaceholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(records) { record in
                            Button {
                                navigation.selectRecord(id: record.id)
                            } label: {
                                recordLabel(record, presentation: currentPresentation,
                                            isActive: activeIDs.contains(record.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(record.announcement.title)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color.black.opacity(0.12))
    }

    private func recordLabel(_ record: ResetRecord, presentation currentPresentation: ResetTopPresentation,
                             isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.announcement.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if record.manualCompletedAt != nil {
                Text(label("已人工确认重置完成", "Manually confirmed complete"))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.mint)
                    .fixedSize(horizontal: false, vertical: true)
            } else if record.manualDismissedAt != nil {
                Text(label("已手动收起 · 仅从首页隐藏", "Hidden from home"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if currentPresentation.archivedUndated[record.id] != nil {
                Text(label("后续已有重置 · 本条关联未确认", "A later reset occurred · Link unconfirmed"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let receipt = currentPresentation.archivedForAccountReceipt[record.id] {
                Text(label("本账户已收到重置券 · 本条关联未确认", "Reset credit received in this account · Link unconfirmed"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(label("到账：", "Granted: ") + ResetAnnouncementDisplay.beijingTimestamp(receipt.grantedAt)
                     + label(" 北京时间", " Beijing"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if isActive {
                Text(label("进行中", "Active"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
            Text(record.announcement.announcedAt.map(ResetAnnouncementDisplay.beijingDate)
                 ?? label("发布时间未提供", "Publication time unavailable"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
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
        if navigation.filter == .undated { return label("没有进行中的待定预告", "No active pending previews") }
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
            Text(label("查看公告详情、发布时间和原帖。", "View the announcement details, publication time and original post."))
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
    let laterAccountReceipt: AccountResetReceipt?
    let manualCompletedAt: Date?
    let manualDismissedAt: Date?
    let canConfirmManually: Bool
    let canDismissManually: Bool
    let onConfirmManually: () -> Void
    let onUndoManualConfirmation: () -> Void
    let onDismissManually: () -> Void
    let onUndoManualDismissal: () -> Void
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
                        if let manualCompletedAt {
                            Text(label("已人工确认重置完成", "Manually confirmed complete"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.mint)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(label("人工确认：", "Confirmed by you: ")
                                 + ResetAnnouncementDisplay.beijingTimestamp(manualCompletedAt)
                                 + label(" 北京时间", " Beijing"))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(label("计时从这次人工确认开始；这是你的确认，不代表官方公告。",
                                       "The timer starts when you confirm. This is your confirmation, not an official announcement."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(action: onUndoManualConfirmation) {
                                Label(label("撤销人工确认", "Undo manual confirmation"), systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 12, weight: .medium))
                            .help(label("撤销这次人工确认；按现有公告与账户记录重新显示状态和计时。",
                                        "Remove your confirmation and use the remaining announcement and account evidence for the status and timer."))
                        } else if let manualDismissedAt {
                            Text(label("已手动收起 · 仅从首页隐藏", "Hidden from home"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(label("收起时间：", "Hidden at: ")
                                 + ResetAnnouncementDisplay.beijingTimestamp(manualDismissedAt)
                                 + label(" 北京时间", " Beijing"))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(label("仅从首页预告卡片移除，未改动重置计时，也不代表重置已完成。",
                                       "Removed from the home card only. Reset timers were not changed and this preview is not marked complete."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(action: onUndoManualDismissal) {
                                Label(label("恢复到首页", "Restore to home"), systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.link)
                            .font(.system(size: 12, weight: .medium))
                            .help(label("恢复这条预告在首页显示（若尚未完成或取消）。",
                                        "Show this preview on the home card again if still active."))
                        } else if let laterDelivery {
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
                        } else if let receipt = laterAccountReceipt {
                            Text(label("本账户已收到重置券 · 本条关联未确认",
                                       "Reset credit received in this account · Link unconfirmed"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(label("到账时间：", "Credit granted: ")
                                 + ResetAnnouncementDisplay.beijingTimestamp(receipt.grantedAt)
                                 + label(" 北京时间", " Beijing"))
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(label("这张券需要你自行使用。较早预告只从首页收起，未证实与本次到账有关，也未标记为完成。",
                                       "You must redeem this credit yourself. The older preview left the home summary, but its relation to this grant is unconfirmed and the preview remains unresolved."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !ResetAnnouncementSummary.isTerminal(announcement),
                                  ResetScheduleTiming.target(for: announcement) == nil {
                            if let elapsed = ResetUndatedSummary.elapsedText(for: announcement, now: context.date, language: language) {
                                Text(elapsed)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.orange)
                            }
                            Text(label("公告未提供明确重置时间", "No exact reset time was provided"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(ResetAnnouncementDisplay.timingText(announcement, now: context.date, language: language))
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(ResetAnnouncementDisplay.isCompleted(announcement) ? Color.mint : Color.orange)
                            if announcement.scheduledFor != nil,
                               ResetScheduleTiming.phase(for: announcement, now: context.date) != .afterDate,
                               ResetScheduleTiming.target(for: announcement)?.isDateBoundaryEstimate == true {
                                Text(ResetScheduleTiming.dateBoundaryExplanation(for: announcement, now: context.date, language: language))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if manualCompletedAt == nil && manualDismissedAt == nil && (canConfirmManually || canDismissManually) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .center, spacing: 8) {
                                    if canConfirmManually {
                                        Button(action: onConfirmManually) {
                                            Label(label("确认已重置", "Confirm reset"), systemImage: "checkmark.circle")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Color.mint)
                                        .controlSize(.small)
                                        .accessibilityLabel(label("人工确认这条预告已重置", "Manually confirm this announcement’s reset"))
                                    }
                                    if canDismissManually {
                                        Button(action: onDismissManually) {
                                            Label(label("收起预告", "Hide preview"), systemImage: "eye.slash")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .accessibilityLabel(label("仅从首页收起这条预告", "Hide this preview from the home card only"))
                                    }
                                }
                                Text(label("「确认已重置」会从点击时重算重置计时；「收起预告」仅隐藏首页卡片，不动计时。",
                                           "“Confirm reset” restarts the reset timer now; “Hide preview” only removes it from the home card."))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 4)
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

    private static let beijingTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func beijingTimestamp(_ date: Date) -> String {
        beijingTimestampFormatter.string(from: date)
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
