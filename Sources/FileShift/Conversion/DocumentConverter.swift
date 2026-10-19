import Foundation
import AppKit
import PDFKit

/// Handles document format conversions for:
/// DOCX, PDF, XLSX, CSV, PPTX, TXT, MD
class DocumentConverter {

    // MARK: - Public

    /// Convert a source document into the requested target format
    func convert(source: URL, to format: String, output: URL) throws -> URL {
        let ext = format.lowercased()
        switch ext {
        case "docx":
            return try convertToDocx(source: source, output: output)
        case "pdf":
            return try convertToPdf(source: source, output: output)
        case "xlsx":
            return try convertToXlsx(source: source, output: output)
        case "csv":
            return try convertToCsv(source: source, output: output)
        case "pptx":
            return try convertToPptx(source: source, output: output)
        case "txt":
            return try convertToTxt(source: source, output: output)
        case "md", "markdown":
            return try convertToMd(source: source, output: output)
        default:
            throw ConversionError.unsupportedConversion(from: source.pathExtension, to: format)
        }
    }

    // MARK: - Text Extraction

    /// Extract plain text content from various document types
    func extractText(from source: URL) throws -> String {
        let ext = source.pathExtension.lowercased()

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: source) else {
                throw ConversionError.conversionFailed("Unable to open PDF")
            }
            var text = ""
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i), let pageText = page.string {
                    text += pageText + "\n\n"
                }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try reading directly as UTF-8
        if let directString = try? String(contentsOf: source, encoding: .utf8) {
            return directString
        }

        // Try macOS textutil to convert to plain text
        let tempTxt = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-output", tempTxt.path, source.path]
        try? process.run()
        process.waitUntilExit()

        if FileManager.default.fileExists(atPath: tempTxt.path),
           let text = try? String(contentsOf: tempTxt, encoding: .utf8) {
            try? FileManager.default.removeItem(at: tempTxt)
            return text
        }

        throw ConversionError.conversionFailed("Failed to read text from \(source.lastPathComponent)")
    }

    // MARK: - Converters

    /// Convert to Microsoft Word (.docx)
    func convertToDocx(source: URL, output: URL) throws -> URL {
        let sourceExt = source.pathExtension.lowercased()

        // If source is text-based or HTML, macOS textutil creates genuine Word 2007+ files
        if ["txt", "rtf", "html", "htm", "md"].contains(sourceExt) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", "docx", "-output", output.path, source.path]
            try process.run()
            process.waitUntilExit()

            if FileManager.default.fileExists(atPath: output.path) {
                return output
            }
        }

        // Fallback: extract text and build OOXML docx
        let text = try extractText(from: source)
        try createOOXMLDocx(text: text, output: output)
        return output
    }

    /// Convert to PDF using CoreText and CGContext (thread-safe, high quality vector output)
    func convertToPdf(source: URL, output: URL) throws -> URL {
        let text = try extractText(from: source)

        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ConversionError.conversionFailed("Failed to create PDF context")
        }

        var mediaBox = pageRect
        context.beginPage(mediaBox: &mediaBox)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ])

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let textRect = pageRect.insetBy(dx: 54, dy: 54)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributed.length), path, nil)

        CTFrameDraw(frame, context)

        context.endPage()
        context.closePDF()

        try pdfData.write(to: output)
        return output
    }

    /// Convert to Plain Text (.txt)
    func convertToTxt(source: URL, output: URL) throws -> URL {
        let text = try extractText(from: source)
        try text.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    /// Convert to Markdown (.md)
    func convertToMd(source: URL, output: URL) throws -> URL {
        let text = try extractText(from: source)
        let baseName = source.deletingPathExtension().lastPathComponent

        // Enhance formatted text with title header if missing
        var md = ""
        if !text.hasPrefix("#") {
            md += "# \(baseName)\n\n"
        }
        md += text
        try md.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    /// Convert to CSV (.csv)
    func convertToCsv(source: URL, output: URL) throws -> URL {
        let text = try extractText(from: source)
        let lines = text.components(separatedBy: .newlines)

        var csvLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // If line is tab-separated or comma-separated, preserve or normalize
            if trimmed.contains("\t") {
                let cols = trimmed.components(separatedBy: "\t").map { escapeCsvCell($0) }
                csvLines.append(cols.joined(separator: ","))
            } else if trimmed.contains(",") {
                csvLines.append(trimmed)
            } else if trimmed.contains("|") {
                // Markdown table row
                let cols = trimmed.split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.allSatisfy { $0 == "-" } }
                    .map { escapeCsvCell($0) }
                if !cols.isEmpty {
                    csvLines.append(cols.joined(separator: ","))
                }
            } else {
                csvLines.append(escapeCsvCell(trimmed))
            }
        }

        let csvContent = csvLines.joined(separator: "\n")
        try csvContent.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    /// Convert to Microsoft Excel (.xlsx)
    func convertToXlsx(source: URL, output: URL) throws -> URL {
        let text = try extractText(from: source)
        let lines = text.components(separatedBy: .newlines)

        var rows: [[String]] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains("\t") {
                rows.append(trimmed.components(separatedBy: "\t"))
            } else if trimmed.contains(",") {
                rows.append(parseCsvLine(trimmed))
            } else if trimmed.contains("|") {
                let cols = trimmed.split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.allSatisfy { $0 == "-" } }
                if !cols.isEmpty {
                    rows.append(cols)
                }
            } else {
                rows.append([trimmed])
            }
        }

        try createOOXMLXlsx(rows: rows, output: output)
        return output
    }

    /// Convert to Microsoft PowerPoint (.pptx)
    func convertToPptx(source: URL, output: URL) throws -> URL {
        let text = try extractText(from: source)
        let title = source.deletingPathExtension().lastPathComponent

        // Group paragraphs into slides (approx 3-5 lines per slide)
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let slides = paragraphs.isEmpty ? [title] : paragraphs
        try createOOXMLPptx(title: title, slides: slides, output: output)
        return output
    }

    // MARK: - OOXML Generators

    private func createOOXMLDocx(text: String, output: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let wordDir = tempDir.appendingPathComponent("word")
        let relsDir = tempDir.appendingPathComponent("_rels")
        let wordRelsDir = wordDir.appendingPathComponent("_rels")
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        try rels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        let escaped = xmlEscape(text)
        let paragraphs = escaped.components(separatedBy: "\n").map { line in
            "<w:p><w:r><w:t xml:space=\"preserve\">\(line)</w:t></w:r></w:p>"
        }.joined(separator: "\n")

        let doc = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>\(paragraphs)</w:body>
        </w:document>
        """
        try doc.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        try zipFolder(source: tempDir, output: output)
    }

    private func createOOXMLXlsx(rows: [[String]], output: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xlDir = tempDir.appendingPathComponent("xl")
        let relsDir = tempDir.appendingPathComponent("_rels")
        let xlRelsDir = xlDir.appendingPathComponent("_rels")
        let wsDir = xlDir.appendingPathComponent("worksheets")
        try FileManager.default.createDirectory(at: xlDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try rels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        let wbRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
        try wbRels.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)

        let wb = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
        try wb.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)

        var rowXml = ""
        for (rIdx, row) in rows.enumerated() {
            let rowNumber = rIdx + 1
            var cellsXml = ""
            for (cIdx, cell) in row.enumerated() {
                let colLetter = columnLetter(for: cIdx)
                let ref = "\(colLetter)\(rowNumber)"
                let escaped = xmlEscape(cell)
                cellsXml += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(escaped)</t></is></c>"
            }
            rowXml += "<row r=\"\(rowNumber)\">\(cellsXml)</row>\n"
        }

        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>\(rowXml)</sheetData>
        </worksheet>
        """
        try sheet.write(to: wsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)

        try zipFolder(source: tempDir, output: output)
    }

    private func createOOXMLPptx(title: String, slides: [String], output: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pptDir = tempDir.appendingPathComponent("ppt")
        let relsDir = tempDir.appendingPathComponent("_rels")
        let pptRelsDir = pptDir.appendingPathComponent("_rels")
        let slidesDir = pptDir.appendingPathComponent("slides")
        try FileManager.default.createDirectory(at: pptDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pptRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: slidesDir, withIntermediateDirectories: true)

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
          <Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>
        </Types>
        """
        try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
        </Relationships>
        """
        try rels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        let presRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
        </Relationships>
        """
        try presRels.write(to: pptRelsDir.appendingPathComponent("presentation.xml.rels"), atomically: true, encoding: .utf8)

        let pres = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>
        </p:presentation>
        """
        try pres.write(to: pptDir.appendingPathComponent("presentation.xml"), atomically: true, encoding: .utf8)

        let slideContent = slides.prefix(5).map { xmlEscape($0) }.joined(separator: "</a:t></a:r></a:p><a:p><a:r><a:t>")
        let slide1 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:spTree>
              <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
              <p:grpSpPr/>
              <p:sp>
                <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
                <p:spPr/>
                <p:txBody>
                  <a:bodyPr/>
                  <a:p><a:r><a:t>\(xmlEscape(title))</a:t></a:r></a:p>
                  <a:p><a:r><a:t>\(slideContent)</a:t></a:r></a:p>
                </p:txBody>
              </p:sp>
            </p:spTree>
          </p:cSld>
        </p:sld>
        """
        try slide1.write(to: slidesDir.appendingPathComponent("slide1.xml"), atomically: true, encoding: .utf8)

        try zipFolder(source: tempDir, output: output)
    }

    private func zipFolder(source: URL, output: URL) throws {
        try? FileManager.default.removeItem(at: output)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", source.path, output.path]
        try ditto.run()
        ditto.waitUntilExit()

        guard FileManager.default.fileExists(atPath: output.path) else {
            throw ConversionError.outputWriteFailed(output)
        }
    }

    // MARK: - Helpers

    private func xmlEscape(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func escapeCsvCell(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return string
    }

    private func parseCsvLine(_ line: String) -> [String] {
        return line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func columnLetter(for index: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        if index < letters.count {
            return letters[index]
        }
        return "A\(letters[index % letters.count])"
    }
}
