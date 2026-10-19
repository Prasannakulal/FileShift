import AppKit
import SwiftUI

/// Custom NSHostingView that accepts dragging destinations and notifies
/// the controller to update the hover state and handle drops.
class RadialDragHostView: NSHostingView<AnyView> {

    var onDragLocationUpdate: (() -> Void)?
    var onDragPerformed: (() -> Void)?

    @MainActor required init(rootView: AnyView) {
        super.init(rootView: rootView)
        setupDragging()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDragging()
    }

    private func setupDragging() {
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragLocationUpdate?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragLocationUpdate?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Keep current state or clear if exited
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDragPerformed?()
        return true
    }
}

/// Manages the transparent overlay NSPanel that hosts the radial menu.
/// This panel floats above all other windows and is transparent except
/// for the radial menu itself.
@MainActor
class OverlayWindowController {

    // MARK: - Properties

    private var overlayPanel: NSPanel?
    private var hostingView: RadialDragHostView?
    private var menuState: RadialMenuState?

    private var onFormatSelected: ((MenuSegment) -> Void)?
    private var currentConfig: RadialMenuConfig?
    private var screenCenter: NSPoint = .zero
    private var panelSize: CGFloat = 400

    var isVisible: Bool {
        return overlayPanel != nil
    }

    // MARK: - Public Methods

    /// Show the radial menu overlay at a given screen position
    func show(
        at screenPoint: NSPoint,
        config: RadialMenuConfig,
        sourceFile: URL,
        onFormatSelected: @escaping (MenuSegment) -> Void
    ) {
        self.onFormatSelected = onFormatSelected
        self.currentConfig = config
        self.screenCenter = screenPoint

        // Dismiss any existing overlay first
        dismiss()

        // Calculate panel size and position (compact dial)
        panelSize = 280
        let panelOrigin = NSPoint(
            x: screenPoint.x - panelSize / 2,
            y: screenPoint.y - panelSize / 2
        )

        // Create the panel
        let panel = NSPanel(
            contentRect: NSRect(origin: panelOrigin, size: NSSize(width: panelSize, height: panelSize)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Calculate formatted file size string for center capsule (e.g. "1.1 MB")
        let fileSizeString: String = {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceFile.path),
               let size = attrs[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                formatter.allowedUnits = [.useMB, .useKB, .useBytes]
                return formatter.string(fromByteCount: size)
            }
            return "1.1 MB"
        }()

        // Initialize state (smaller compact radii)
        let state = RadialMenuState(
            totalSegments: config.segmentCount,
            innerRadius: 46,
            outerRadius: 110
        )
        self.menuState = state

        // Create the SwiftUI radial menu view
        let radialMenu = RadialMenuView(
            config: config,
            state: state,
            fileSizeString: fileSizeString,
            onSegmentSelected: { [weak self] segment in
                self?.handleSegmentSelected(segment)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let host = RadialDragHostView(rootView: AnyView(radialMenu))
        host.frame = NSRect(origin: .zero, size: NSSize(width: panelSize, height: panelSize))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear

        host.onDragLocationUpdate = { [weak self] in
            guard let self = self else { return }
            self.updateMouseLocation(screenPoint: NSEvent.mouseLocation)
        }

        host.onDragPerformed = { [weak self] in
            guard let self = self else { return }
            self.handleDrop(at: NSEvent.mouseLocation)
        }

        panel.contentView = host
        panel.orderFrontRegardless()

        self.overlayPanel = panel
        self.hostingView = host

        setupEscapeKeyHandler()

        print("🎯 Radial menu shown at (\(Int(screenPoint.x)), \(Int(screenPoint.y))) with \(config.segmentCount) segments")
    }

    /// Update hover using a global screen coordinate
    func updateMouseLocation(screenPoint: NSPoint) {
        guard overlayPanel != nil, let state = menuState else { return }
        state.updateHoverScreen(mouseScreenPoint: screenPoint, screenCenter: screenCenter)
    }

    /// Handle drop when user releases mouse button
    func handleDrop(at screenPoint: NSPoint) {
        updateMouseLocation(screenPoint: screenPoint)
        handleDropOnCurrentHover()
    }

    private func handleDropOnCurrentHover() {
        guard let state = menuState,
              let idx = state.hoveredIndex,
              let config = currentConfig,
              idx < config.segments.count else {
            dismiss()
            return
        }

        let segment = config.segments[idx]
        handleSegmentSelected(segment)
    }

    /// Dismiss the overlay immediately
    func dismiss() {
        guard let panel = overlayPanel else { return }
        self.overlayPanel = nil
        self.hostingView = nil
        self.menuState = nil

        panel.orderOut(nil)
    }

    // MARK: - Private

    private func handleSegmentSelected(_ segment: MenuSegment) {
        print("✅ Selected segment: \(segment.label)")
        let callback = onFormatSelected
        dismiss()
        callback?(segment)
    }

    private func setupEscapeKeyHandler() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                self?.dismiss()
                return nil
            }
            return event
        }
    }
}
