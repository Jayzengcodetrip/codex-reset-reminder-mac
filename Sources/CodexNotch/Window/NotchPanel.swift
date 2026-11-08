import AppKit

enum NotchPanelVisibilityPolicy {
    static func shouldUseMenuBarFallback(
        layoutMode: NotchLayoutMode,
        displayIsEnabled: Bool
    ) -> Bool {
        layoutMode == .menuBarFallback
    }

    static func shouldKeepHiddenHoverSensor(
        layoutMode: NotchLayoutMode,
        displayIsEnabled: Bool
    ) -> Bool {
        layoutMode != .menuBarFallback && !displayIsEnabled
    }

    static func shouldRestoreAfterApplicationSwitch(
        panelIsRequested: Bool,
        layoutMode: NotchLayoutMode,
        displayIsEnabled: Bool
    ) -> Bool {
        guard panelIsRequested,
              layoutMode != .menuBarFallback else {
            return false
        }
        // A hidden notch keeps a transparent sensor at the physical notch so
        // the user can hover back in and re-open the card.
        return displayIsEnabled
            || shouldKeepHiddenHoverSensor(
                layoutMode: layoutMode,
                displayIsEnabled: displayIsEnabled
            )
    }
}

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        // Keep the island and hover sensor available in ordinary/full-screen
        // Spaces, but let WindowServer hide both throughout Mission Control.
        // `stationary` deliberately stays visible in that overview and blocks
        // its Space thumbnails. Use the system's transient overview policy
        // without polling or changing the user's display preference.
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .canJoinAllApplications]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
