import SwiftUI
import AppKit

// MARK: - App Entry Point
// FileShift is a menu-bar-only app (LSUIElement = true).
// It monitors system-wide drag events and shows a radial conversion menu.

@main
struct FileShiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We use Settings as a placeholder scene.
        // The actual UI is managed via NSPanel overlays.
        Settings {
            SettingsView()
        }
    }
}
