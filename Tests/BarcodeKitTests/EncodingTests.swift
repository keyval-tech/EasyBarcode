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
        XCTAssertEqual(BarcodeFormat.resolved(digitCount: 7, requested: .automatic), .code128)
        XCTAssertEqual(BarcodeFormat.resolved(digitCount: 11, requested: .automatic), .upcA)
        XCTAssertEqual(BarcodeFormat.resolved(digitCount: 12, requested: .automatic), .ean13)
        XCTAssertEqual(BarcodeFormat.resolved(digitCount: 13, requested: .automatic), .ean13)
        XCTAssertEqual(BarcodeFormat.resolved(digitCount: 13, requested: .qr), .qr)
    }

    func testSanitize() {
        XCTAssertEqual(BarcodePayloadBuilder.sanitize("69-01 23a45"), "69012345")
        XCTAssertEqual(BarcodePayloadBuilder.sanitize("") , "")
    }

    func testManualEANRejectsShortInput() {
        let payload = BarcodePayloadBuilder.make(from: "12345", requested: .ean13)
        XCTAssertFalse(payload.isValid)
        XCTAssertNotNil(payload.error)
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
