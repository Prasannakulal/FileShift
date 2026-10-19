import Foundation

/// Data model for a single segment in the radial menu
struct MenuSegment: Identifiable, Equatable {
    let id = UUID()
    let label: String           // Display label (e.g., "DOCX", "COMPRESS")
    let icon: String?           // SF Symbol name (optional)
    let targetFormat: String    // Target format extension or action ID
    let isAction: Bool          // true = action (compress, crop), false = conversion

    static func == (lhs: MenuSegment, rhs: MenuSegment) -> Bool {
        lhs.id == rhs.id
    }
}

/// Configuration for a radial menu — contains all segments to display
struct RadialMenuConfig {
    let segments: [MenuSegment]
    let title: String           // e.g., "Convert PDF" or "Image Actions"

    var segmentCount: Int { segments.count }
}
