import Foundation

/// Turns a 13-digit EAN-13 string into its 95-module bit pattern.
///
/// The same 95-module pattern is used by UPC-A: UPC-A is an EAN-13 symbol
/// whose first digit is zero, so encoding `"0" + upcDigits` yields the
/// correct bars.
public enum EAN13Encoder {
    public static let moduleCount = 95

    /// Module ranges (start, length) that belong to the guard bars and are
    /// drawn taller than the data bars.
    public static let guardRanges: [Range<Int>] = [0..<3, 45..<50, 92..<95]

    public struct Symbol: Sendable, Equatable {
        /// 95 modules, `true` means a black bar.
        public let modules: [Bool]
        /// The 13 numeric digits, for human-readable text.
        public let digits: [Int]
    }

    private static let leftOdd = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011"
    ]

    private static let leftEven = [
        "0100111", "0110011", "0011011", "0100001", "0011101",
        "0111001", "0000101", "0010001", "0001001", "0010111"
    ]

    private static let right = [
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100"
    ]

    /// Parity pattern for the six left-hand digits, keyed by the first digit.
    private static let parityPatterns: [String] = [
        "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
        "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"
    ]

    public static func encode(ean13: String) -> Symbol? {
        guard ean13.count == 13, ean13.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }

        let characters = Array(ean13)
        let digits = characters.compactMap { $0.wholeNumberValue }
        guard digits.count == 13, let first = digits.first else { return nil }

        var bits = "101"
        let parity = Array(parityPatterns[first])

        for index in 0..<6 {
            let digit = digits[index + 1]
            bits += parity[index] == "L" ? leftOdd[digit] : leftEven[digit]
        }

        bits += "01010"

        for index in 0..<6 {
            bits += right[digits[index + 7]]
        }

        bits += "101"

        guard bits.count == moduleCount else { return nil }
        return Symbol(modules: bits.map { $0 == "1" }, digits: digits)
    }
}
