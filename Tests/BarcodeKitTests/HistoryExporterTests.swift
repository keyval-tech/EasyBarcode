import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import BarcodeKit

final class HistoryExporterTests: XCTestCase {
    /// Small PNG rendered via CoreGraphics so the embedded media carries real
    /// image bytes.
    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 1, y: 1, width: width - 2, height: height - 2))
        let image = try XCTUnwrap(context.makeImage())

        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func makeRows() throws -> [HistoryExportRow] {
        [
            HistoryExportRow(
                text: "6901234567892",
                formatName: "EAN-13",
                dateString: "2026-11-08 09:24",
                note: "样品 | 给客户",
                pngData: try makePNG(width: 120, height: 64)
            ),
            HistoryExportRow(
                text: "ORDER-12345",
                formatName: "Code 128",
                dateString: "2026-11-08 09:30",
                note: nil,
                pngData: try makePNG(width: 140, height: 40)
            ),
            HistoryExportRow(
                text: "订单号 9527",
                formatName: "QR",
                dateString: "2026-11-08 09:35",
                note: "多行\n备注",
                pngData: nil
            )
        ]
    }

    @MainActor
    func testXLSXExportProducesValidWorkbookWithImages() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eb-export-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }

        let count = try await HistoryExporter.exportXLSX(rows: try makeRows(), to: url)
        XCTAssertEqual(count, 3)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 1000)

        // Structural check: it must be a readable ZIP.
        try validateWithProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-t", url.path],
            expectOutput: "No errors detected"
        )

        // Semantic check via openpyxl when available.
        try validateWithOpenPyXL(at: url)
    }

    @MainActor
    func testMarkdownExportWritesTableAndImageFolder() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("eb-md-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("EasyBarcode历史-2026-11-08.md")
        defer { try? FileManager.default.removeItem(at: base) }

        let count = try HistoryExporter.exportMarkdown(rows: try makeRows(), to: url)
        XCTAssertEqual(count, 3)

        let markdown = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# EasyBarcode 历史记录"))
        XCTAssertTrue(markdown.contains("## 条目"))
        XCTAssertTrue(markdown.contains("## 导出信息"))
        // Metadata section comes after the entries.
        XCTAssertLessThan(
            markdown.range(of: "## 条目")!.upperBound,
            markdown.range(of: "- 导出时间：")!.lowerBound
        )
        XCTAssertTrue(markdown.contains("- 共 3 条"))
        XCTAssertTrue(markdown.contains("- `6901234567892`"))
        XCTAssertTrue(markdown.contains("  <img src=\"EasyBarcode历史-2026-11-08图片/01.png\" width=\"180\">"))
        XCTAssertTrue(markdown.contains("  备注：样品 \\| 给客户"))
        XCTAssertTrue(markdown.contains("  格式：EAN-13"))
        XCTAssertTrue(markdown.contains("  生成时间：2026-11-08 09:24"))
        XCTAssertTrue(markdown.contains("- `订单号 9527`"))
        XCTAssertTrue(markdown.contains("  备注：多行 / 备注"))
        XCTAssertFalse(markdown.contains("| # |"))

        let imagesFolder = base.appendingPathComponent("EasyBarcode历史-2026-11-08图片", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesFolder.appendingPathComponent("01.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imagesFolder.appendingPathComponent("02.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imagesFolder.appendingPathComponent("03.png").path))
    }

    @MainActor
    func testDOCXExportProducesDocumentWithInlineImages() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eb-export-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: url) }

        let count = try HistoryExporter.exportDOCX(rows: try makeRows(), to: url)
        XCTAssertEqual(count, 3)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 1000)

        try validateWithProcess(
            executable: "/usr/bin/unzip",
            arguments: ["-t", url.path],
            expectOutput: "No errors detected"
        )

        // The document part carries the expected content and exactly two
        // inline drawings (rows 1 and 2 have images; row 3 does not).
        let document = try documentXML(of: url)
        XCTAssertTrue(document.contains("EasyBarcode 历史记录"))
        XCTAssertTrue(document.contains("条目"))
        XCTAssertTrue(document.contains("• "))
        XCTAssertTrue(document.contains("6901234567892"))
        XCTAssertTrue(document.contains("备注：样品"))
        XCTAssertTrue(document.contains("导出信息"))
        XCTAssertEqual(document.components(separatedBy: "<w:drawing>").count - 1, 2)

        let rels = try tryUnzip(of: url, entry: "word/_rels/document.xml.rels")
        XCTAssertTrue(rels.contains("media/image1.png"))
        XCTAssertTrue(rels.contains("media/image2.png"))
        XCTAssertFalse(rels.contains("media/image3.png"))

        try validateWithPythonDocX(at: url)
    }

    @MainActor
    func testHTMLExportProducesSelfContainedTableWithEmbeddedImages() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eb-export-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: url) }

        let count = try HistoryExporter.exportHTML(rows: try makeRows(), to: url)
        XCTAssertEqual(count, 3)

        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains("<title>EasyBarcode 历史记录</title>"))
        XCTAssertTrue(html.contains("## 条目".replacingOccurrences(of: "## ", with: "<h2>")))
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>#</th><th>内容</th><th>格式</th><th>生成时间</th><th>备注</th><th>图片</th>"))
        XCTAssertTrue(html.contains("<td class=\"code\">6901234567892</td>"))
        XCTAssertTrue(html.contains("<td>样品 | 给客户</td>"))
        // Two embedded images as data URIs; row 3 has none.
        XCTAssertEqual(html.components(separatedBy: "data:image/png;base64,").count - 1, 2)
        XCTAssertTrue(html.contains("width=\"180\""))
        XCTAssertTrue(html.contains("<td>多行<br>备注</td>"))
        XCTAssertTrue(html.contains("<h2>导出信息</h2>"))
        XCTAssertTrue(html.contains("共 3 条"))
        XCTAssertFalse(html.contains("images-fallback-folder"))
    }

    // MARK: - Helpers

    private func validateWithProcess(
        executable: String,
        arguments: [String],
        expectOutput: String? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "process failed:\n\(output)")
        if let expectOutput {
            XCTAssertTrue(output.contains(expectOutput), "expected \(expectOutput), got:\n\(output)")
        }
    }

    private func tryUnzip(of url: URL, entry: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "unzip -p failed")
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func documentXML(of url: URL) throws -> String {
        try tryUnzip(of: url, entry: "word/document.xml")
    }

    private func validateWithPythonDocX(at url: URL) throws {
        let availability = Process()
        availability.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        availability.arguments = ["python3", "-c", "import docx"]
        availability.standardOutput = Pipe()
        availability.standardError = Pipe()
        try? availability.run()
        availability.waitUntilExit()
        guard availability.terminationStatus == 0 else {
            throw XCTSkip("python-docx not installed; skipping semantic validation")
        }

        let script = """
        import docx
        doc = docx.Document(r"\(url.path)")
        texts = [p.text for p in doc.paragraphs]
        assert "EasyBarcode 历史记录" in texts, texts
        assert "条目" in texts
        assert any("6901234567892" in t for t in texts), texts
        assert len(doc.inline_shapes) == 2, len(doc.inline_shapes)
        print("PYTHON-DOCX-OK")
        """

        try validateWithProcess(
            executable: "/usr/bin/env",
            arguments: ["python3", "-c", script],
            expectOutput: "PYTHON-DOCX-OK"
        )
    }

    private func validateWithOpenPyXL(at url: URL) throws {
        let availability = Process()
        availability.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        availability.arguments = ["python3", "-c", "import openpyxl"]
        availability.standardOutput = Pipe()
        availability.standardError = Pipe()
        try? availability.run()
        availability.waitUntilExit()
        guard availability.terminationStatus == 0 else {
            throw XCTSkip("openpyxl not installed; skipping semantic validation")
        }

        let script = """
        import sys
        from openpyxl import load_workbook
        wb = load_workbook(r"\(url.path)")
        ws = wb.active
        assert ws["A1"].value == "#", ws["A1"].value
        assert ws["B2"].value == "6901234567892", ws["B2"].value
        assert ws["C2"].value == "EAN-13"
        assert ws["D3"].value == "2026-11-08 09:30", ws["D3"].value
        assert ws["E4"].value == "多行\\n备注", ws["E4"].value
        assert len(ws._images) == 2, len(ws._images)
        print("OPENPYXL-OK")
        """

        try validateWithProcess(
            executable: "/usr/bin/env",
            arguments: ["python3", "-c", script],
            expectOutput: "OPENPYXL-OK"
        )
    }
}
