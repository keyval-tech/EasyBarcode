import Vision
import XCTest
@testable import BarcodeKit

/// End-to-end proof that what we draw can be decoded back to the input.
final class VisionRoundTripTests: XCTestCase {
    func testEAN13RoundTrip() throws {
        try assertRoundTrip("6901234567892", format: .ean13)
    }

    func testUPCARoundTrip() throws {
        try assertRoundTrip("036000291452", format: .upcA)
    }

    func testCode128RoundTrip() throws {
        try assertRoundTrip("123456789012", format: .code128)
    }

    func testQRRoundTrip() throws {
        try assertRoundTrip("6901234567892", format: .qr)
    }

    func testLongCode128RoundTrip() throws {
        try assertRoundTrip("123456789012345678901234567890", format: .code128)
    }

    private func assertRoundTrip(_ digits: String, format: BarcodeFormat) throws {
        let payload = BarcodePayloadBuilder.make(from: digits, requested: format)
        XCTAssertTrue(payload.isValid, payload.error ?? "payload invalid")

        let image = try XCTUnwrap(BarcodeImageRenderer.image(for: payload, targetWidth: 1400))

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13, .upce, .code128, .qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let values = (request.results ?? []).compactMap(\.payloadStringValue)
        XCTAssertFalse(values.isEmpty, "Vision did not detect a barcode for \(format.displayName)")

        let matches = values.contains { value in
            value == payload.digits
                || value.hasSuffix(payload.digits)
                || payload.digits.hasSuffix(value)
        }
        XCTAssertTrue(matches, "decoded \(values) does not match \(payload.digits)")
    }
}
