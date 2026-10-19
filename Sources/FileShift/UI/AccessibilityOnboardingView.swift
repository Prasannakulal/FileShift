import SwiftUI
import AppKit

/// Onboarding dialog that guides users to grant Accessibility permissions.
struct AccessibilityOnboardingView: View {
    let onGranted: () -> Void

    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 20) {
            // App / Permission Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange.opacity(0.85),
                                Color.orange
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: Color.orange.opacity(0.35), radius: 8, x: 0, y: 3)

                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)

            // Title & Description
            VStack(spacing: 8) {
                Text("Accessibility Access Required")
                    .font(.system(size: 17, weight: .bold))

                Text("FileShift needs Accessibility permission to detect when you hold **⇧ Shift** while dragging files in Finder or on your Desktop.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)

            // Step-by-step instructions
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text("1")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Circle())

                    Text("Click **Open System Settings** below.")
                        .font(.system(size: 12))
                }

                HStack(alignment: .top, spacing: 12) {
                    Text("2")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Circle())

                    Text("Find **FileShift** and toggle the switch to **ON**.")
                        .font(.system(size: 12))
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(10)
            .padding(.horizontal, 8)

            Spacer()

            // Action Buttons
            HStack(spacing: 12) {
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)

                Spacer()

                Button("Open System Settings") {
                    openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.regular)

                Button(isChecking ? "Checking…" : "Check Again") {
                    verifyPermission()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 440, height: 380)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            verifyPermissionSilently()
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func verifyPermission() {
        isChecking = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            onGranted()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isChecking = false
            }
        }
    }

    private func verifyPermissionSilently() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            onGranted()
        }
    }
}

/// Controller managing the onboarding window
@MainActor
class AccessibilityOnboardingController {
    static let shared = AccessibilityOnboardingController()

    private var window: NSWindow?

    var isWindowVisible: Bool {
        window != nil
    }

    func show(onGranted: @escaping () -> Void) {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AccessibilityOnboardingView { [weak self] in
            self?.close()
            onGranted()
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "FileShift Setup"
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}
