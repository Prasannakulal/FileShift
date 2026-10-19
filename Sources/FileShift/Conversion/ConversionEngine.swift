import Foundation
import AppKit
import UniformTypeIdentifiers

/// Central conversion engine that delegates to specific converters
/// based on the source file type and target format.
class ConversionEngine {

    static let shared = ConversionEngine()

    private let imageConverter = ImageConverter()
    private let pdfConverter = PDFConverter()
    private let documentConverter = DocumentConverter()

    private init() {}

    // MARK: - Public

    /// Convert a source file to a target format
    /// - Parameters:
    ///   - source: URL of the source file
    ///   - format: Target format extension (e.g., "jpg", "png", "docx", "xlsx", "pptx", "md", "csv")
    ///   - outputDir: Directory to save the converted file
    /// - Returns: URL of the converted file
    func convert(source: URL, to format: String, outputDir: URL) async throws -> URL {
        let sourceType = FileTypeDetector.detectType(for: source)
        let target = format.lowercased()

        // 0. Image Compression Action
        if target == "compress" {
            let (out, _, _) = try await compressImage(source: source, quality: 0.65, scale: 1.0, outputDir: outputDir)
            return out
        }

        let outputURL = generateOutputURL(source: source, format: format, outputDir: outputDir)

        // 1. PDF conversions
        if sourceType == .pdf {
            return try await convertFromPDF(source: source, format: target, output: outputURL)
        }

        // 2. Image conversions (or converting image to document/PDF/SVG)
        if sourceType == .image {
            return try await convertImage(source: source, format: target, output: outputURL)
        }

        // 3. Document / Text / Data conversions
        return try documentConverter.convert(source: source, to: target, output: outputURL)
    }

    /// Compresses an image with specific quality and scale parameters
    func compressImage(
        source: URL,
        quality: Double,
        scale: Double,
        outputDir: URL
    ) async throws -> (URL, Int64, Double) {
        let outputURL = generateCompressedOutputURL(source: source, in: outputDir)
        let (out, newSize, savings) = try imageConverter.compress(
            source: source,
            quality: quality,
            scaleFactor: scale,
            output: outputURL
        )
        print("💾 Compressed \(source.lastPathComponent) → \(newSize) bytes (Saved \(Int(savings * 100))%) at \(outputURL.lastPathComponent)")
        return (out, newSize, savings)
    }

    /// Generates non-conflicting output URL for compressed file
    private func generateCompressedOutputURL(source: URL, in directory: URL) -> URL {
        let baseName = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension

        let cleanBase: String
        if baseName.hasSuffix("_compressed") {
            cleanBase = String(baseName.dropLast(11))
        } else {
            cleanBase = baseName
        }

        let standardName = "\(cleanBase)_compressed.\(ext)"
        let standardURL = directory.appendingPathComponent(standardName)

        if !FileManager.default.fileExists(atPath: standardURL.path) {
            return standardURL
        }

        var counter = 1
        while true {
            let candidateName = "\(cleanBase)_compressed_\(counter).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    // MARK: - Private Conversion Methods

    private func convertFromPDF(source: URL, format: String, output: URL) async throws -> URL {
        switch format.lowercased() {
        case "jpg", "jpeg":
            return try pdfConverter.convertToImage(source: source, format: .jpeg, output: output)
        case "png":
            return try pdfConverter.convertToImage(source: source, format: .png, output: output)
        case "tiff", "tif":
            return try pdfConverter.convertToImage(source: source, format: .tiff, output: output)
        case "webp":
            let tempImg = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            _ = try pdfConverter.convertToImage(source: source, format: .png, output: tempImg)
            defer { try? FileManager.default.removeItem(at: tempImg) }
            return try imageConverter.convertToWebP(source: tempImg, output: output)
        case "svg":
            let tempImg = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            _ = try pdfConverter.convertToImage(source: source, format: .png, output: tempImg)
            defer { try? FileManager.default.removeItem(at: tempImg) }
            return try imageConverter.convertToSVG(source: tempImg, output: output)
        case "docx", "xlsx", "csv", "pptx", "txt", "md":
            return try documentConverter.convert(source: source, to: format, output: output)
        default:
            throw ConversionError.unsupportedConversion(from: "pdf", to: format)
        }
    }

    private func convertImage(source: URL, format: String, output: URL) async throws -> URL {
        switch format.lowercased() {
        case "jpg", "jpeg":
            return try imageConverter.convert(source: source, to: .jpeg, output: output)
        case "png":
            return try imageConverter.convert(source: source, to: .png, output: output)
        case "heic":
            return try imageConverter.convert(source: source, to: .heic, output: output)
        case "webp":
            return try imageConverter.convertToWebP(source: source, output: output)
        case "avif":
            return try imageConverter.convertToAVIF(source: source, output: output)
        case "svg":
            return try imageConverter.convertToSVG(source: source, output: output)
        case "tiff", "tif":
            return try imageConverter.convert(source: source, to: .tiff, output: output)
        case "bmp":
            return try imageConverter.convert(source: source, to: .bmp, output: output)
        case "gif":
            return try imageConverter.convert(source: source, to: .gif, output: output)
        case "pdf":
            return try imageConverter.convertToPDF(source: source, output: output)
        case "docx", "txt", "md":
            // Create a document containing image description / OCR / markup
            let text = "Image file: \(source.lastPathComponent)"
            let tempTxt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
            try text.write(to: tempTxt, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempTxt) }
            return try documentConverter.convert(source: tempTxt, to: format, output: output)
        default:
            throw ConversionError.unsupportedConversion(from: source.pathExtension, to: format)
        }
    }

    // MARK: - Helpers

    /// Generate an output URL with the new extension, avoiding overwrites
    private func generateOutputURL(source: URL, format: String, outputDir: URL) -> URL {
        let settings = AppSettings.shared
        let baseName = source.deletingPathExtension().lastPathComponent

        let fileName: String
        switch settings.namingStrategy {
        case .suffix:
            fileName = "\(baseName)_converted.\(format)"
        case .replace:
            fileName = "\(baseName).\(format)"
        case .increment:
            fileName = generateIncrementedName(baseName: baseName, format: format, in: outputDir)
        }

        return outputDir.appendingPathComponent(fileName)
    }

    private func generateIncrementedName(baseName: String, format: String, in directory: URL) -> String {
        let base = "\(baseName).\(format)"
        let url = directory.appendingPathComponent(base)

        if !FileManager.default.fileExists(atPath: url.path) {
            return base
        }

        var counter = 1
        while true {
            let name = "\(baseName)_\(counter).\(format)"
            let candidateURL = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return name
            }
            counter += 1
        }
    }
}

// MARK: - Errors

enum ConversionError: LocalizedError {
    case unsupportedConversion(from: String, to: String)
    case sourceFileNotFound(URL)
    case conversionFailed(String)
    case outputWriteFailed(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedConversion(let from, let to):
            return "Cannot convert from .\(from) to .\(to)"
        case .sourceFileNotFound(let url):
            return "Source file not found: \(url.lastPathComponent)"
        case .conversionFailed(let reason):
            return "Conversion failed: \(reason)"
        case .outputWriteFailed(let url):
            return "Failed to write output: \(url.lastPathComponent)"
        }
    }
}
