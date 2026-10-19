import AppKit
import SwiftUI

/// A floating toast notification that shows conversion progress.
/// Matches the glassmorphic design from the screenshots:
/// rounded rect, frosted glass, progress bar, "Converting to X", "N of N saved".
class ProgressToastController {

    // MARK: - Properties

    private var toastPanel: NSPanel?
    private var viewModel = ProgressToastViewModel()

    // MARK: - Public Methods

    /// Show the progress toast
    func show(message: String, total: Int) {
        dismiss()

        viewModel.message = message
        viewModel.totalCount = total
        viewModel.completedCount = 0
        viewModel.progress = 0.0
        viewModel.state = .converting

        let toastView = ProgressToastView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.dismiss()
        })

        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 80

        // Position at bottom-right of main screen
        guard let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - panelWidth - 20,
            y: screen.visibleFrame.minY + 20
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: toastView)
        hostingView.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))
        panel.contentView = hostingView

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 1.0
        }

        self.toastPanel = panel
    }

    /// Update conversion progress
    func updateProgress(completed: Int, total: Int) {
        viewModel.completedCount = completed
        viewModel.totalCount = total
        viewModel.progress = total > 0 ? Double(completed) / Double(total) : 0
    }

    /// Show success state
    func showSuccess(savedCount: Int) {
        viewModel.state = .completed
        viewModel.message = "\(savedCount) of \(viewModel.totalCount) saved"
        viewModel.progress = 1.0
    }

    /// Show custom success message
    func showSuccess(message: String) {
        viewModel.state = .completed
        viewModel.message = message
        viewModel.progress = 1.0
    }

    /// Show error state
    func showError(message: String) {
        viewModel.state = .error
        viewModel.message = message
    }

    /// Dismiss the toast
    func dismiss() {
        guard let panel = toastPanel else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.toastPanel = nil
        })
    }
}

// MARK: - View Model

class ProgressToastViewModel: ObservableObject {
    @Published var message: String = ""
    @Published var progress: Double = 0.0
    @Published var completedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var state: ToastState = .converting

    enum ToastState {
        case converting
        case completed
        case error
    }
}

// MARK: - SwiftUI View

struct ProgressToastView: View {
    @ObservedObject var viewModel: ProgressToastViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)

                // Message
                Text(viewModel.message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                // Status icon
                statusIcon
            }

            // Progress details
            HStack {
                Text("\(viewModel.completedCount) of \(viewModel.totalCount) saved")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * viewModel.progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.state {
        case .converting:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        }
    }

    private var progressColor: LinearGradient {
        switch viewModel.state {
        case .converting:
            return LinearGradient(
                colors: [Color(hex: "E85D26"), Color(hex: "FF8C42")],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .completed:
            return LinearGradient(
                colors: [.green, .green],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .error:
            return LinearGradient(
                colors: [.red, .red],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}
