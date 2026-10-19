import Foundation
import UniformTypeIdentifiers

/// Categories of files that FileShift can convert
enum FileCategory: String, CaseIterable {
    case pdf
    case image
    case document
    case video
    case audio
    case unknown
}

/// Detects the type category of a file based on its extension and UTType
struct FileTypeDetector {

    /// Map of file extensions to categories
    private static let extensionMap: [String: FileCategory] = [
        // PDF
        "pdf": .pdf,

        // Images
        "jpg": .image, "jpeg": .image, "png": .image,
        "gif": .image, "bmp": .image, "tiff": .image, "tif": .image,
        "webp": .image, "heic": .image, "heif": .image,
        "avif": .image, "svg": .image, "ico": .image,
        "raw": .image, "cr2": .image, "nef": .image,

        // Documents
        "docx": .document, "doc": .document,
        "txt": .document, "rtf": .document,
        "odt": .document, "pages": .document,
        "html": .document, "htm": .document,
        "md": .document, "markdown": .document,
        "csv": .document, "xlsx": .document, "xls": .document,
        "pptx": .document, "ppt": .document,

        // Video
        "mp4": .video, "mov": .video, "avi": .video,
        "mkv": .video, "webm": .video, "flv": .video,
        "wmv": .video, "m4v": .video,

        // Audio
        "mp3": .audio, "wav": .audio, "aac": .audio,
        "flac": .audio, "ogg": .audio, "m4a": .audio,
        "wma": .audio, "aiff": .audio,
    ]

    /// Detect the file category for a given URL
    static func detectType(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()

        // First try extension map
        if let category = extensionMap[ext] {
            return category
        }

        // Fallback to UTType
        if let utType = UTType(filenameExtension: ext) {
            if utType.conforms(to: .pdf) { return .pdf }
            if utType.conforms(to: .image) { return .image }
            if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
            if utType.conforms(to: .audio) { return .audio }
            if utType.conforms(to: .text) || utType.conforms(to: .data) { return .document }
        }

        return .unknown
    }

    /// Get a human-readable description of the file type
    static func description(for url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        let category = detectType(for: url)
        return "\(ext) (\(category.rawValue))"
    }
}
