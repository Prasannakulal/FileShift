import Foundation
import SwiftUI

/// User preferences and app settings
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Whether FileShift is enabled or disabled
    @AppStorage("isEnabled") var isEnabled: Bool = true

    /// Timestamp until which FileShift is paused (0 if not paused by timer)
    @AppStorage("pauseUntilTimestamp") var pauseUntilTimestamp: Double = 0

    /// Returns true if FileShift is currently paused or disabled
    var isPaused: Bool {
        if !isEnabled { return true }
        if pauseUntilTimestamp > Date().timeIntervalSince1970 { return true }
        return false
    }

    /// Resume / Enable FileShift
    func resume() {
        isEnabled = true
        pauseUntilTimestamp = 0
    }

    /// Pause FileShift indefinitely or for a specific duration
    func pause(duration: TimeInterval? = nil) {
        if let duration = duration {
            isEnabled = true
            pauseUntilTimestamp = Date().timeIntervalSince1970 + duration
        } else {
            isEnabled = false
            pauseUntilTimestamp = 0
        }
    }

    /// Where to save converted files
    @AppStorage("outputLocation") var outputLocation: OutputLocation = .sameFolder

    /// Whether to launch at login
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    /// Image conversion quality (0.0 - 1.0)
    @AppStorage("imageQuality") var imageQuality: Double = 0.85

    /// File naming strategy for converted files
    @AppStorage("namingStrategy") var namingStrategy: NamingStrategy = .suffix

    /// Whether to show the progress toast
    @AppStorage("showProgressToast") var showProgressToast: Bool = true

    /// The modifier key that triggers the radial menu (default: Shift)
    @AppStorage("triggerModifier") var triggerModifier: TriggerModifier = .shift

    enum OutputLocation: String, CaseIterable {
        case sameFolder = "Same Folder"
        case desktop = "Desktop"
        case downloads = "Downloads"
        case custom = "Custom…"
    }

    enum NamingStrategy: String, CaseIterable {
        case suffix = "Add Suffix (file_converted.jpg)"
        case replace = "Replace Extension (file.jpg)"
        case increment = "Increment (file_1.jpg)"
    }

    enum TriggerModifier: String, CaseIterable {
        case shift = "⇧ Shift"
        case control = "⌃ Control"
        case option = "⌥ Option"
    }
}
