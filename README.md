# FileShift 🚀

> **Mac native drag-and-drop file converter with a circular radial HUD menu.**
> Reverse-engineered from ReConvert / Rea macOS concepts.

Hold **⇧ Shift** while dragging any file in Finder or your Desktop, and a sleek circular pie menu appears around your cursor. Hover over your desired target format or action (JPEG, PNG, WebP, HEIC, PDF, DOCX, TXT, etc.) and drop to instantly convert!

---

## ✨ Features

- 🎯 **Radial Pie Menu HUD**: Glassmorphic circular HUD that matches the macOS aesthetic with dynamic animations, glow states, and center selection readout.
- ⚡ **Instant Drag-and-Drop Trigger**: Activates seamlessly when holding `Shift` while dragging files from Finder.
- 🔄 **Comprehensive Format Engine (13 Formats)**:
  - **Images (6 formats)**: JPG / JPEG, PNG, HEIC, WebP, AVIF, SVG (plus PDF & TIFF)
  - **Documents (7 formats)**: DOCX (Word), PDF, XLSX (Excel), CSV, PPTX (PowerPoint), TXT (Plain text), MD (Markdown)
- 🍞 **Glassmorphic Progress Toast**: Floating frosted-glass toast with progress bar, animated status messages, and automatic Finder reveal.
- ⚙️ **Customizable Settings**: Trigger key customization (Shift, Option, Control, Command), naming rules (suffix, increment, overwrite), and output destination.
- 🛡️ **100% Native & Private**: Built entirely in Swift with AppKit, SwiftUI, ImageIO, CoreImage, and PDFKit. Zero cloud dependencies, zero analytics.

---

## 🏗️ Architecture

```
FileShift/
├── Package.swift                     # Swift Package Manager manifest
├── Info.plist                        # macOS app metadata (LSUIElement = true)
├── build.sh                          # App bundle packager script
└── Sources/FileShift/
    ├── App/
    │   ├── FileShiftApp.swift        # App entry point
    │   └── AppDelegate.swift         # Status bar menu, lifecycle & event routing
    ├── Core/
    │   ├── DragSessionManager.swift  # Drag state tracker & file payload parser
    │   ├── FileTypeDetector.swift    # UTI & extension type classifier
    │   ├── GlobalEventMonitor.swift  # NSEvent global monitors & pasteboard listener
    │   └── MenuConfigProvider.swift  # Dynamic radial segments per file type
    ├── Models/
    │   ├── AppSettings.swift         # UserDefaults-backed user configuration
    │   ├── ConversionTask.swift      # Async progress & state tracking
    │   └── MenuSegment.swift         # Radial segment models & format definitions
    ├── Conversion/
    │   ├── ConversionEngine.swift    # Central coordinator & format dispatcher
    │   ├── ImageConverter.swift      # ImageIO & CoreImage native conversions
    │   └── PDFConverter.swift        # PDFKit extraction & conversion logic
    └── UI/
        ├── RadialMenuView.swift      # SwiftUI circular pie menu & animations
        ├── OverlayWindowController.swift # Floating transparent NSPanel host
        ├── ProgressToastView.swift   # Glassmorphic progress notification HUD
        └── SettingsView.swift        # Preferences & configuration UI
```

---

## 🚀 Installation & First Run (Open Source)

### Option A: Install via DMG Installer (Recommended)
1. Download **`FileShift-1.0.0.dmg`** from [Releases](https://github.com/your-username/FileShift/releases).
2. Open the DMG and drag **FileShift** into your **Applications** folder.
3. **First-time launch (bypassing Gatekeeper)**:
   - Because FileShift is free & open-source without an Apple Developer ID, macOS Gatekeeper may show a warning on first run.
   - Simply **Right-click (or Control-click)** on `FileShift.app` in Applications and choose **Open**, then click **Open**.
   - *(Or run this one-liner in Terminal to remove the quarantine flag)*:
     ```bash
     xattr -cr /Applications/FileShift.app
     ```
4. **Grant Accessibility Permission**:
   - On first launch, FileShift will automatically prompt you to grant Accessibility access in **System Settings > Privacy & Security > Accessibility** (required to detect `Shift + Drag`).

---

### Option B: Build from Source
```bash
git clone https://github.com/your-username/FileShift.git
cd FileShift
./build.sh
open .build/FileShift.app
```

---

## 🎯 How to Use

1. Select any file (or multiple files) in Finder or your Desktop.
2. Hold **⇧ Shift** while dragging the file.
3. The compact circular HUD appears around your cursor.
4. Drop on your target format (DOCX, JPG, PNG, TXT, WEBP, etc.) to convert instantly!

---

## 📦 Creating Distributable DMG

To build a fresh release DMG for GitHub Releases:
```bash
./package.sh
```
This generates:
- `dist/FileShift-1.0.0.dmg` (Custom drag-to-Applications installer with background and volume icon)
- `dist/FileShift-1.0.0.zip`

---

## 🧪 Self-Tests
Verify that all native converters pass:
```bash
swift run FileShift --test
```
