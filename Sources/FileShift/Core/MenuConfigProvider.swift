import Foundation

/// Provides the correct radial menu configuration based on the file type
/// being dragged. This is what makes the menu "context-aware".
struct MenuConfigProvider {

    // MARK: - Public

    /// Returns the appropriate menu config for a given file category
    static func config(for category: FileCategory) -> RadialMenuConfig {
        switch category {
        case .pdf:
            return pdfConfig
        case .image:
            return imageConversionConfig
        case .document:
            return documentConfig
        case .video:
            return videoConfig
        case .audio:
            return audioConfig
        case .unknown:
            return documentConfig
        }
    }

    /// Returns the "actions" menu for already-converted image files
    static func actionsConfig() -> RadialMenuConfig {
        return imageActionsConfig
    }

    // MARK: - Configurations

    /// Image file → image format conversions and actions
    /// (COMPRESS, PNG, JPG, WEBP, HEIC, AVIF, SVG, PDF)
    private static let imageConversionConfig = RadialMenuConfig(
        segments: [
            MenuSegment(label: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", targetFormat: "compress", isAction: true),
            MenuSegment(label: "PNG", icon: "photo.artframe", targetFormat: "png", isAction: false),
            MenuSegment(label: "JPG", icon: "photo", targetFormat: "jpg", isAction: false),
            MenuSegment(label: "WEBP", icon: "globe", targetFormat: "webp", isAction: false),
            MenuSegment(label: "HEIC", icon: "photo.stack", targetFormat: "heic", isAction: false),
            MenuSegment(label: "AVIF", icon: "photo.badge.checkmark", targetFormat: "avif", isAction: false),
            MenuSegment(label: "SVG", icon: "paintbrush.pointed", targetFormat: "svg", isAction: false),
            MenuSegment(label: "PDF", icon: "doc.text.fill", targetFormat: "pdf", isAction: false),
        ],
        title: "Convert Image"
    )

    /// Document file → 7 document format conversions requested by user
    /// (DOCX, PDF, XLSX, CSV, PPTX, TXT, MD)
    private static let documentConfig = RadialMenuConfig(
        segments: [
            MenuSegment(label: "DOCX", icon: "doc.richtext", targetFormat: "docx", isAction: false),
            MenuSegment(label: "PDF", icon: "doc.text.fill", targetFormat: "pdf", isAction: false),
            MenuSegment(label: "XLSX", icon: "chart.bar.doc.horizontal", targetFormat: "xlsx", isAction: false),
            MenuSegment(label: "CSV", icon: "tablecells", targetFormat: "csv", isAction: false),
            MenuSegment(label: "PPTX", icon: "person.crop.rectangle.stack", targetFormat: "pptx", isAction: false),
            MenuSegment(label: "TXT", icon: "doc.plaintext", targetFormat: "txt", isAction: false),
            MenuSegment(label: "MD", icon: "text.quote", targetFormat: "md", isAction: false),
        ],
        title: "Convert Document"
    )

    /// PDF file → conversion formats (DOCX, JPG, PNG, TXT as in reference UI)
    private static let pdfConfig = RadialMenuConfig(
        segments: [
            MenuSegment(label: "DOCX", icon: "doc.richtext", targetFormat: "docx", isAction: false),
            MenuSegment(label: "JPG", icon: "photo", targetFormat: "jpg", isAction: false),
            MenuSegment(label: "PNG", icon: "photo.artframe", targetFormat: "png", isAction: false),
            MenuSegment(label: "TXT", icon: "doc.plaintext", targetFormat: "txt", isAction: false),
        ],
        title: "Convert PDF"
    )

    /// Image file → edit actions (7 segments, as seen in screenshot 5)
    private static let imageActionsConfig = RadialMenuConfig(
        segments: [
            MenuSegment(label: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", targetFormat: "compress", isAction: true),
            MenuSegment(label: "METADATA", icon: "tag", targetFormat: "metadata", isAction: true),
            MenuSegment(label: "EDIT", icon: "slider.horizontal.3", targetFormat: "edit", isAction: true),
            MenuSegment(label: "ANNOTATE", icon: "pencil.tip.crop.circle", targetFormat: "annotate", isAction: true),
            MenuSegment(label: "CROP", icon: "crop", targetFormat: "crop", isAction: true),
            MenuSegment(label: "ADD BG", icon: "photo.on.rectangle", targetFormat: "addbg", isAction: true),
            MenuSegment(label: "REDACT", icon: "eye.slash", targetFormat: "redact", isAction: true),
        ],
        title: "Image Actions"
    )

    /// Video file → conversion formats
    private static let videoConfig = RadialMenuConfig(
        segments: [
            MenuSegment(label: "MP4", icon: "film", targetFormat: "mp4", isAction: false),
            MenuSegment(label: "MOV", icon: "film.stack", targetFormat: "mov", isAction: false),
            MenuSegment(label: "GIF", icon: "livephoto", targetFormat: "gif", isAction: false),
            MenuSegment(label: "WEBM", icon: "play.rectangle", targetFormat: "webm", isAction: false),
        ],
        title: "Convert Video"
    )

    /// Audio file → conversion formats
    private static let audioConfig = RadialMenuConfig(
        segments: [
            MenuSegment(label: "MP3", icon: "music.note", targetFormat: "mp3", isAction: false),
            MenuSegment(label: "WAV", icon: "waveform", targetFormat: "wav", isAction: false),
            MenuSegment(label: "AAC", icon: "music.note.list", targetFormat: "aac", isAction: false),
            MenuSegment(label: "FLAC", icon: "waveform.circle", targetFormat: "flac", isAction: false),
        ],
        title: "Convert Audio"
    )
}
