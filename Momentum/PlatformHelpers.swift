import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Small cross-platform shims so shared views compile unchanged on iOS and macOS.
enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Opens the system's notification settings for this app (iOS Settings / macOS System Settings).
    @MainActor
    static func openNotificationSettings() {
        #if WIDGET_EXTENSION
        // App extensions can't open URLs or other apps; settings are only offered in the app.
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

extension View {
    /// Inline navigation title on iOS; no-op on macOS (no navigation bar).
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Inset-grouped list on iOS, inset list on macOS.
    @ViewBuilder
    func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// Gives sheets a sensible size on macOS, where they otherwise shrink to fit their content.
    @ViewBuilder
    func macSheetFrame(width: CGFloat = 480, height: CGFloat = 600) -> some View {
        #if os(macOS)
        self.frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }

    /// Runs `action` while the pointer hovers on macOS; a no-op on iOS.
    @ViewBuilder
    func macHover(_ action: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        self.onHover(perform: action)
        #else
        self
        #endif
    }
}
