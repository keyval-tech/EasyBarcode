import Foundation
import XLKit

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

/// Exports history rows to .xlsx (images embedded in cells, via XLKit) or
/// Markdown (images written to a sibling folder).
@MainActor
public enum HistoryExporter {
    public static let columnHeaders = ["#", "内容", "格式", "生成时间", "备注", "图片"]
    /// Display box for embedded barcodes, in points.
    static let imageBox = CGSize(width: 110, height: 55)

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

    /// Writes a Markdown table next to which the barcode PNGs are stored in
    /// a sibling folder (`<stem>图片/`), referenced by relative paths.
    /// Returns the exported row count.
    @discardableResult
    public static func exportMarkdown(rows: [HistoryExportRow], to url: URL) throws -> Int {
        let stem = url.deletingPathExtension().lastPathComponent
        let imagesFolderName = stem + "图片"
        let imagesDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(imagesFolderName, isDirectory: true)

        if rows.contains(where: { $0.pngData != nil }) {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }

        let exportedAt = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .medium,
            timeStyle: .short
        )

        var lines: [String] = [
            "# EasyBarcode 历史记录",
            "",
            "- 导出时间：\(exportedAt)",
            "- 共 \(rows.count) 条",
            "- 图片存放在同级文件夹「\(imagesFolderName)」，移动本文件时请一并移动。",
            ""
        ]

        for (index, row) in rows.enumerated() {
            let imageName = String(format: "%02d", index + 1) + ".png"
            // Continuation lines are indented so every block below stays
            // attached to its list item when rendered.
            lines.append("- \(escapeCodeText(row.text))")
            if let pngData = row.pngData {
                try pngData.write(
                    to: imagesDirectory.appendingPathComponent(imageName),
                    options: .atomic
                )
                lines.append("")
                lines.append("  ![](\(imagesFolderName)/\(imageName))")
            }
            lines.append("")
            lines.append("  备注：\(escapeMarkdown(row.note ?? "—"))")
            lines.append("")
            lines.append("  格式：\(escapeMarkdown(row.formatName))")
            lines.append("")
            lines.append("  生成时间：\(escapeMarkdown(row.dateString))")
            lines.append("")
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return rows.count
    }

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
}
