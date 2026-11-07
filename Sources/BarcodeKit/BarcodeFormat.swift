import Foundation

/// The barcode symbologies supported by EasyBarcode.
public enum BarcodeFormat: String, CaseIterable, Codable, Sendable {
    case automatic
    case ean13
    case upcA
    case code128
    case qr

    public var displayName: String {
        switch self {
        case .automatic: return "自动"
        case .ean13: return "EAN-13"
        case .upcA: return "UPC-A"
        case .code128: return "Code 128"
        case .qr: return "QR"
        }
    }

    /// Prefix used for saved file names, e.g. `EAN13-6901234567892.png`.
    public var filePrefix: String {
        switch self {
        case .automatic: return "Barcode"
        case .ean13: return "EAN13"
        case .upcA: return "UPCA"
        case .code128: return "Code128"
        case .qr: return "QR"
        }
    }

    public var isLinear: Bool {
        switch self {
        case .ean13, .upcA, .code128: return true
        case .automatic, .qr: return false
        }
    }

    /// EAN-13 / UPC-A are numeric-only symbologies; everything else accepts
    /// arbitrary text.
    public var acceptsArbitraryText: Bool {
        switch self {
        case .automatic, .code128, .qr: return true
        case .ean13, .upcA: return false
        }
    }

    /// Input placeholder matching the mode's restriction.
    public var inputPlaceholder: String {
        switch self {
        case .automatic: return "输入数字或文本…"
        case .ean13: return "输入 12-13 位数字…"
        case .upcA: return "输入 11-12 位数字…"
        case .code128: return "输入数字或文本…"
        case .qr: return "输入任意文本…"
        }
    }

    /// Formats that can be picked manually in the UI.
    public static let manualFormats: [BarcodeFormat] = [.ean13, .upcA, .code128, .qr]

    /// Picks the symbology used for an `automatic` request.
    ///
    /// Pure digits keep the retail rules (11 → UPC-A, 12/13 → EAN-13,
    /// otherwise Code 128). Text falls back to Code 128 when it is pure
    /// ASCII and to QR when it contains characters Code 128 cannot carry
    /// (e.g. Chinese).
    public static func resolved(for text: String, requested: BarcodeFormat) -> BarcodeFormat {
        guard requested == .automatic else { return requested }

        let isAllDigits = !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
        if isAllDigits {
            switch text.count {
            case 11: return .upcA
            case 12, 13: return .ean13
            default: return .code128
            }
        }
        return text.canBeConverted(to: .ascii) ? .code128 : .qr
    }
}
