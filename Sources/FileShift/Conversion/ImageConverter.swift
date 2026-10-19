import Foundation
import AppKit
import CoreImage
import UniformTypeIdentifiers

/// Handles image-to-image format conversions using macOS native frameworks:
/// CoreImage, ImageIO, and CGImage APIs.
class ImageConverter {

    /// Supported image output types mapped to CGImage destination types
    enum ImageFormat: String {
        case jpeg = "public.jpeg"
        case png = "public.png"
        case tiff = "public.tiff"
        case bmp = "com.microsoft.bmp"
        case gif = "com.compuserve.gif"
        case heic = "public.heic"
        case avif = "public.avif"

        var utType: CFString {
            rawValue as CFString
        }

        var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .tiff: return "tiff"
            case .bmp: return "bmp"
            case .gif: return "gif"
            case .heic: return "heic"
            case .avif: return "avif"
            }
        }
    }

    // MARK: - Public

    /// Convert an image from one format to another using ImageIO
    func convert(source: URL, to format: ImageFormat, output: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ConversionError.sourceFileNotFound(source)
        }

        // If source is SVG, render through NSImage
        if source.pathExtension.lowercased() == "svg" {
            return try convertFromSVG(source: source, to: format, output: output)
        }

        // Read source image
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.conversionFailed("Failed to read source image")
        }

        // Create destination
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            format.utType,
            1,
            nil
        ) else {
            throw ConversionError.outputWriteFailed(output)
        }

        // Set quality for lossy formats
        let quality = AppSettings.shared.imageQuality
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed("Failed to write \(format.fileExtension) image")
        }

        return output
    }

    /// Convert an image to WebP format
    func convertToWebP(source: URL, output: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ConversionError.sourceFileNotFound(source)
        }

        let cgImage: CGImage
        if source.pathExtension.lowercased() == "svg" {
            guard let img = NSImage(contentsOf: source),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cg = rep.cgImage else {
                throw ConversionError.conversionFailed("Failed to render SVG")
            }
            cgImage = cg
        } else {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ConversionError.conversionFailed("Failed to read source image")
            }
            cgImage = cg
        }

        let webpType = "org.webmproject.webp" as CFString

        if let destination = CGImageDestinationCreateWithURL(output as CFURL, webpType, 1, nil) {
            let quality = AppSettings.shared.imageQuality
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                return output
            }
        }

        // Fallback: save as PNG and rename
        return try convertToWebPFallback(cgImage: cgImage, output: output)
    }

    /// Convert an image to AVIF format
    func convertToAVIF(source: URL, output: URL) throws -> URL {
        let avifType = "public.avif" as CFString

        let cgImage: CGImage
        if source.pathExtension.lowercased() == "svg" {
            guard let img = NSImage(contentsOf: source),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cg = rep.cgImage else {
                throw ConversionError.conversionFailed("Failed to render SVG")
            }
            cgImage = cg
        } else {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ConversionError.conversionFailed("Failed to read source image")
            }
            cgImage = cg
        }

        if let destination = CGImageDestinationCreateWithURL(output as CFURL, avifType, 1, nil) {
            let quality = AppSettings.shared.imageQuality
            let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            if CGImageDestinationFinalize(destination) {
                return output
            }
        }

        // Fallback: WebP/PNG
        return try convertToWebP(source: source, output: output)
    }

    /// Convert an image to SVG format (vector wrapper container with base64 raster)
    func convertToSVG(source: URL, output: URL) throws -> URL {
        guard let image = NSImage(contentsOf: source) else {
            throw ConversionError.conversionFailed("Failed to read source image")
        }

        let width = max(1, Int(image.size.width))
        let height = max(1, Int(image.size.height))

        let pngData: Data
        if source.pathExtension.lowercased() == "png", let direct = try? Data(contentsOf: source) {
            pngData = direct
        } else if let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let repPng = rep.representation(using: .png, properties: [:]) {
            pngData = repPng
        } else {
            pngData = try Data(contentsOf: source)
        }

        let base64 = pngData.base64EncodedString()
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <image width="\(width)" height="\(height)" href="data:image/png;base64,\(base64)"/>
        </svg>
        """

        try svg.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    /// Convert an image to PDF by embedding it in a PDF page
    func convertToPDF(source: URL, output: URL) throws -> URL {
        guard let image = NSImage(contentsOf: source) else {
            throw ConversionError.conversionFailed("Failed to read source image")
        }

        let imageSize = image.size
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw ConversionError.conversionFailed("Failed to create PDF data consumer")
        }

        var mediaBox = CGRect(origin: .zero, size: CGSize(width: imageSize.width, height: imageSize.height))

        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.conversionFailed("Failed to create PDF context")
        }

        context.beginPDFPage(nil)

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: mediaBox)
        }

        context.endPDFPage()
        context.closePDF()

        try pdfData.write(to: output)
        return output
    }

    /// Compresses an image with specified quality (0.05 to 1.0) and scale factor (0.2 to 1.0).
    /// Returns the output URL, the new size in bytes, and the savings ratio (0.0 to 1.0).
    func compress(
        source: URL,
        quality: Double = 0.65,
        scaleFactor: Double = 1.0,
        output: URL
    ) throws -> (URL, Int64, Double) {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ConversionError.sourceFileNotFound(source)
        }

        let originalSize = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? 0

        let cgImage: CGImage
        if source.pathExtension.lowercased() == "svg" {
            guard let img = NSImage(contentsOf: source),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cg = rep.cgImage else {
                throw ConversionError.conversionFailed("Failed to read SVG for compression")
            }
            cgImage = cg
        } else {
            guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ConversionError.conversionFailed("Failed to read image for compression")
            }
            cgImage = cg
        }

        let width = cgImage.width
        let height = cgImage.height

        let ext = source.pathExtension.lowercased()
        let isLosslessFormat = (ext == "png" || ext == "tiff" || ext == "bmp")

        // Determine effective dimension scale
        let dimFactor: CGFloat
        if isLosslessFormat && quality < 0.88 {
            dimFactor = CGFloat(scaleFactor) * CGFloat(0.35 + (quality * 0.65))
        } else {
            dimFactor = CGFloat(scaleFactor)
        }

        let currentMax = max(CGFloat(width), CGFloat(height))
        let maxAllowedDim: CGFloat = 2560.0
        let targetMax = min(currentMax * dimFactor, maxAllowedDim)
        let finalScale = min(1.0, max(0.05, targetMax / currentMax))

        let finalImage: CGImage
        if finalScale < 0.98 {
            let newWidth = max(1, Int(CGFloat(width) * finalScale))
            let newHeight = max(1, Int(CGFloat(height) * finalScale))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let alphaInfo = cgImage.alphaInfo
            let hasAlpha = (alphaInfo == .first || alphaInfo == .last || alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast)
            let bitmapInfo: UInt32 = hasAlpha
                ? CGImageAlphaInfo.premultipliedLast.rawValue
                : CGImageAlphaInfo.noneSkipLast.rawValue

            if let ctx = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                ctx.interpolationQuality = .high
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
                finalImage = ctx.makeImage() ?? cgImage
            } else {
                finalImage = cgImage
            }
        } else {
            finalImage = cgImage
        }

        // Remove old file at destination if present to ensure clean creation
        try? FileManager.default.removeItem(at: output)

        let targetType: CFString
        var options: [CFString: Any] = [:]
        let clampedQuality = min(1.0, max(0.05, quality))

        switch ext {
        case "png":
            targetType = "public.png" as CFString
        case "heic", "heif":
            targetType = "public.heic" as CFString
            options[kCGImageDestinationLossyCompressionQuality] = clampedQuality
        case "webp":
            targetType = "org.webmproject.webp" as CFString
            options[kCGImageDestinationLossyCompressionQuality] = clampedQuality
        case "avif":
            targetType = "public.avif" as CFString
            options[kCGImageDestinationLossyCompressionQuality] = clampedQuality
        default:
            targetType = "public.jpeg" as CFString
            options[kCGImageDestinationLossyCompressionQuality] = clampedQuality
        }

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, targetType, 1, nil) else {
            throw ConversionError.outputWriteFailed(output)
        }

        CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed("Failed to compress image")
        }

        let newSize = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? originalSize
        let savingsRatio = originalSize > 0 ? max(0.0, Double(originalSize - newSize) / Double(originalSize)) : 0.0

        return (output, newSize, savingsRatio)
    }

    /// Convenience wrapper for default compression
    func compress(source: URL, output: URL) throws -> (URL, Double) {
        let (out, _, savings) = try compress(source: source, quality: 0.65, scaleFactor: 1.0, output: output)
        return (out, savings)
    }

    // MARK: - Private

    private func convertFromSVG(source: URL, to format: ImageFormat, output: URL) throws -> URL {
        guard let image = NSImage(contentsOf: source),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else {
            throw ConversionError.conversionFailed("Failed to render SVG")
        }

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            format.utType,
            1,
            nil
        ) else {
            throw ConversionError.outputWriteFailed(output)
        }

        let quality = AppSettings.shared.imageQuality
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed("Failed to write image from SVG")
        }

        return output
    }

    private func convertToWebPFallback(cgImage: CGImage, output: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempPng = tempDir.appendingPathComponent(UUID().uuidString + ".png")

        guard let destination = CGImageDestinationCreateWithURL(
            tempPng as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw ConversionError.outputWriteFailed(output)
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed("WebP not supported, PNG fallback also failed")
        }

        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: tempPng, to: output)
        return output
    }
}
