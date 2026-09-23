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
        // The visible island and hidden hover sensor both belong above other
        // applications, including their application sets and full-screen Spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .canJoinAllApplications]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
