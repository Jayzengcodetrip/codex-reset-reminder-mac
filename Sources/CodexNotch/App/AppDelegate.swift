import AppKit

enum AppIdentity {
    static let bundleIdentifier = "io.github.jayzengcodetrip.codexresetreminder"
    static let chatGPTCodexBundleIdentifier = "com.openai.codex"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var runtimeCoordinator: NotchRuntimeCoordinator?
    private var resetExperience: ResetExperienceCoordinator?
    private var settingsWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--verify-window-restoration") {
            // Scheduling fixtures and an unshown panel; no account data, preferences or network.
            do {
                let count = try NotchPanelRestoration.runSelfChecks()
                let panel = NotchPanel(contentRect: .zero)
                let policies = [
                    panel.collectionBehavior.contains(.canJoinAllApplications),
                    panel.collectionBehavior.contains(.canJoinAllSpaces),
                    panel.collectionBehavior.contains(.fullScreenAuxiliary),
                    !panel.collectionBehavior.contains(.fullScreenNone),
                    panel.level == .popUpMenu,
                    !panel.hidesOnDeactivate,
                    !panel.canBecomeKey && !panel.canBecomeMain,
                    !panel.isVisible
                ]
                guard policies.allSatisfy({ $0 }) else {
                    print("Window restoration self-check failed: panel participation or focus policy")
                    exit(1)
                }
                print("Window restoration self-checks passed: \(count + policies.count)")
                exit(0)
            } catch {
                print("Window restoration self-check failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--verify-reset-behavior") {
            Task {
                do {
                    let count = try await ResetSelfCheck.run()
                    print("Reset behavior self-checks passed: \(count)")
                    exit(0)
                } catch {
                    print("Reset behavior self-check failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
            return
        }
        if CommandLine.arguments.contains("--verify-reset-source") {
            // Public connectivity only: no credentials, notifications, login items or saved state.
            Task {
                do {
                    let snapshot = try await NextResetClient().fetch()
                    let date = snapshot.sourceCheckedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
                    print("Public source verified: records=\(snapshot.announcements.count), fresh=\(snapshot.sourceIsFresh), sourceCheckedAt=\(date)")
                    exit(0)
                } catch {
                    print("Public source check failed: \(error.localizedDescription)")
                    exit(1)
                }
            }
            return
        }
        if CommandLine.arguments.contains("--verify-bundled-resources") {
            // Exit before reading credentials or starting session monitoring.
            let valid = SwordWandererAsset.pixelSize == CGSize(width: 1_536, height: 2_288)
                && SwordWandererAsset.swordImage != nil
                && SwordWandererAsset.slimeImage != nil
                && SwordWandererAsset.hitSparkImage != nil
            print(valid ? "Bundled resources verified" : "Bundled resources missing or invalid")
            exit(valid ? 0 : 1)
        }
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            AppLanguage.storageKey: AppLanguage.chinese.rawValue,
            RecentConversationLimit.storageKey: 0,
            ResetReminderPreferences.launchAtLoginKey: true
        ])
        observeSettingsWindowActivation()
        runtimeCoordinator = NotchRuntimeCoordinator()
        runtimeCoordinator?.start()
        let experience = ResetExperienceCoordinator()
        resetExperience = experience
        experience.onStatusChange = { [weak self] unread, away, status, announcements, records in
            self?.runtimeCoordinator?.updateResetAnnouncements(
                unread: unread, awayUnread: away, status: status, announcements: announcements, records: records
            )
        }
        runtimeCoordinator?.onOpenResetAnnouncements = { [weak experience] in
            experience?.showAnnouncements()
        }
        experience.onShowSummary = { [weak self] in
            self?.runtimeCoordinator?.showResetSummary()
        }
        experience.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        resetExperience?.stop()
        runtimeCoordinator?.stop()
        stopObservingSettingsWindowActivation()
    }

    deinit {
        stopObservingSettingsWindowActivation()
    }

    private func observeSettingsWindowActivation() {
        settingsWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow,
                  SettingsWindowPresenter.isSettingsWindow(window) else {
                return
            }
            SettingsWindowPresenter.bringToFront(window)
        }
    }

    private func stopObservingSettingsWindowActivation() {
        if let settingsWindowObserver {
            NotificationCenter.default.removeObserver(settingsWindowObserver)
        }
        settingsWindowObserver = nil
    }
}
