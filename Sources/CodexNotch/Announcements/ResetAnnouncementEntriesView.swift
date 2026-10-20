import SwiftUI

/// Undated posts share one compact summary; only usable dates get a countdown card.
struct ResetAnnouncementEntriesView: View {
    let unreadCount: Int
    let awayUnreadCount: Int
    let statusText: String
    let announcements: [ResetAnnouncement]
    var undatedAnnouncements: [ResetAnnouncement] = []
    let now: Date
    let language: AppLanguage
    var didResetToday: Bool = false
    var secondsSinceLastDelivery: Int? = nil
    var latestDeliveryOrigin: ResetDeliveryOrigin? = nil
    var unconfirmedRecovery: AccountQuotaRecovery? = nil
    let action: () -> Void
    var undatedAction: () -> Void = {}
    var confirmAction: (String) -> Void = { _ in }
    var restartTimerAction: () -> Void = {}

    static let summaryHeight: CGFloat = 120
    static let deliveryHeight: CGFloat = 30
    static let sectionSpacing: CGFloat = 6
    static let maximumHeight: CGFloat = 284

    static func deliveryFooterHeight(origin: ResetDeliveryOrigin?) -> CGFloat {
        origin == .manualConfirmation || origin == .manualTimerRestart ? 16 : deliveryHeight
    }

    // Retained for existing callers that only have timed countdowns.
    static func height(for count: Int) -> CGFloat {
        let visibleCount = min(2, max(1, count))
        let entryHeight = count == 0 ? ResetAnnouncementEntryView.emptyHeight : ResetAnnouncementEntryView.announcementHeight
        return CGFloat(visibleCount) * entryHeight + CGFloat(visibleCount - 1) * 8
    }

    static func height(for presentation: ResetTopPresentation, unreadCount: Int = 0) -> CGFloat {
        height(timedCount: presentation.announcements.count,
               hasUndated: !presentation.undatedAnnouncements.isEmpty,
               hasDelivery: presentation.secondsSinceLastDelivery != nil,
               hasUnconfirmed: presentation.unconfirmedAccountRecovery != nil,
               deliveryOrigin: presentation.latestDeliveryOrigin,
               emptyCardHeight: ResetAnnouncementEntryView.emptyCardHeight(
                   unreadCount: unreadCount, didResetToday: presentation.didResetToday,
                   origin: presentation.latestDeliveryOrigin))
    }

    static func height(timedCount: Int, hasUndated: Bool, hasDelivery: Bool,
                       hasUnconfirmed: Bool = false,
                       deliveryOrigin: ResetDeliveryOrigin? = nil,
                       emptyCardHeight: CGFloat = ResetAnnouncementEntryView.emptyHeight) -> CGFloat {
        let footer = (hasDelivery ? deliveryFooterHeight(origin: deliveryOrigin) : 16) + sectionSpacing
            + (hasUnconfirmed ? deliveryHeight + sectionSpacing : 0)
        guard timedCount > 0 || hasUndated else {
            return emptyCardHeight + footer
        }
        let count = timedCount + (hasUndated ? 1 : 0)
        let cards = CGFloat(timedCount) * ResetAnnouncementEntryView.announcementHeight
            + (hasUndated ? summaryHeight : 0) + CGFloat(max(0, count - 1)) * 8
        return min(maximumHeight, cards + footer)
    }

    private var hasActive: Bool { !announcements.isEmpty || !undatedAnnouncements.isEmpty }
    private var height: CGFloat {
        Self.height(timedCount: announcements.count, hasUndated: !undatedAnnouncements.isEmpty,
                    hasDelivery: secondsSinceLastDelivery != nil, hasUnconfirmed: unconfirmedRecovery != nil,
                    deliveryOrigin: latestDeliveryOrigin, emptyCardHeight: emptyCardHeight)
    }
    private var footerHeight: CGFloat {
        (secondsSinceLastDelivery != nil ? Self.deliveryFooterHeight(origin: latestDeliveryOrigin) : 16) + Self.sectionSpacing
            + (unconfirmedRecovery != nil ? Self.deliveryHeight + Self.sectionSpacing : 0)
    }
    private var emptyCardHeight: CGFloat {
        ResetAnnouncementEntryView.emptyCardHeight(unreadCount: unreadCount, didResetToday: didResetToday,
                                                  origin: latestDeliveryOrigin)
    }
    private var contentHeight: CGFloat {
        guard hasActive else { return emptyCardHeight }
        let count = announcements.count + (undatedAnnouncements.isEmpty ? 0 : 1)
        return CGFloat(announcements.count) * ResetAnnouncementEntryView.announcementHeight
            + (undatedAnnouncements.isEmpty ? 0 : Self.summaryHeight) + CGFloat(max(0, count - 1)) * 8
    }

    var body: some View {
        VStack(spacing: footerHeight > 0 ? Self.sectionSpacing : 0) {
            Group {
                if contentHeight > height - footerHeight {
                    ScrollView(.vertical) { cards }
                        .scrollIndicators(.visible)
                } else {
                    cards
                }
            }
            .frame(height: height - footerHeight)
            if let seconds = secondsSinceLastDelivery {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Self.deliveryAgeHeading(origin: latestDeliveryOrigin, language: language)
                             + ResetTopPresentation.elapsedText(seconds: seconds, language: language))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.mint)
                            .lineLimit(1)
                            .layoutPriority(1)
                        restartTimerButton
                        Spacer(minLength: 0)
                    }
                    let footnote = Self.deliveryFootnote(origin: latestDeliveryOrigin, language: language)
                    if !footnote.isEmpty {
                        Text(footnote)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .frame(height: Self.deliveryFooterHeight(origin: latestDeliveryOrigin))
            } else {
                HStack(spacing: 6) {
                    Text(language.localized(chinese: "尚未记录重置时间", english: "No reset time recorded"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                    restartTimerButton
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .frame(height: 16)
            }
            if let recovery = unconfirmedRecovery {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.unconfirmedHeading(language: language))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.orange)
                    Text(language.localized(chinese: "确认原因后更新重置计时", english: "Reset timer updates when the cause is confirmed"))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .frame(height: Self.deliveryHeight)
                .accessibilityElement(children: .combine)
                .help(language.localized(chinese: "首次检测：", english: "First detected: ")
                      + ResetAnnouncementDisplay.beijingTimestamp(recovery.detectedAt) + " (UTC+8)")
            }
        }
        .frame(height: height)
    }

    private var restartTimerButton: some View {
        Button(action: restartTimerAction) {
            Label(language.localized(chinese: "重新计时", english: "Restart timer"), systemImage: "arrow.counterclockwise")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(Color.white.opacity(0.09), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("manual-reset-timer-restart")
        .help(language.localized(chinese: "已确认额度重置？点击后从现在重新计时，无需预告。不会使用重置券。",
                                 english: "Quota reset confirmed? Restart this clock from now, even without an announcement. No reset credits are used."))
    }

    static func unconfirmedHeading(language: AppLanguage) -> String {
        language.localized(chinese: "本账户额度已恢复 · 方式待确认", english: "Account quota recovered · Cause unconfirmed")
    }

    static func deliveryAgeHeading(origin: ResetDeliveryOrigin?, language: AppLanguage) -> String {
        if origin == .accountReceipt {
            return language.localized(chinese: "距本账户收到重置券已过 ",
                                      english: "Since this account received a reset credit: ")
        }
        return language.localized(chinese: "距上次重置已过 ", english: "Since last reset: ")
    }

    static func deliveryFootnote(origin: ResetDeliveryOrigin?, language: AppLanguage) -> String {
        if origin == .manualConfirmation || origin == .manualTimerRestart {
            return ""
        }
        if case let .accountRecovery(kind) = origin {
            switch kind {
            case .manualCredit:
                return language.localized(chinese: "手动用券 · 按重置券兑换完成时间计时",
                                          english: "Manual credit · From the recorded redemption time")
            case .weekly:
                return language.localized(chinese: "正常周重置 · 按首次检测到恢复的时间计时",
                                          english: "Weekly reset · From the first recovery observation")
            case .officialTemporary:
                return language.localized(chinese: "官方临时重置期间恢复 · 按首次检测时间计时",
                                          english: "Recovered during an official reset · From first detection")
            case .unconfirmed:
                return language.localized(chinese: "本账户额度已恢复 · 方式待确认",
                                          english: "Account quota recovered · Cause unconfirmed")
            }
        }
        if origin == .accountReceipt {
            return language.localized(chinese: "按本账户重置券发放时间计时，需自行使用",
                                      english: "From this account's credit grant; redeem it yourself")
        }
        return language.localized(chinese: "按官方发放消息计时，不代表账户到账",
                                  english: "From the official rollout post; account receipt may vary")
    }

    private var cards: some View {
        VStack(spacing: 8) {
            if !hasActive {
                ResetAnnouncementEntryView(unreadCount: unreadCount, awayUnreadCount: awayUnreadCount,
                    statusText: statusText, announcement: nil,
                    now: now, language: language, didResetToday: didResetToday,
                    secondsSinceLastDelivery: secondsSinceLastDelivery,
                    latestDeliveryOrigin: latestDeliveryOrigin, action: action)
            } else {
                ForEach(Array(announcements.reversed()), id: \.id) { announcement in
                    ResetAnnouncementEntryView(
                        unreadCount: announcement.id == announcements.last?.id ? unreadCount : 0,
                        awayUnreadCount: announcement.id == announcements.last?.id ? awayUnreadCount : 0,
                        statusText: statusText, announcement: announcement,
                        now: now, language: language, didResetToday: didResetToday,
                        secondsSinceLastDelivery: secondsSinceLastDelivery,
                        latestDeliveryOrigin: latestDeliveryOrigin, action: action,
                        manualConfirmationAction: { confirmAction(announcement.id) })
                }
                if let latest = undatedAnnouncements.last {
                    undatedSummary(latest)
                }
            }
        }
    }

    private func undatedSummary(_ latest: ResetAnnouncement) -> some View {
        Button(action: undatedAction) {
            HStack(spacing: 10) {
                Image(systemName: awayUnreadCount > 0 || unreadCount > 0 ? "bell.badge" : "text.bubble")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ResetUndatedSummary.title(count: undatedAnnouncements.count, language: language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(ResetUndatedSummary.excerpt(latest, language: language))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ResetUndatedSummary.publication(latest, language: language))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                    Text(ResetScheduleTiming.losAngelesNowText(now, language: language))
                        .font(.system(size: 10.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.85))
                    if unreadCount > 0 {
                        Text(awayUnreadCount > 0
                             ? language.localized(chinese: "离开期间有 \(awayUnreadCount) 条动态更新", english: "\(awayUnreadCount) updates while away")
                             : language.localized(chinese: "有 \(unreadCount) 条未读动态", english: "\(unreadCount) unread updates"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                    Text(statusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(.horizontal, 12)
            .frame(height: Self.summaryHeight)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.12), lineWidth: 0.5) }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .help(language.localized(chinese: "查看待定预告列表；打开不会清除未读", english: "View undated previews without clearing unread updates"))
    }
}

/// A stable-height entry keeps announcement updates from moving the quota card.
struct ResetAnnouncementEntryView: View {
    static let emptyHeight: CGFloat = 48

    static func emptyCardHeight(unreadCount: Int, didResetToday: Bool, origin: ResetDeliveryOrigin?) -> CGFloat {
        // Keep ordinary two-line content compact, reserving only the rows that
        // actually exist for unread updates and a public same-day delivery.
        let publicToday = didResetToday && (origin == nil || origin == .publicAnnouncement)
        return emptyHeight + (unreadCount > 0 ? 14 : 0) + (publicToday ? 16 : 0)
    }
    static let announcementHeight: CGFloat = 138

    let unreadCount: Int
    let awayUnreadCount: Int
    let statusText: String
    let announcement: ResetAnnouncement?
    let now: Date
    let language: AppLanguage
    var didResetToday: Bool = false
    var secondsSinceLastDelivery: Int? = nil
    var latestDeliveryOrigin: ResetDeliveryOrigin? = nil
    let action: () -> Void
    var manualConfirmationAction: (() -> Void)? = nil

    static func emptyHeadline(didResetToday: Bool, origin: ResetDeliveryOrigin?, language: AppLanguage) -> String {
        if case .accountRecovery = origin {
            return language.localized(chinese: "暂无最新重置预告", english: "No new reset announcements")
        }
        if origin == .accountReceipt || origin == .manualConfirmation || origin == .manualTimerRestart {
            return language.localized(chinese: "暂无最新重置预告",
                                      english: "No new reset announcements")
        }
        if didResetToday {
            return language.localized(chinese: "暂无最新重置预告（今天已重置）",
                                      english: "No new reset announcements (reset delivered today)")
        }
        return language.localized(chinese: "暂无最新重置预告", english: "No new reset announcements")
    }

    private var title: String {
        if announcement != nil {
            let heading = language.localized(chinese: "临时重置预告", english: "Temporary reset ahead")
            if awayUnreadCount > 0 {
                return heading + language.localized(chinese: " · 离开期间有更新", english: " · Updates while away")
            }
            return heading + (unreadCount > 0 ? language.localized(chinese: " · 有未读更新", english: " · Unread updates") : "")
        }
        return Self.emptyHeadline(didResetToday: didResetToday, origin: latestDeliveryOrigin, language: language)
    }

    private var highlighted: Bool { announcement != nil }

    private var accessibilityText: String {
        guard let announcement else { return title + "，" + statusText }
        var lines = [title, ResetAnnouncementSummary.headline(for: announcement, now: now, language: language)]
        if ResetScheduleTiming.phase(for: announcement, now: now) != .afterDate {
            lines.append(ResetAnnouncementSummary.scheduleText(for: announcement, now: now, language: language))
            if let beijing = ResetScheduleTiming.beijingWeekdayText(for: announcement, now: now, language: language) {
                lines.append(beijing)
            }
            if let risk = ResetScheduleTiming.quotaRiskText(for: announcement, now: now, language: language) {
                lines.append(risk)
            }
        }
        lines.append(ResetScheduleTiming.losAngelesNowText(now, language: language))
        lines.append(statusText)
        return lines.joined(separator: "，")
    }

    static func confirmationLabel(language: AppLanguage) -> String {
        language.localized(chinese: "确认已重置", english: "Confirm reset")
    }

    private var confirmationButton: some View {
        Button(action: { manualConfirmationAction?() }) {
            Label(Self.confirmationLabel(language: language), systemImage: "checkmark.circle")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .overlay { Capsule().stroke(Color.orange.opacity(0.4), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("manual-reset-confirm-" + (announcement?.id ?? ""))
        .help(language.localized(
            chinese: "将这条预告标为人工确认完成，并从点击时刻重新计时；可在公告详情撤销",
            english: "Complete this preview and restart its timer now. Undo in announcement details."))
    }

    var body: some View {
        // Sibling buttons keep confirmation independent from opening history.
        ZStack {
            Button(action: action) {
                Color.clear.contentShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText)
            .accessibilityIdentifier("reset-announcement-open-" + (announcement?.id ?? "empty"))
            .help(language.localized(chinese: "查看公告详情；查看额度不会清除未读",
                                     english: "View announcements; checking quota does not clear unread updates"))

            HStack(spacing: 10) {
                Image(systemName: announcement != nil ? "clock.fill" : (unreadCount > 0 ? "bell.badge.fill" : "bell"))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(highlighted ? Color.orange : Color.secondary)
                    .frame(width: 25)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    if let announcement {
                        Group {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(ResetAnnouncementSummary.countdownText(for: announcement, now: now, language: language))
                                .font(.system(size: ResetScheduleTiming.phase(for: announcement, now: now) == .afterDate ? 13 : 18,
                                              weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color.orange)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        if ResetScheduleTiming.phase(for: announcement, now: now) != .afterDate {
                            HStack(spacing: 6) {
                                Text(ResetAnnouncementSummary.scheduleText(for: announcement, now: now, language: language))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                if manualConfirmationAction != nil { confirmationButton }
                            }
                            Group {
                                if let beijingWeekday = ResetScheduleTiming.beijingWeekdayText(for: announcement, now: now, language: language) {
                                    Text(beijingWeekday)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                                if let risk = ResetScheduleTiming.quotaRiskText(for: announcement, now: now, language: language) {
                                    Text(risk)
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(Color.orange.opacity(0.9))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        } else if manualConfirmationAction != nil {
                            confirmationButton
                        }
                        Text(ResetScheduleTiming.losAngelesNowText(now, language: language))
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    } else {
                        Text(title.replacingOccurrences(of: "（", with: "\n（"))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(didResetToday ? Color.green : Color.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    Group {
                        if announcement == nil && unreadCount > 0 {
                            Text(awayUnreadCount > 0
                                ? language.localized(chinese: "离开期间有 \(awayUnreadCount) 条更新 · 点击查看", english: "\(awayUnreadCount) updates while away · View history")
                                : language.localized(chinese: "\(unreadCount) 条未读动态 · 点击查看", english: "\(unreadCount) unread updates · View history"))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.orange)
                                .lineLimit(1)
                        }
                        Text(statusText)
                            .font(.system(size: announcement == nil ? 10.5 : 9.5))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .lineLimit(announcement == nil ? 2 : 1)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity,
               minHeight: announcement == nil ? Self.emptyCardHeight(unreadCount: unreadCount, didResetToday: didResetToday, origin: latestDeliveryOrigin) : Self.announcementHeight,
               maxHeight: announcement == nil ? Self.emptyCardHeight(unreadCount: unreadCount, didResetToday: didResetToday, origin: latestDeliveryOrigin) : Self.announcementHeight)
        .background(highlighted ? Color.orange.opacity(0.12) : Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(highlighted ? Color.orange.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}
