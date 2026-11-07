import XCTest
@testable import BarcodeKit

final class EncodingTests: XCTestCase {
    func testEANCheckDigit() {
        XCTAssertEqual(BarcodePayloadBuilder.eanCheckDigit(body: "690123456789"), 2)
        XCTAssertEqual(BarcodePayloadBuilder.upcCheckDigit(body: "03600029145"), 2)
    }

    func testEANTwelveDigitsGetsCheckDigit() {
        let payload = BarcodePayloadBuilder.make(from: "690123456789", requested: .automatic)
        XCTAssertEqual(payload.format, .ean13)
        XCTAssertEqual(payload.digits, "6901234567892")
        XCTAssertTrue(payload.isValid)
        XCTAssertNil(payload.notice)
    }

    func testEANIncorrectCheckDigitIsCorrected() {
        let payload = BarcodePayloadBuilder.make(from: "6901234567890", requested: .ean13)
        XCTAssertEqual(payload.digits, "6901234567892")
        XCTAssertNotNil(payload.notice)
        XCTAssertTrue(payload.isValid)
    }

    func testUPCA() {
        let payload = BarcodePayloadBuilder.make(from: "03600029145", requested: .automatic)
        XCTAssertEqual(payload.format, .upcA)
        XCTAssertEqual(payload.digits, "036000291452")
        XCTAssertTrue(payload.isValid)
    }

    func testAutomaticFormatSelection() {
        XCTAssertEqual(BarcodeFormat.resolved(for: "1234567", requested: .automatic), .code128)
        XCTAssertEqual(BarcodeFormat.resolved(for: "03600029145", requested: .automatic), .upcA)
        XCTAssertEqual(BarcodeFormat.resolved(for: "690123456789", requested: .automatic), .ean13)
        XCTAssertEqual(BarcodeFormat.resolved(for: "6901234567892", requested: .automatic), .ean13)
        XCTAssertEqual(BarcodeFormat.resolved(for: "6901234567892", requested: .qr), .qr)
    }

    func testAutomaticResolvesText() {
        XCTAssertEqual(BarcodeFormat.resolved(for: "ORDER-12345", requested: .automatic), .code128)
        XCTAssertEqual(BarcodeFormat.resolved(for: "订单号 12345", requested: .automatic), .qr)
        XCTAssertTrue(BarcodePayloadBuilder.make(from: "hello world", requested: .automatic).isValid)
    }

    func testNumericModesStripNonDigits() {
        XCTAssertEqual(BarcodePayloadBuilder.sanitize("69-01 23a45", for: .ean13), "69012345")
        XCTAssertEqual(BarcodePayloadBuilder.sanitize("", for: .upcA), "")
    }

    func testTextModesKeepText() {
        XCTAssertEqual(BarcodePayloadBuilder.sanitize("Hello 世界 123", for: .qr), "Hello 世界 123")
        XCTAssertEqual(BarcodePayloadBuilder.sanitize("INV-2026\n", for: .code128), "INV-2026")
    }

    func testQRAndCode128AcceptText() {
        let qr = BarcodePayloadBuilder.make(from: "https://example.com/?q=1", requested: .qr)
        XCTAssertEqual(qr.format, .qr)
        XCTAssertTrue(qr.isValid)

        let code = BarcodePayloadBuilder.make(from: "ABC-123-XYZ", requested: .code128)
        XCTAssertEqual(code.format, .code128)
        XCTAssertTrue(code.isValid)
    }

    func testCode128RejectsNonASCII() {
        let payload = BarcodePayloadBuilder.make(from: "中文内容", requested: .code128)
        XCTAssertFalse(payload.isValid)
        XCTAssertNotNil(payload.error)
    }

    func testManualEANRejectsShortInput() {
        let payload = BarcodePayloadBuilder.make(from: "12345", requested: .ean13)
        XCTAssertFalse(payload.isValid)
        XCTAssertNotNil(payload.error)
    }

    func testEANModeStripsPastedText() {
        let payload = BarcodePayloadBuilder.make(from: "订单690123456789", requested: .ean13)
        XCTAssertEqual(payload.format, .ean13)
        XCTAssertEqual(payload.digits, "6901234567892")
        XCTAssertTrue(payload.isValid)
    }

    func testEANModuleStructure() throws {
        let symbol = try XCTUnwrap(EAN13Encoder.encode(ean13: "6901234567892"))
        XCTAssertEqual(symbol.modules.count, 95)
        XCTAssertEqual(Array(symbol.modules[0..<3]), [true, false, true])
        XCTAssertEqual(Array(symbol.modules[45..<50]), [false, true, false, true, false])
        XCTAssertEqual(Array(symbol.modules[92..<95]), [true, false, true])
        XCTAssertEqual(symbol.digits.count, 13)
    }

    func testRenderProducesImage() throws {
        let payload = BarcodePayloadBuilder.make(from: "6901234567892", requested: .ean13)
        let image = try XCTUnwrap(BarcodeImageRenderer.image(for: payload, targetWidth: 1200))
        XCTAssertGreaterThan(image.width, 900)
        XCTAssertGreaterThan(image.height, 300)
    }
}
