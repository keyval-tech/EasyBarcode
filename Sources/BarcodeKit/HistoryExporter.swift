import Foundation
import XLKit
import ZIPFoundation

/// One row of a history export. Decoupled from the app's HistoryEntry so the
/// exporter stays testable inside BarcodeKit.
public struct HistoryExportRow: Sendable {
    public let text: String
    public let formatName: String
    public let dateString: String
    public let note: String?
    /// PNG bytes for the barcode image; `nil` leaves the image cell empty.
    public let pngData: Data?

    public init(text: String, formatName: String, dateString: String, note: String?, pngData: Data?) {
        self.text = text
        self.formatName = formatName
        self.dateString = dateString
        self.note = note
        self.pngData = pngData
    }
}

/// Exports history rows to .xlsx (images embedded via XLKit), .docx (inline
/// images, packaged with ZIPFoundation) or Markdown (images written to a
/// sibling folder).
@MainActor
public enum HistoryExporter {
    public static let columnHeaders = ["#", "内容", "格式", "生成时间", "备注", "图片"]
    /// Display box for embedded barcodes, in points.
    static let imageBox = CGSize(width: 110, height: 55)
    /// Display width (CSS pixels) for Markdown and DOCX images.
    static let imageDisplayWidth: Double = 180

    // MARK: - XLSX

    /// Writes an .xlsx workbook with one sheet; each row's barcode PNG is
    /// embedded into the last column. Returns the exported row count.
    @discardableResult
    public static func exportXLSX(rows: [HistoryExportRow], to url: URL) async throws -> Int {
        let workbook = Workbook()
        let sheet = workbook.addSheet(name: "历史记录")
        sheet.setRow(1, strings: columnHeaders)

        for (index, row) in rows.enumerated() {
            let rowNumber = index + 2
            sheet.setRow(rowNumber, strings: [
                "\(index + 1)",
                row.text,
                row.formatName,
                row.dateString,
                row.note ?? ""
            ])
            if let pngData = row.pngData {
                _ = try await sheet.embedImageAutoSized(
                    pngData,
                    at: "F\(rowNumber)",
                    of: workbook,
                    maxCellWidth: imageBox.width,
                    maxCellHeight: imageBox.height,
                    scale: 1.0
                )
            }
        }

        try await workbook.save(to: url)
        return rows.count
    }

    // MARK: - DOCX

    /// Writes a .docx mirroring the Markdown layout: title, 条目 section with
    /// one bullet per entry (code / inline image / 备注 / 格式 / 生成时间),
    /// then 导出信息. Returns the exported row count.
    @discardableResult
    public static func exportDOCX(rows: [HistoryExportRow], to url: URL) throws -> Int {
        var media: [(name: String, data: Data)] = []
        var relationships: [String] = []
        var body: [String] = []

        func paragraph(_ runs: String, size: Int = 22, bold: Bool = false) -> String {
            let boldXML = bold ? "<w:b/>" : ""
            return "<w:p><w:r><w:rPr>\(boldXML)<w:sz w:val=\"\(size)\"/></w:rPr>\(runs)</w:r></w:p>"
        }

        func textRun(_ text: String) -> String {
            "<w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t>"
        }

        // Title and section headings use direct formatting so no styles.xml
        // part is required.
        body.append(paragraph(textRun("EasyBarcode 历史记录"), size: 32, bold: true))
        body.append(paragraph(textRun("条目"), size: 26, bold: true))

        for (index, row) in rows.enumerated() {
            let imageName = "image\(index + 1).png"
            body.append(paragraph("<w:t xml:space=\"preserve\">• </w:t>" + textRun(row.text)))

            if let pngData = row.pngData {
                media.append((imageName, pngData))
                let relID = "rId\(media.count)"
                relationships.append(
                    "<Relationship Id=\"\(relID)\" "
                        + "Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" "
                        + "Target=\"media/\(imageName)\"/>"
                )
                if let size = pngPixelSize(pngData) {
                    let extent = displayExtent(
                        pixelSize: size,
                        maxWidth: imageDisplayWidth,
                        maxHeight: 180
                    )
                    body.append(imageParagraph(relID: relID, name: imageName, extent: extent, id: media.count + 1))
                }
            }

            body.append(paragraph(textRun("备注：\(row.note ?? "—")"), size: 18))
            body.append(paragraph(textRun("格式：\(row.formatName)"), size: 18))
            body.append(paragraph(textRun("生成时间：\(row.dateString)"), size: 18))
        }

        body.append(paragraph(textRun("导出信息"), size: 26, bold: true))
        let exportedAt = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        body.append(paragraph(textRun("导出时间：\(exportedAt)"), size: 18))
        body.append(paragraph(textRun("共 \(rows.count) 条"), size: 18))
        if !media.isEmpty {
            body.append(paragraph(textRun("图片随文档一并嵌入，可在 Word 中直接查看。"), size: 18))
        }
        body.append(
            "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/>"
                + "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/></w:sectPr>"
        )

        let documentXML =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                + "<w:document"
                + " xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""
                + " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
                + " xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\""
                + " xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
                + " xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
                + "<w:body>" + body.joined() + "</w:body></w:document>"

        let contentTypesXML =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
                + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
                + "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
                + "<Default Extension=\"png\" ContentType=\"image/png\"/>"
                + "<Override PartName=\"/word/document.xml\""
                + " ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
                + "</Types>"

        let rootRelsXML =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                + "<Relationship Id=\"rId1\""
                + " Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\""
                + " Target=\"word/document.xml\"/>"
                + "</Relationships>"

        let documentRelsXML =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
                + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
                + relationships.joined()
                + "</Relationships>"

        let archive = try Archive(url: url, accessMode: .create)
        try addData(archive: archive, name: "[Content_Types].xml", data: Data(contentTypesXML.utf8))
        try addData(archive: archive, name: "_rels/.rels", data: Data(rootRelsXML.utf8))
        try addData(archive: archive, name: "word/document.xml", data: Data(documentXML.utf8))
        try addData(archive: archive, name: "word/_rels/document.xml.rels", data: Data(documentRelsXML.utf8))
        for entry in media {
            try addData(archive: archive, name: "word/media/\(entry.name)", data: entry.data)
        }

        return rows.count
    }

    static func imageParagraph(relID: String, name: String, extent: CGSize, id: Int) -> String {
        let cx = Int(extent.width * 12700)
        let cy = Int(extent.height * 12700)
        return "<w:p><w:r><w:drawing>"
            + "<wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">"
            + "<wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/>"
            + "<wp:docPr id=\"\(id)\" name=\"\(name)\"/>"
            + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
            + "<pic:pic>"
            + "<pic:nvPicPr><pic:cNvPr id=\"\(id)\" name=\"\(name)\"/><pic:cNvPicPr/></pic:nvPicPr>"
            + "<pic:blipFill><a:blip r:embed=\"\(relID)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
            + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>"
            + "</pic:pic></a:graphicData></a:graphic></wp:inline>"
            + "</w:drawing></w:r></w:p>"
    }

    // MARK: - Markdown

    /// Writes a Markdown document mirroring the DOCX layout: 条目 section with
    /// one bullet per entry, then 导出信息. Barcode PNGs are stored in a
    /// sibling folder (`<stem>图片/`) and referenced by relative paths.
    /// Returns the exported row count.
    @discardableResult
    public static func exportMarkdown(rows: [HistoryExportRow], to url: URL) throws -> Int {
        let stem = url.deletingPathExtension().lastPathComponent
        let imagesFolderName = stem + "图片"
        let imagesDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(imagesFolderName, isDirectory: true)

        let exportedAt = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .medium,
            timeStyle: .short
        )

        let hasImages = rows.contains(where: { $0.pngData != nil })
        if hasImages {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }

        var lines: [String] = [
            "# EasyBarcode 历史记录",
            "",
            "## 条目",
            ""
        ]

        for (index, row) in rows.enumerated() {
            let imageName = String(format: "%02d", index + 1) + ".png"
            // Continuation lines are indented so every block below stays
            // attached to its list item when rendered. Images are limited
            // via an <img width> attribute; plain Markdown cannot scale.
            lines.append("- \(escapeCodeText(row.text))")
            if let pngData = row.pngData {
                try pngData.write(
                    to: imagesDirectory.appendingPathComponent(imageName),
                    options: .atomic
                )
                lines.append("")
                lines.append("  <img src=\"\(imagesFolderName)/\(imageName)\" width=\"\(Int(imageDisplayWidth))\">")
            }
            lines.append("")
            lines.append("  备注：\(escapeMarkdown(row.note ?? "—"))")
            lines.append("")
            lines.append("  格式：\(escapeMarkdown(row.formatName))")
            lines.append("")
            lines.append("  生成时间：\(escapeMarkdown(row.dateString))")
            lines.append("")
        }

        lines.append("## 导出信息")
        lines.append("")
        lines.append("- 导出时间：\(exportedAt)")
        lines.append("- 共 \(rows.count) 条")
        if hasImages {
            lines.append("- 图片存放在同级文件夹「\(imagesFolderName)」，移动本文件时请一并移动。")
        }
        lines.append("")

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return rows.count
    }

    // MARK: - Helpers

    /// Backtick-wrapped code span; falls back to escaped plain text when the
    /// content itself contains backticks.
    static func escapeCodeText(_ text: String) -> String {
        guard !text.contains("`") else { return escapeMarkdown(text) }
        return "`\(escapeMarkdown(text))`"
    }

    static func escapeMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " / ")
            .replacingOccurrences(of: "\r", with: "")
    }

    static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Reads the pixel dimensions from a PNG's IHDR header.
    static func pngPixelSize(_ data: Data) -> CGSize? {
        let bytes = [UInt8](data)
        guard bytes.count >= 24,
              bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47
        else { return nil }

        func be32(_ offset: Int) -> Double {
            Double(
                UInt32(bytes[offset]) << 24
                    | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8
                    | UInt32(bytes[offset + 3])
            )
        }
        let width = be32(16)
        let height = be32(20)
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Scales a pixel size down to fit inside the display box, in points.
    static func displayExtent(pixelSize: CGSize, maxWidth: Double, maxHeight: Double) -> CGSize {
        let scale = min(maxWidth / pixelSize.width, maxHeight / pixelSize.height, 1)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    static func addData(archive: Archive, name: String, data: Data) throws {
        try archive.addEntry(
            with: name,
            type: .file,
            uncompressedSize: UInt32(data.count),
            modificationDate: Date(),
            permissions: nil,
            bufferSize: 64 * 1024,
            provider: { position, size in
                data.subdata(in: position..<position + size)
            }
        )
    }
}
