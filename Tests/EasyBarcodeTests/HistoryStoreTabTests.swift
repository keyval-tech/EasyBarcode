import XCTest
import BarcodeKit
@testable import EasyBarcode
@testable import BarcodeKit

final class HistoryStoreTabTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: HistoryStore!
    private var imagesDir: URL!

    override func setUpWithError() throws {
        suiteName = "test-easybarcode-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = HistoryStore(defaults: defaults)
        imagesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("eb-hist-\(UUID().uuidString)", isDirectory: true)
        store.setImagesDirectory(imagesDir)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: imagesDir)
    }

    @MainActor
    private func seedThreeEntries() {
        store.record(digits: "6901234567892", format: .ean13)
        store.record(digits: "ORDER-12345", format: .code128)
        store.record(digits: "订单号 9527", format: .qr)
    }

    @MainActor
    func testTabLifecycle() {
        seedThreeEntries()

        XCTAssertTrue(store.tabs.isEmpty)
        store.addTab("样品")
        store.addTab("客户A")
        store.addTab(" 样品 ") // duplicate after trim is ignored
        XCTAssertEqual(store.tabs, ["样品", "客户A"])

        let entry = store.entries[0]
        store.toggleTab(id: entry.id, tab: "样品")
        XCTAssertEqual(store.entries[0].tabs, ["样品"])

        // Toggle off.
        store.toggleTab(id: entry.id, tab: "样品")
        XCTAssertNil(store.entries[0].tabs)

        // Toggle on again, then rename propagates to entries.
        store.toggleTab(id: entry.id, tab: "样品")
        store.renameTab("样品", to: "打样")
        XCTAssertEqual(store.tabs, ["打样", "客户A"])
        XCTAssertEqual(store.entries[0].tabs, ["打样"])

        // Removing a tab only unassigns entries.
        store.removeTab("打样")
        XCTAssertFalse(store.tabs.contains("打样"))
        XCTAssertNil(store.entries[0].tabs)
    }

    @MainActor
    func testFilterByTabFormatAndNotes() {
        seedThreeEntries()
        store.addTab("样品")
        store.toggleTab(id: store.entries[2].id, tab: "样品")
        store.updateNote(id: store.entries[1].id, note: "给客户的样品")

        var filter = HistoryFilter()
        XCTAssertEqual(store.entries(matching: filter).count, 3)

        filter.tab = "样品"
        XCTAssertEqual(store.entries(matching: filter).count, 1)
        XCTAssertEqual(store.entries(matching: filter).first?.digits, "6901234567892")

        filter.tab = nil
        filter.format = .qr
        XCTAssertEqual(store.entries(matching: filter).count, 1)
        XCTAssertEqual(store.entries(matching: filter).first?.digits, "订单号 9527")

        filter.format = nil
        filter.onlyWithNotes = true
        XCTAssertEqual(store.entries(matching: filter).count, 1)
        XCTAssertEqual(store.entries(matching: filter).first?.digits, "ORDER-12345")

        filter.onlyWithNotes = false
        filter.query = "样品" // matches the note of ORDER-12345 and the tab-tagged EAN card's content? only note/digits checked
        let queried = store.entries(matching: filter)
        XCTAssertEqual(queried.count, 1)
        XCTAssertEqual(queried.first?.digits, "ORDER-12345")
    }

    @MainActor
    func testTimeRangeFilter() throws {
        seedThreeEntries()

        // Simulate an old entry by moving its date back.
        let old = try XCTUnwrap(store.entries.last)
        store.entries[store.entries.count - 1].createdAt = Date().addingTimeInterval(-40 * 86_400)

        var filter = HistoryFilter()
        filter.timeRange = .today
        XCTAssertEqual(store.entries(matching: filter).count, 2)

        filter.timeRange = .last30
        XCTAssertEqual(store.entries(matching: filter).count, 2)

        filter.timeRange = .all
        XCTAssertEqual(store.entries(matching: filter).count, 3)
        _ = old
    }

    @MainActor
    func testTabsDecodeFromLegacyJSON() throws {
        seedThreeEntries()
        store.addTab("样品")
        store.toggleTab(id: store.entries[0].id, tab: "样品")

        // Strip the "tabs" key to simulate data written by an older build.
        let key = "EasyBarcode.history.v1"
        guard let data = defaults.data(forKey: key),
              var list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return XCTFail("history data missing")
        }
        for index in list.indices {
            list[index].removeValue(forKey: "tabs")
        }
        let legacy = try JSONSerialization.data(withJSONObject: list)
        defaults.set(legacy, forKey: key)

        let reopened = HistoryStore(defaults: defaults)
        XCTAssertEqual(reopened.entries.count, 3)
        XCTAssertNil(reopened.entries[0].tabs, "legacy entries decode without tabs")
    }

    @MainActor
    func testRecordingSameCodeKeepsNoteAndTags() {
        seedThreeEntries()
        let original = try! XCTUnwrap(store.entries.first { $0.digits == "6901234567892" })
        store.updateNote(id: original.id, note: "客户样品\n第二行")
        store.addTab("样品")
        store.toggleTab(id: original.id, tab: "样品")

        store.record(digits: "6901234567892", format: .ean13)

        XCTAssertEqual(store.entries.count, 3, "regenerating must not add a row")
        let refreshed = store.entries[0]
        XCTAssertEqual(refreshed.id, original.id, "same record, not a replacement")
        XCTAssertEqual(refreshed.note, "客户样品\n第二行")
        XCTAssertEqual(refreshed.tabs, ["样品"])
        XCTAssertGreaterThan(refreshed.createdAt, original.createdAt)
        XCTAssertNotNil(refreshed.imagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: refreshed.imagePath ?? ""))
    }

    @MainActor
    func testSanitizeFileName() {
        XCTAssertEqual(
            HistoryExporter.sanitizeFileName("EAN-13_6901234567892"),
            "EAN-13_6901234567892"
        )
        XCTAssertEqual(
            HistoryExporter.sanitizeFileName("QR_bad/name:here"),
            "QR_bad_name_here"
        )
        XCTAssertEqual(HistoryExporter.sanitizeFileName("  spaced  "), "spaced")
        XCTAssertEqual(HistoryExporter.sanitizeFileName("///"), "___")
        XCTAssertEqual(HistoryExporter.sanitizeFileName(""), "未命名")
        XCTAssertEqual(
            HistoryExporter.sanitizeFileName(String(repeating: "字", count: 100)).count,
            80
        )
    }
}
