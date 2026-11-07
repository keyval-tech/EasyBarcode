import Foundation

/// A validated, normalized barcode request.
public struct BarcodePayload: Sendable, Equatable {
    /// The raw text the user typed.
    public let input: String
    /// The digits that should actually be encoded. For EAN-13/UPC-A this
    /// includes the (possibly corrected) check digit.
    public let digits: String
    /// The symbology that will be used.
    public let format: BarcodeFormat
    /// A non-fatal message, e.g. a corrected check digit.
    public let notice: String?
    /// A fatal input problem for the selected format.
    public let error: String?

    public var isEmpty: Bool {
        digits.isEmpty && error == nil
    }

    public var isValid: Bool {
        error == nil && !digits.isEmpty
    }

    public init(input: String, digits: String, format: BarcodeFormat, notice: String? = nil, error: String? = nil) {
        self.input = input
        self.digits = digits
        self.format = format
        self.notice = notice
        self.error = error
    }
}

public enum BarcodePayloadBuilder {
    /// Longest input we accept. Comfortably above any real-world retail code
    /// while keeping Code 128 / QR generation fast.
    public static let maxDigits = 64

    /// Strips everything that is not an ASCII digit and caps the length.
    public static func sanitize(_ raw: String) -> String {
        let digits = raw.filter { $0.isASCII && $0.isNumber }
        return String(digits.prefix(maxDigits))
    }

    /// EAN-13 check digit over a 12-digit body.
    public static func eanCheckDigit(body: String) -> Int {
        var sum = 0
        for (index, character) in body.enumerated() {
            guard let digit = character.wholeNumberValue else { continue }
            sum += index % 2 == 0 ? digit : digit * 3
        }
        return (10 - sum % 10) % 10
    }

    /// UPC-A check digit over an 11-digit body.
    public static func upcCheckDigit(body: String) -> Int {
        eanCheckDigit(body: "0" + body)
    }

    public static func make(from rawInput: String, requested: BarcodeFormat) -> BarcodePayload {
        let digits = sanitize(rawInput)
        let format = BarcodeFormat.resolved(digitCount: digits.count, requested: requested)

        guard !digits.isEmpty else {
            return BarcodePayload(input: rawInput, digits: "", format: format)
        }

        switch format {
        case .ean13:
            return makeEAN13(input: rawInput, digits: digits)
        case .upcA:
            return makeUPCA(input: rawInput, digits: digits)
        case .code128:
            return BarcodePayload(input: rawInput, digits: digits, format: .code128)
        case .qr:
            return BarcodePayload(input: rawInput, digits: digits, format: .qr)
        case .automatic:
            return BarcodePayload(input: rawInput, digits: digits, format: .code128)
        }
    }

    private static func makeEAN13(input: String, digits: String) -> BarcodePayload {
        switch digits.count {
        case 12:
            let check = eanCheckDigit(body: digits)
            return BarcodePayload(input: input, digits: digits + String(check), format: .ean13)
        case 13:
            let body = String(digits.prefix(12))
            let expected = eanCheckDigit(body: body)
            let actual = digits.last!.wholeNumberValue ?? -1
            if actual == expected {
                return BarcodePayload(input: input, digits: digits, format: .ean13)
            }
            return BarcodePayload(
                input: input,
                digits: body + String(expected),
                format: .ean13,
                notice: "校验位应为 \(expected)，已自动修正"
            )
        default:
            return BarcodePayload(
                input: input,
                digits: digits,
                format: .ean13,
                error: "EAN-13 需要 12 或 13 位数字"
            )
        }
    }

    private static func makeUPCA(input: String, digits: String) -> BarcodePayload {
        switch digits.count {
        case 11:
            let check = upcCheckDigit(body: digits)
            return BarcodePayload(input: input, digits: digits + String(check), format: .upcA)
        case 12:
            let body = String(digits.prefix(11))
            let expected = upcCheckDigit(body: body)
            let actual = digits.last!.wholeNumberValue ?? -1
            if actual == expected {
                return BarcodePayload(input: input, digits: digits, format: .upcA)
            }
            return BarcodePayload(
                input: input,
                digits: body + String(expected),
                format: .upcA,
                notice: "校验位应为 \(expected)，已自动修正"
            )
        default:
            return BarcodePayload(
                input: input,
                digits: digits,
                format: .upcA,
                error: "UPC-A 需要 11 或 12 位数字"
            )
        }
    }
}
