import SwiftUI

/// Settings / Preferences view shown from the menu bar
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ConversionSettingsTab(settings: settings)
                .tabItem {
                    Label("Conversion", systemImage: "arrow.triangle.2.circlepath")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 320)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Enable FileShift drag detection", isOn: $settings.isEnabled)

                Picker("Trigger Key", selection: $settings.triggerModifier) {
                    ForEach(AppSettings.TriggerModifier.allCases, id: \.self) { modifier in
                        Text(modifier.rawValue).tag(modifier)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                Toggle("Show progress toast", isOn: $settings.showProgressToast)
            }

            Section("Output") {
                Picker("Save converted files to", selection: $settings.outputLocation) {
                    ForEach(AppSettings.OutputLocation.allCases, id: \.self) { location in
                        Text(location.rawValue).tag(location)
                    }
                }

                Picker("File naming", selection: $settings.namingStrategy) {
                    ForEach(AppSettings.NamingStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Conversion Settings

struct ConversionSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Image Quality") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("JPEG/HEIC Quality")
                        Spacer()
                        Text("\(Int(settings.imageQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.imageQuality, in: 0.1...1.0, step: 0.05)
                }
            }

            Section("Supported Formats") {
                VStack(alignment: .leading, spacing: 8) {
                    FormatRow(category: "PDF", formats: "DOCX, JPG, PNG, TXT")
                    FormatRow(category: "Images", formats: "PNG, JPG, WEBP, HEIC, AVIF, BMP, TIFF, PDF")
                    FormatRow(category: "Documents", formats: "PDF, TXT, DOCX, HTML")
                    FormatRow(category: "Video", formats: "MP4, MOV, GIF, WEBM")
                    FormatRow(category: "Audio", formats: "MP3, WAV, AAC, FLAC")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct FormatRow: View {
    let category: String
    let formats: String

    var body: some View {
        HStack(alignment: .top) {
            Text(category)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 80, alignment: .leading)
            Text("→ \(formats)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "E85D26"), Color(hex: "FF8C42")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Text("FileShift")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("v1.0.0")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Drag + Shift to convert files instantly.\nNo windows, no chrome — just results.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(40)
    }
}
