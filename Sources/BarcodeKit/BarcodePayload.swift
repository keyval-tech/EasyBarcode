import Foundation

/// A validated, normalized barcode request.
public struct BarcodePayload: Sendable, Equatable {
    /// The raw text the user typed.
    public let input: String
    /// The content that should actually be encoded. For EAN-13/UPC-A this is
    /// the digit string including the (possibly corrected) check digit; for
    /// Code 128 / QR it is the user's text.
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
    /// Cap for numeric input (comfortably above any retail code).
    public static let maxNumericDigits = 64
    /// Cap for text input; keeps QR/Code 128 rendering fast.
    public static let maxTextLength = 256

    /// Mode-aware input cleaning: numeric symbologies strip everything that
    /// is not a digit, text symbologies keep the text (minus newlines).
    public static func sanitize(_ raw: String, for format: BarcodeFormat) -> String {
        switch format {
        case .ean13, .upcA:
            let digits = raw.filter { $0.isASCII && $0.isNumber }
            return String(digits.prefix(maxNumericDigits))
        case .automatic, .code128, .qr:
            let text = raw.filter { !$0.isNewline }
            return String(text.prefix(maxTextLength))
        }
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
        let text = sanitize(rawInput, for: requested)
        let format = BarcodeFormat.resolved(for: text, requested: requested)

        guard !text.isEmpty else {
            return BarcodePayload(input: rawInput, digits: "", format: format)
        }

        switch format {
        case .ean13:
            return makeEAN13(input: rawInput, digits: text)
        case .upcA:
            return makeUPCA(input: rawInput, digits: text)
        case .code128:
            guard text.canBeConverted(to: .ascii) else {
                return BarcodePayload(
                    input: rawInput,
                    digits: text,
                    format: .code128,
                    error: "Code 128 仅支持英文、数字与符号，中文请改用 QR"
                )
            }
            return BarcodePayload(input: rawInput, digits: text, format: .code128)
        case .qr:
            return BarcodePayload(input: rawInput, digits: text, format: .qr)
        case .automatic:
            return BarcodePayload(input: rawInput, digits: text, format: .code128)
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
