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
