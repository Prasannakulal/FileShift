import Foundation
import AppKit
import PDFKit

/// Handles conversions from PDF to other formats using PDFKit.
class PDFConverter {

    // MARK: - PDF → Image

    /// Convert the first page of a PDF to an image format
    func convertToImage(source: URL, format: ImageConverter.ImageFormat, output: URL) throws -> URL {
        guard let pdfDocument = PDFDocument(url: source) else {
            throw ConversionError.conversionFailed("Failed to open PDF document")
        }

        guard let firstPage = pdfDocument.page(at: 0) else {
            throw ConversionError.conversionFailed("PDF has no pages")
        }

        // Render PDF page to CGImage at 2x resolution for quality
        let pageRect = firstPage.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: Int(scaledSize.width),
            height: Int(scaledSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ConversionError.conversionFailed("Failed to create graphics context")
        }

        // White background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(origin: .zero, size: scaledSize))

        // Scale and draw the PDF page
        context.scaleBy(x: scale, y: scale)

        // PDFKit drawing
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        firstPage.draw(with: .mediaBox, to: context)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            throw ConversionError.conversionFailed("Failed to render PDF page to image")
        }

        // Write the image using ImageIO
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL,
            format.utType,
            1,
            nil
        ) else {
            throw ConversionError.outputWriteFailed(output)
        }

        let quality = AppSettings.shared.imageQuality
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed("Failed to write rendered PDF as \(format.fileExtension)")
        }

        return output
    }

    // MARK: - PDF → Text

    /// Extract text content from a PDF
    func convertToText(source: URL, output: URL) throws -> URL {
        guard let pdfDocument = PDFDocument(url: source) else {
            throw ConversionError.conversionFailed("Failed to open PDF document")
        }

        var textContent = ""

        for pageIndex in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: pageIndex) {
                if let pageText = page.string {
                    if pageIndex > 0 {
                        textContent += "\n\n--- Page \(pageIndex + 1) ---\n\n"
                    }
                    textContent += pageText
                }
            }
        }

        if textContent.isEmpty {
            textContent = "[No extractable text found in PDF]"
        }

        try textContent.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    // MARK: - PDF → DOCX

    /// Convert PDF to a basic DOCX file
    /// Uses the OOXML format to create a minimal .docx with extracted text
    func convertToDocx(source: URL, output: URL) throws -> URL {
        guard let pdfDocument = PDFDocument(url: source) else {
            throw ConversionError.conversionFailed("Failed to open PDF document")
        }

        // Extract text from all pages
        var fullText = ""
        for pageIndex in 0..<pdfDocument.pageCount {
            if let page = pdfDocument.page(at: pageIndex),
               let pageText = page.string {
                fullText += pageText + "\n\n"
            }
        }

        // Create a minimal DOCX (which is a ZIP file containing XML)
        let docxData = try createMinimalDocx(text: fullText)
        try docxData.write(to: output)

        return output
    }

    // MARK: - DOCX Creation

    /// Creates a minimal valid .docx file with the given text content.
    /// A .docx is a ZIP archive containing XML files.
    private func createMinimalDocx(text: String) throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create directory structure
        let wordDir = tempDir.appendingPathComponent("word")
        let relsDir = tempDir.appendingPathComponent("_rels")
        let wordRelsDir = wordDir.appendingPathComponent("_rels")

        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)

        // [Content_Types].xml
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        // _rels/.rels
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        try rels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        // word/_rels/document.xml.rels
        let docRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        </Relationships>
        """
        try docRels.write(to: wordRelsDir.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)

        // word/document.xml — the actual content
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let paragraphs = escapedText.components(separatedBy: "\n").map { line in
            """
            <w:p><w:r><w:t xml:space="preserve">\(line)</w:t></w:r></w:p>
            """
        }.joined(separator: "\n")

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs)
          </w:body>
        </w:document>
        """
        try document.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        // Zip the directory to create the .docx
        let zipURL = tempDir.appendingPathExtension("docx")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-j", zipURL.path, tempDir.path]
        process.currentDirectoryURL = tempDir

        // Use ditto instead (better macOS compatibility)
        let dittoProcess = Process()
        dittoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        dittoProcess.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, zipURL.path]
        try dittoProcess.run()
        dittoProcess.waitUntilExit()

        let data = try Data(contentsOf: zipURL)

        // Clean up temp files
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: zipURL)

        return data
    }
}
