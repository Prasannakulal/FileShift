import AppKit
import UniformTypeIdentifiers

/// Monitors system-wide events to detect when a user is dragging a file
/// while holding the Shift key. This is the core trigger for FileShift.
class GlobalEventMonitor {

    // MARK: - Properties

    private var flagsMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var mouseUpMonitor: Any?
    private var localMouseUpMonitor: Any?

    private var isShiftHeld = false
    private var isDragActive = false
    private var lastMouseLocation: NSPoint = .zero

    private let dragSessionManager: DragSessionManager
    private let onDragWithShift: ([URL], NSPoint) -> Void
    private let onDragMove: (NSPoint) -> Void
    private let onDragDrop: (NSPoint) -> Void
    private let onDragEnd: () -> Void

    // Polling timer for pasteboard monitoring
    private var pasteboardTimer: Timer?
    private var lastPasteboardChangeCount: Int = 0

    // MARK: - Init

    init(
        dragSessionManager: DragSessionManager,
        onDragWithShift: @escaping ([URL], NSPoint) -> Void,
        onDragMove: @escaping (NSPoint) -> Void,
        onDragDrop: @escaping (NSPoint) -> Void,
        onDragEnd: @escaping () -> Void
    ) {
        self.dragSessionManager = dragSessionManager
        self.onDragWithShift = onDragWithShift
        self.onDragMove = onDragMove
        self.onDragDrop = onDragDrop
        self.onDragEnd = onDragEnd
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public

    func startMonitoring() {
        // Monitor Shift key press/release globally
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Monitor mouse movement globally to track cursor position during drag
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .mouseMoved]) { [weak self] event in
            self?.handleMouseMove(event)
        }

        // Monitor mouse up globally to detect drag drop or release
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }

        // Also monitor local events (within our own windows)
        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
            return event
        }

        // Monitor Escape key globally to instantly cancel and dismiss
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.endDragSession()
            }
        }

        // Start polling the dragging pasteboard for file URLs (high responsiveness)
        startPasteboardPolling()

        print("🔍 Global event monitoring started")
    }

    func stopMonitoring() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = mouseMoveMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMoveMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
        if let monitor = localMouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseUpMonitor = nil
        }
        stopPasteboardPolling()
        print("🔍 Global event monitoring stopped")
    }

    // MARK: - Event Handlers

    private func handleFlagsChanged(_ event: NSEvent) {
        let shiftPressed = event.modifierFlags.contains(.shift)

        if shiftPressed && !isShiftHeld {
            isShiftHeld = true
            checkForActiveDrag()
        } else if !shiftPressed {
            isShiftHeld = false
            if isDragActive {
                endDragSession()
            }
        }
    }

    private func handleMouseMove(_ event: NSEvent) {
        lastMouseLocation = NSEvent.mouseLocation

        // If dragging is active, continuously report mouse location to update hover segment
        if isDragActive {
            // Safety check: if mouse button was released without an event, dismiss immediately!
            if (NSEvent.pressedMouseButtons & 1) == 0 {
                endDragSession()
                return
            }
            onDragMove(lastMouseLocation)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        if isDragActive {
            let dropLocation = NSEvent.mouseLocation
            isDragActive = false
            dragSessionManager.endSession()
            onDragDrop(dropLocation)
        } else {
            onDragEnd()
        }
    }

    // MARK: - Drag Detection

    /// Check the dragging pasteboard for file URLs to detect an active Finder drag
    private func checkForActiveDrag() {
        // Do not trigger if FileShift is disabled or paused
        guard !AppSettings.shared.isPaused else { return }

        // A drag operation requires the left mouse button to be held down!
        guard (NSEvent.pressedMouseButtons & 1) != 0 else {
            return
        }
        guard !isDragActive else { return }

        let pasteboard = NSPasteboard(name: .drag)
        let fileURLs = extractFileURLs(from: pasteboard)

        if !fileURLs.isEmpty {
            isDragActive = true
            dragSessionManager.startSession(files: fileURLs)
            onDragWithShift(fileURLs, lastMouseLocation)
            print("📂 Drag detected with \(fileURLs.count) file(s): \(fileURLs.map { $0.lastPathComponent })")
        }
    }

    private func endDragSession() {
        isDragActive = false
        dragSessionManager.endSession()
        onDragEnd()
    }

    // MARK: - Pasteboard Polling

    private func startPasteboardPolling() {
        lastPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    private func stopPasteboardPolling() {
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
    }

    private func pollPasteboard() {
        // Safety check: if drag was marked active but the mouse button is no longer down, cancel drag immediately!
        if isDragActive && (NSEvent.pressedMouseButtons & 1) == 0 {
            endDragSession()
            return
        }

        // Safety check: if drag was active but Shift is no longer pressed, cancel drag immediately!
        if isDragActive && !NSEvent.modifierFlags.contains(.shift) {
            isShiftHeld = false
            endDragSession()
            return
        }

        let pasteboard = NSPasteboard(name: .drag)
        let currentCount = pasteboard.changeCount

        if currentCount != lastPasteboardChangeCount {
            lastPasteboardChangeCount = currentCount

            if isShiftHeld {
                checkForActiveDrag()
            }
        }
    }

    // MARK: - Helpers

    private func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        var urls: [URL] = []
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                urls.append(url)
            } else if let data = item.data(forType: NSPasteboard.PasteboardType("public.file-url")),
                      let urlString = String(data: data, encoding: .utf8),
                      let url = URL(string: urlString) {
                urls.append(url)
            }
        }

        if urls.isEmpty, let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = filenames.map { URL(fileURLWithPath: $0) }
        }

        return urls
    }
}
