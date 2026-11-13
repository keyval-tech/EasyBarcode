import XCTest
@testable import BarcodeKit

/// Tab cycles through these, so a format must only appear when the current
/// input can actually be encoded without throwing part of it away.
final class FormatAvailabilityTests: XCTestCase {
    func testEmptyInputOffersEveryFormat() {
        XCTAssertEqual(BarcodePayloadBuilder.supportedFormats(for: ""), BarcodeFormat.allCases)
        XCTAssertEqual(BarcodePayloadBuilder.supportedFormats(for: "   "), BarcodeFormat.allCases)
    }

    func testThirteenDigitsOffersRetailAndTextFormats() {
        let formats = BarcodePayloadBuilder.supportedFormats(for: "6901234567892")
        XCTAssertEqual(formats, [.automatic, .ean13, .code128, .qr])
        XCTAssertFalse(formats.contains(.upcA), "13 digits is not a valid UPC-A length")
    }

    func testElevenDigitsOffersUPCA() {
        let formats = BarcodePayloadBuilder.supportedFormats(for: "12345678901")
        XCTAssertEqual(formats, [.automatic, .upcA, .code128, .qr])
        XCTAssertFalse(formats.contains(.ean13))
    }

    func testTwelveDigitsOffersBothRetailFormats() {
        XCTAssertEqual(
            BarcodePayloadBuilder.supportedFormats(for: "123456789012"),
            [.automatic, .ean13, .upcA, .code128, .qr]
        )
    }

    func testShortDigitsSkipRetailFormats() {
        XCTAssertEqual(
            BarcodePayloadBuilder.supportedFormats(for: "123456"),
            [.automatic, .code128, .qr]
        )
    }

    func testASCIITextSkipsRetailFormats() {
        XCTAssertEqual(
            BarcodePayloadBuilder.supportedFormats(for: "ORDER-12345"),
            [.automatic, .code128, .qr]
        )
    }

    func testNonASCIITextOnlyOffersQR() {
        XCTAssertEqual(
            BarcodePayloadBuilder.supportedFormats(for: "订单号 9527"),
            [.automatic, .qr]
        )
    }

    func testMixedTextIsNotSilentlyReducedToDigits() {
        // EAN-13 would strip "订单 " and leave 13 digits; cycling must not
        // offer it because that would silently discard the text.
        XCTAssertEqual(
            BarcodePayloadBuilder.supportedFormats(for: "订单 6901234567892"),
            [.automatic, .qr]
        )
    }

    func testWhitespacePaddingIsIgnored() {
        XCTAssertEqual(
            BarcodePayloadBuilder.supportedFormats(for: "  6901234567892 "),
            [.automatic, .ean13, .code128, .qr]
        )
    }
}
