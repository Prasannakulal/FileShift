import AppKit
import SwiftUI

/// Observable ViewModel for the interactive Image Compression HUD.
/// Powers the dynamic drag-to-resize control, showing current size and live target size.
class CompressionHUDViewModel: ObservableObject {
    let sourceURL: URL
    let originalBytes: Int64
    let originalDimensions: CGSize
    let thumbnailImage: NSImage?

    @Published var quality: Double = 0.60 {
        didSet {
            if quality < 0.45 {
                scaleFactor = max(0.40, (quality / 0.45) * 0.8)
            } else {
                scaleFactor = 1.0
            }
            recalculateEstimatedSize()
        }
    }

    @Published var scaleFactor: Double = 1.0

    @Published var estimatedBytes: Int64 = 0
    @Published var savingsPercent: Int = 0

    init(sourceURL: URL) {
        self.sourceURL = sourceURL

        // Read original file size
        let attr = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        self.originalBytes = (attr?[.size] as? Int64) ?? 0

        // Read thumbnail and image dimensions
        if let image = NSImage(contentsOf: sourceURL) {
            self.thumbnailImage = image
            if let rep = image.representations.first {
                self.originalDimensions = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            } else {
                self.originalDimensions = image.size
            }
        } else {
            self.thumbnailImage = nil
            self.originalDimensions = .zero
        }

        recalculateEstimatedSize()
    }

    var formattedOriginalSize: String {
        ByteCountFormatter.string(fromByteCount: originalBytes, countStyle: .file)
    }

    var formattedEstimatedSize: String {
        ByteCountFormatter.string(fromByteCount: max(1024, estimatedBytes), countStyle: .file)
    }

    var formattedDimensions: String {
        let w = Int(originalDimensions.width * CGFloat(scaleFactor))
        let h = Int(originalDimensions.height * CGFloat(scaleFactor))
        if w > 0 && h > 0 {
            return "\(w) × \(h) px"
        }
        return ""
    }

    var qualityLabel: String {
        if quality < 0.35 {
            return "Web Compact"
        } else if quality < 0.65 {
            return "Balanced"
        } else if quality < 0.85 {
            return "High Quality"
        } else {
            return "Maximum Quality"
        }
    }

    private func recalculateEstimatedSize() {
        guard originalBytes > 0 else {
            estimatedBytes = 0
            savingsPercent = 0
            return
        }

        let ext = sourceURL.pathExtension.lowercased()
        let isLossless = (ext == "png" || ext == "tiff" || ext == "bmp")

        // Realistic compression curve:
        // JPEG/WebP/HEIC scale non-linearly with quality; PNG scales primarily with resolution & quantization
        let ratio: Double
        if isLossless {
            // PNG scaling approximation
            let dimScale = scaleFactor * (quality < 0.85 ? (0.4 + quality * 0.6) : 1.0)
            ratio = min(1.0, max(0.08, pow(dimScale, 1.7) * (0.5 + quality * 0.5)))
        } else {
            // Lossy formats (JPEG, HEIC, WebP)
            let qCurve = pow(quality, 1.35)
            let dimCurve = pow(scaleFactor, 1.8)
            ratio = min(1.0, max(0.05, (0.10 + qCurve * 0.85) * dimCurve))
        }

        let est = Int64(Double(originalBytes) * ratio)
        self.estimatedBytes = est
        self.savingsPercent = max(0, min(95, Int((1.0 - (Double(est) / Double(originalBytes))) * 100)))
    }

    func applyPreset(quality: Double, scale: Double = 1.0) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            self.scaleFactor = scale
            self.quality = quality
        }
    }
}

/// The interactive SwiftUI view for image compression with live drag sizing
struct CompressionHUDView: View {
    @ObservedObject var viewModel: CompressionHUDViewModel
    let onConfirm: (Double, Double) -> Void
    let onCancel: () -> Void

    @State private var isDragging: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            // MARK: - Header
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "E85D26"), Color(hex: "FF8C42")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Compress Image")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // MARK: - File & Size Card
            HStack(spacing: 14) {
                // Thumbnail
                if let thumb = viewModel.thumbnailImage {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        )
                }

                // File name & original size
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.sourceURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(viewModel.formattedDimensions)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text("Current Size:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(viewModel.formattedOriginalSize)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            )

            // MARK: - Live Target Size Card (Hero Readout)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Size")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(viewModel.formattedEstimatedSize)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "E85D26"), Color(hex: "FF8C42")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        if viewModel.savingsPercent > 0 {
                            Text("-\(viewModel.savingsPercent)%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18))
                                .foregroundStyle(Color.green)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                // Quality pill
                VStack(alignment: .trailing, spacing: 2) {
                    Text(viewModel.qualityLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "E85D26"))

                    Text("Quality: \(Int(viewModel.quality * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "E85D26").opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: "E85D26").opacity(0.25), lineWidth: 0.8)
                    )
            )

            // MARK: - Interactive Drag Slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Drag to adjust required size:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(isDragging ? "Dragging..." : "Drag slider")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isDragging ? Color(hex: "E85D26") : Color.secondary.opacity(0.7))
                }

                // Custom Slider with gradient track
                GeometryReader { geo in
                    let trackWidth = geo.size.width
                    let thumbX = CGFloat(viewModel.quality) * trackWidth

                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        // Filled active track
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "FF8C42"), Color(hex: "E85D26")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, min(trackWidth, thumbX)), height: 8)

                        // Draggable Thumb Handle
                        Circle()
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(hex: "E85D26"), lineWidth: 3)
                            )
                            .offset(x: max(0, min(trackWidth - 20, thumbX - 10)))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        let newPercent = Double(value.location.x / trackWidth)
                                        viewModel.quality = min(0.95, max(0.10, newPercent))
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                    }
                            )
                    }
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let newPercent = Double(value.location.x / trackWidth)
                                viewModel.quality = min(0.95, max(0.10, newPercent))
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
                }
                .frame(height: 20)

                // Track end labels
                HStack {
                    Text("◀ Max Compression (Smallest)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(hex: "E85D26"))
                    Spacer()
                    Text("Min Compression (Original) ▶")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Preset Pills
            HStack(spacing: 8) {
                PresetButton(title: "Extreme 25%", isSelected: viewModel.quality <= 0.3) {
                    viewModel.applyPreset(quality: 0.25, scale: 0.65)
                }
                PresetButton(title: "Balanced 50%", isSelected: viewModel.quality > 0.3 && viewModel.quality <= 0.6) {
                    viewModel.applyPreset(quality: 0.50, scale: 0.85)
                }
                PresetButton(title: "High 75%", isSelected: viewModel.quality > 0.6 && viewModel.quality <= 0.82) {
                    viewModel.applyPreset(quality: 0.75, scale: 1.0)
                }
                PresetButton(title: "Original 95%", isSelected: viewModel.quality > 0.82) {
                    viewModel.applyPreset(quality: 0.95, scale: 1.0)
                }
            }

            // MARK: - Action Buttons
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    onConfirm(viewModel.quality, viewModel.scaleFactor)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Compress to \(viewModel.formattedEstimatedSize)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "E85D26"), Color(hex: "FF8C42")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color(hex: "E85D26").opacity(0.35), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 30, x: 0, y: 12)
    }
}

/// Quick preset selection pill button
struct PresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected
                    ? AnyShapeStyle(Color(hex: "E85D26"))
                    : AnyShapeStyle(Color.white.opacity(0.08))
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            isSelected ? Color(hex: "E85D26") : Color.white.opacity(0.12),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

/// Floating panel controller for the compression sizing modal
@MainActor
class CompressionHUDController {
    private var panel: NSPanel?

    func show(
        for sourceURL: URL,
        at screenLocation: NSPoint,
        onConfirm: @escaping (Double, Double) -> Void
    ) {
        dismiss()

        let viewModel = CompressionHUDViewModel(sourceURL: sourceURL)

        let hudView = CompressionHUDView(
            viewModel: viewModel,
            onConfirm: { [weak self] quality, scale in
                self?.dismiss()
                onConfirm(quality, scale)
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 340

        // Center on screen or near cursor, keeping fully within screen bounds
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        var x = screenLocation.x - (panelWidth / 2)
        var y = screenLocation.y - (panelHeight / 2)

        x = max(screenFrame.minX + 20, min(screenFrame.maxX - panelWidth - 20, x))
        y = max(screenFrame.minY + 20, min(screenFrame.maxY - panelHeight - 20, y))

        let newPanel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false
        newPanel.ignoresMouseEvents = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: hudView)
        host.frame = NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))
        newPanel.contentView = host

        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            newPanel.animator().alphaValue = 1.0
        }

        self.panel = newPanel
    }

    func dismiss() {
        guard let p = panel else { return }
        self.panel = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 0.0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }
}
