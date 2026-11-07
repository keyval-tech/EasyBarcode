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

    /// Formats that can be picked manually in the UI.
    public static let manualFormats: [BarcodeFormat] = [.ean13, .upcA, .code128, .qr]

    /// Picks the format used for an `automatic` request.
    ///
    /// EAN-13 is the common retail symbology for 12- and 13-digit numbers
    /// (12 digits means "body without check digit"). UPC-A is used for
    /// 11-digit bodies. Everything else falls back to Code 128, which can
    /// encode any digit string.
    public static func resolved(digitCount: Int, requested: BarcodeFormat) -> BarcodeFormat {
        guard requested == .automatic else { return requested }
        switch digitCount {
        case 11: return .upcA
        case 12, 13: return .ean13
        default: return .code128
        }
    }
}
