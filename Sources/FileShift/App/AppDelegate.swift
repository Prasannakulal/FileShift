import AppKit
import SwiftUI
import Combine

/// AppDelegate manages the menu bar status item, global event monitoring,
/// and coordinates the overlay window for the radial menu.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private var globalEventMonitor: GlobalEventMonitor!
    private var overlayController: OverlayWindowController!
    private var dragSessionManager: DragSessionManager!
    private let compressionHUDController = CompressionHUDController()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--test") {
            runSelfTests()
            return
        }
        if CommandLine.arguments.contains("--snapshot") {
            generateSnapshot()
            return
        }

        setupStatusItem()
        setupDragSessionManager()
        setupOverlayController()
        checkAccessibilityOnLaunch()
    }

    private func checkAccessibilityOnLaunch() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        if isTrusted {
            setupGlobalEventMonitor()
            print("✅ FileShift is running with Accessibility enabled.")
        } else {
            print("⚠️ Accessibility permissions not yet granted. Prompting user...")
            AccessibilityOnboardingController.shared.show { [weak self] in
                self?.setupGlobalEventMonitor()
                self?.updateStatusMenu()
                let toast = ProgressToastController()
                toast.showSuccess(message: "FileShift ready! Hold ⇧ Shift while dragging.")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalEventMonitor?.stopMonitoring()
    }

    // MARK: - Status Bar Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateStatusMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusMenu()
    }

    private func updateStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let isPaused = AppSettings.shared.isPaused

        // Update status icon
        if let button = statusItem.button {
            let symbolName = isPaused ? "pause.circle" : "arrow.triangle.2.circlepath"
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "FileShift")?.withSymbolConfiguration(config)
            button.alphaValue = isPaused ? 0.6 : 1.0
            button.toolTip = isPaused ? "FileShift (Paused)" : "FileShift — Drag + Shift to convert"
        }

        // Header
        let titleItem = NSMenuItem(title: "FileShift", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        // Status description
        let subtitleText: String
        if isPaused {
            if AppSettings.shared.pauseUntilTimestamp > Date().timeIntervalSince1970 {
                let remainingMin = max(1, Int((AppSettings.shared.pauseUntilTimestamp - Date().timeIntervalSince1970) / 60))
                subtitleText = "Paused (Resumes in \(remainingMin)m)"
            } else {
                subtitleText = "FileShift is Disabled"
            }
        } else {
            subtitleText = "Hold ⇧ Shift while dragging a file"
        }
        let subtitleItem = NSMenuItem(title: subtitleText, action: nil, keyEquivalent: "")
        subtitleItem.isEnabled = false
        menu.addItem(subtitleItem)

        // Show Accessibility permission alert if not granted
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            menu.addItem(NSMenuItem.separator())
            let warningItem = NSMenuItem(title: "⚠️ Accessibility Permission Required…", action: #selector(openAccessibilityOnboarding), keyEquivalent: "")
            warningItem.target = self
            menu.addItem(warningItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Master toggle / pause controls
        if isPaused {
            let enableItem = NSMenuItem(title: "Enable FileShift", action: #selector(toggleEnable), keyEquivalent: "e")
            enableItem.target = self
            menu.addItem(enableItem)
        } else {
            let enabledCheckItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnable), keyEquivalent: "")
            enabledCheckItem.state = .on
            enabledCheckItem.target = self
            menu.addItem(enabledCheckItem)

            // Pause submenu
            let pauseMenu = NSMenu()
            let pause30 = NSMenuItem(title: "Pause for 30 Minutes", action: #selector(pause30Min), keyEquivalent: "")
            pause30.target = self
            let pause1Hour = NSMenuItem(title: "Pause for 1 Hour", action: #selector(pause1Hour), keyEquivalent: "")
            pause1Hour.target = self
            let pauseToday = NSMenuItem(title: "Pause for Rest of Day", action: #selector(pauseTodayAction), keyEquivalent: "")
            pauseToday.target = self
            let disableItem = NSMenuItem(title: "Disable Completely", action: #selector(disableCompletely), keyEquivalent: "")
            disableItem.target = self

            pauseMenu.addItem(pause30)
            pauseMenu.addItem(pause1Hour)
            pauseMenu.addItem(pauseToday)
            pauseMenu.addItem(NSMenuItem.separator())
            pauseMenu.addItem(disableItem)

            let pauseSubmenuItem = NSMenuItem(title: "Pause FileShift", action: nil, keyEquivalent: "")
            pauseSubmenuItem.submenu = pauseMenu
            menu.addItem(pauseSubmenuItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        let aboutItem = NSMenuItem(title: "About FileShift", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self

        let quitItem = NSMenuItem(title: "Quit FileShift", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(settingsItem)
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
    }

    @objc private func toggleEnable() {
        if AppSettings.shared.isPaused {
            AppSettings.shared.resume()
        } else {
            AppSettings.shared.pause()
        }
        updateStatusMenu()
    }

    @objc private func pause30Min() {
        AppSettings.shared.pause(duration: 30 * 60)
        updateStatusMenu()
    }

    @objc private func pause1Hour() {
        AppSettings.shared.pause(duration: 60 * 60)
        updateStatusMenu()
    }

    @objc private func pauseTodayAction() {
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) {
            let duration = tomorrow.timeIntervalSince(Date())
            AppSettings.shared.pause(duration: duration)
        } else {
            AppSettings.shared.pause(duration: 8 * 3600)
        }
        updateStatusMenu()
    }

    @objc private func disableCompletely() {
        AppSettings.shared.pause(duration: nil)
        updateStatusMenu()
    }

    @objc private func openAccessibilityOnboarding() {
        AccessibilityOnboardingController.shared.show { [weak self] in
            self?.setupGlobalEventMonitor()
            self?.updateStatusMenu()
            let toast = ProgressToastController()
            toast.showSuccess(message: "FileShift ready! Hold ⇧ Shift while dragging.")
        }
    }

    // MARK: - Core Setup

    private func setupDragSessionManager() {
        dragSessionManager = DragSessionManager()
    }

    private func setupOverlayController() {
        overlayController = OverlayWindowController()
    }

    private func setupGlobalEventMonitor() {
        guard globalEventMonitor == nil else { return }
        globalEventMonitor = GlobalEventMonitor(
            dragSessionManager: dragSessionManager,
            onDragWithShift: { [weak self] fileURLs, mouseLocation in
                DispatchQueue.main.async {
                    self?.handleDragWithShift(fileURLs: fileURLs, at: mouseLocation)
                }
            },
            onDragMove: { [weak self] mouseLocation in
                DispatchQueue.main.async {
                    self?.overlayController.updateMouseLocation(screenPoint: mouseLocation)
                }
            },
            onDragDrop: { [weak self] dropLocation in
                DispatchQueue.main.async {
                    self?.overlayController.handleDrop(at: dropLocation)
                }
            },
            onDragEnd: { [weak self] in
                DispatchQueue.main.async {
                    self?.overlayController.dismiss()
                }
            }
        )
        globalEventMonitor.startMonitoring()
    }

    // MARK: - Drag Handling

    @MainActor
    private func handleDragWithShift(fileURLs: [URL], at location: NSPoint) {
        guard let firstFile = fileURLs.first else { return }

        let fileType = FileTypeDetector.detectType(for: firstFile)
        let menuConfig = MenuConfigProvider.config(for: fileType)

        overlayController.show(
            at: location,
            config: menuConfig,
            sourceFile: firstFile,
            onFormatSelected: { [weak self] segment in
                self?.handleConversion(
                    sourceFile: firstFile,
                    segment: segment
                )
            }
        )
    }

    private func handleDragEnd() {
        // Overlay handles its own dismiss on drop
    }

    @MainActor
    private func handleConversion(sourceFile: URL, segment: MenuSegment) {
        overlayController.dismiss()

        if segment.targetFormat.lowercased() == "compress" {
            // Present interactive Compression Sizing HUD with live size drag option
            compressionHUDController.show(
                for: sourceFile,
                at: NSEvent.mouseLocation
            ) { [weak self] quality, scale in
                self?.executeCompression(sourceFile: sourceFile, quality: quality, scale: scale)
            }
            return
        }

        let toast = ProgressToastController()
        toast.show(message: "Converting to \(segment.label)", total: 1)

        Task {
            do {
                let outputURL = try await ConversionEngine.shared.convert(
                    source: sourceFile,
                    to: segment.targetFormat,
                    outputDir: sourceFile.deletingLastPathComponent()
                )
                await MainActor.run {
                    toast.updateProgress(completed: 1, total: 1)
                    toast.showSuccess(savedCount: 1)

                    // Reveal in Finder
                    NSWorkspace.shared.noteFileSystemChanged(outputURL.deletingLastPathComponent().path)
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        toast.dismiss()
                    }
                }
                print("✅ Converted: \(outputURL.lastPathComponent)")
            } catch {
                await MainActor.run {
                    toast.showError(message: error.localizedDescription)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        toast.dismiss()
                    }
                }
                print("❌ Conversion failed: \(error)")
            }
        }
    }

    @MainActor
    private func executeCompression(sourceFile: URL, quality: Double, scale: Double) {
        let toast = ProgressToastController()
        toast.show(message: "Compressing \(sourceFile.lastPathComponent)...", total: 1)

        Task {
            do {
                let (outputURL, newSize, savings) = try await ConversionEngine.shared.compressImage(
                    source: sourceFile,
                    quality: quality,
                    scale: scale,
                    outputDir: sourceFile.deletingLastPathComponent()
                )
                await MainActor.run {
                    toast.updateProgress(completed: 1, total: 1)
                    let formatted = ByteCountFormatter.string(fromByteCount: newSize, countStyle: .file)
                    let savingsText = savings > 0 ? " (-\(Int(savings * 100))%)" : ""
                    toast.showSuccess(message: "Saved: \(outputURL.lastPathComponent) (\(formatted)\(savingsText))")

                    // Notify Finder and reveal the new file immediately!
                    NSWorkspace.shared.noteFileSystemChanged(outputURL.deletingLastPathComponent().path)
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        toast.dismiss()
                    }
                }
                print("✅ Compressed: \(outputURL.lastPathComponent)")
            } catch {
                await MainActor.run {
                    toast.showError(message: error.localizedDescription)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        toast.dismiss()
                    }
                }
                print("❌ Compression failed: \(error)")
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Self Test

    private func runSelfTests() {
        print("🧪 Running FileShift Conversion Engine Self-Tests...")
        let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // 1. Create temporary test image
        let imgSize = CGSize(width: 200, height: 200)
        let img = NSImage(size: imgSize)
        img.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(origin: .zero, size: imgSize).fill()
        img.unlockFocus()

        let testImageURL = outputDir.appendingPathComponent("selftest_input.png")
        if let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: testImageURL)
        }

        // 2. Create temporary test text document
        let testDocURL = outputDir.appendingPathComponent("selftest_input.txt")
        let sampleDoc = "FileShift Document\nFormat,Status\nDOCX,Supported\nXLSX,Supported\nPPTX,Supported"
        try? sampleDoc.write(to: testDocURL, atomically: true, encoding: .utf8)

        let imageFormats = ["jpg", "png", "webp", "heic", "avif", "svg", "compress"]
        let documentFormats = ["docx", "pdf", "xlsx", "csv", "pptx", "txt", "md"]

        Task {
            var successCount = 0

            print("\n📸 Testing Image Formats & Actions (7):")
            for format in imageFormats {
                do {
                    let out = try await ConversionEngine.shared.convert(source: testImageURL, to: format, outputDir: outputDir)
                    print("  ✅ Converted/Processed → \(format.uppercased()): \(out.lastPathComponent)")
                    successCount += 1
                } catch {
                    print("  ❌ Failed → \(format.uppercased()): \(error)")
                }
            }

            print("\n📄 Testing Document Formats (7):")
            for format in documentFormats {
                do {
                    let out = try await ConversionEngine.shared.convert(source: testDocURL, to: format, outputDir: outputDir)
                    print("  ✅ Converted → \(format.uppercased()): \(out.lastPathComponent)")
                    successCount += 1
                } catch {
                    print("  ❌ Failed → \(format.uppercased()): \(error)")
                }
            }

            // Cleanup
            try? FileManager.default.removeItem(at: testImageURL)
            try? FileManager.default.removeItem(at: testDocURL)
            let files = (try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.lastPathComponent.hasPrefix("selftest_input") && f.lastPathComponent != "selftest_input.txt" && f.lastPathComponent != "selftest_input.png" {
                try? FileManager.default.removeItem(at: f)
            }

            print("\n🎉 Self-Tests Complete: \(successCount)/14 operations passed!")
            exit(0)
        }
    }

    private func generateSnapshot() {
        let config = MenuConfigProvider.config(for: .pdf)
        let state = RadialMenuState(totalSegments: config.segmentCount, innerRadius: 46, outerRadius: 110)
        let view = RadialMenuView(
            config: config,
            state: state,
            fileSizeString: "1.1 MB",
            onSegmentSelected: { _ in },
            onDismiss: {}
        )
        .frame(width: 280, height: 280)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 280)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
                hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: "dial_preview.png"))
                    print("📸 Dial preview saved to dial_preview.png")
                }
            }
            exit(0)
        }
    }
}
