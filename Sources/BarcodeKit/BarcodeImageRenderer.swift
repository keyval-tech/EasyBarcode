import AppKit
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Renders validated payloads to crisp, printer-quality CGImages.
///
/// EAN-13 / UPC-A are drawn module by module with Core Graphics so every bar
/// has exactly the same integer width. Code 128 and QR come from Core Image
/// and are scaled by an integer factor with nearest-neighbour sampling, which
/// keeps their modules perfectly aligned.
public enum BarcodeImageRenderer {
    private static let ciContext = CIContext(options: nil)

    public static func image(for payload: BarcodePayload, targetWidth: Int) -> CGImage? {
        image(for: payload, targetWidth: targetWidth, showsText: true)
    }

    public static func image(for payload: BarcodePayload, targetWidth: Int, showsText: Bool) -> CGImage? {
        guard payload.isValid else { return nil }
        let width = max(64, targetWidth)

        switch payload.format {
        case .ean13, .upcA:
            return renderRetail(payload, targetWidth: width)
        case .code128:
            return renderCode128(payload.digits, targetWidth: width, showsText: showsText)
        case .qr:
            return renderQR(payload.digits, targetWidth: width)
        case .automatic:
            return nil
        }
    }

    public static func pngData(for payload: BarcodePayload, targetWidth: Int) -> Data? {
        guard let image = image(for: payload, targetWidth: targetWidth) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: - EAN-13 / UPC-A

    private static func renderRetail(_ payload: BarcodePayload, targetWidth: Int) -> CGImage? {
        let isUPC = payload.format == .upcA
        let ean13Digits = isUPC ? "0" + payload.digits : payload.digits
        guard let symbol = EAN13Encoder.encode(ean13: ean13Digits) else { return nil }

        let quietModules = 11
        let totalModules = EAN13Encoder.moduleCount + quietModules * 2
        let moduleWidth = max(2, targetWidth / totalModules)
        let width = totalModules * moduleWidth

        let textBaseline = CGFloat(3 * moduleWidth)
        let barBottom = 12 * moduleWidth
        let barHeight = 45 * moduleWidth
        let barTop = barBottom + barHeight
        let height = barTop + 5 * moduleWidth

        guard let context = makeContext(width: width, height: height) else { return nil }

        context.setShouldAntialias(false)
        context.setFillColor(CGColor(gray: 0, alpha: 1))

        for (index, isBar) in symbol.modules.enumerated() where isBar {
            let x = (quietModules + index) * moduleWidth
            let isGuard = EAN13Encoder.guardRanges.contains { $0.contains(index) }
            let bottom = isGuard ? moduleWidth : barBottom
            let rect = CGRect(
                x: x,
                y: bottom,
                width: moduleWidth,
                height: barTop - bottom
            )
            context.fill(rect)
        }

        context.setShouldAntialias(true)
        let fontSize = CGFloat(8 * moduleWidth)
        let outsideLeftX = CGFloat(11 * moduleWidth) / 2
        let outsideRightX = CGFloat((quietModules + EAN13Encoder.moduleCount) * moduleWidth)
            + CGFloat(11 * moduleWidth) / 2

        if isUPC {
            // "0" + 12 digits: d1 sits in the left quiet zone, d2...d6 under
            // left cells 1...5, d7...d11 under right cells 0...4, d12 sits in
            // the right quiet zone.
            let digits = symbol.digits
            draw(digit: digits[1], centerX: outsideLeftX, baseline: textBaseline, fontSize: fontSize, in: context)
            for cell in 1...5 {
                draw(
                    digit: digits[cell + 1],
                    centerX: centerX(forLeftCell: cell, quiet: quietModules, moduleWidth: moduleWidth),
                    baseline: textBaseline,
                    fontSize: fontSize,
                    in: context
                )
            }
            for cell in 0...4 {
                draw(
                    digit: digits[cell + 7],
                    centerX: centerX(forRightCell: cell, quiet: quietModules, moduleWidth: moduleWidth),
                    baseline: textBaseline,
                    fontSize: fontSize,
                    in: context
                )
            }
            draw(digit: digits[12], centerX: outsideRightX, baseline: textBaseline, fontSize: fontSize, in: context)
        } else {
            let digits = symbol.digits
            draw(digit: digits[0], centerX: outsideLeftX, baseline: textBaseline, fontSize: fontSize, in: context)
            for cell in 0..<6 {
                draw(
                    digit: digits[cell + 1],
                    centerX: centerX(forLeftCell: cell, quiet: quietModules, moduleWidth: moduleWidth),
                    baseline: textBaseline,
                    fontSize: fontSize,
                    in: context
                )
            }
            for cell in 0..<6 {
                draw(
                    digit: digits[cell + 7],
                    centerX: centerX(forRightCell: cell, quiet: quietModules, moduleWidth: moduleWidth),
                    baseline: textBaseline,
                    fontSize: fontSize,
                    in: context
                )
            }
        }

        return context.makeImage()
    }

    private static func centerX(forLeftCell cell: Int, quiet: Int, moduleWidth: Int) -> CGFloat {
        let moduleCenter = CGFloat(3 + cell * 7) + 3.5
        return (CGFloat(quiet) + moduleCenter) * CGFloat(moduleWidth)
    }

    private static func centerX(forRightCell cell: Int, quiet: Int, moduleWidth: Int) -> CGFloat {
        let moduleCenter = CGFloat(50 + cell * 7) + 3.5
        return (CGFloat(quiet) + moduleCenter) * CGFloat(moduleWidth)
    }

    private static func draw(
        digit: Int,
        centerX: CGFloat,
        baseline: CGFloat,
        fontSize: CGFloat,
        in context: CGContext
    ) {
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(digit), attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        context.textPosition = CGPoint(x: centerX - textWidth / 2, y: baseline)
        CTLineDraw(line, context)
    }

    // MARK: - Code 128

    private static func renderCode128(_ digits: String, targetWidth: Int, showsText: Bool) -> CGImage? {
        guard let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(digits.data(using: .ascii), forKey: "inputMessage")
        filter.setValue(10, forKey: "inputQuietSpace")
        filter.setValue(60, forKey: "inputBarcodeHeight")

        guard let output = filter.outputImage,
              !output.extent.isEmpty,
              !output.extent.isInfinite,
              !output.extent.isNull
        else {
            return nil
        }
        guard let base = ciContext.createCGImage(output, from: output.extent) else { return nil }

        let scale = max(1, Int((Double(targetWidth) / Double(base.width)).rounded()))
        let barWidth = base.width * scale
        let barHeight = base.height * scale

        let idealFontSize = CGFloat(barHeight) * 0.16
        let maxFontSize = CGFloat(barWidth) * 0.86 / (CGFloat(max(1, digits.count)) * 0.62)
        let fontSize = max(12, min(idealFontSize, maxFontSize))
        let textHeight = showsText ? Int(fontSize * 1.35) : 0
        let height = barHeight + textHeight

        guard let context = makeContext(width: barWidth, height: height) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(
            base,
            in: CGRect(x: 0, y: textHeight, width: barWidth, height: barHeight)
        )

        if showsText {
            context.setShouldAntialias(true)
            drawTextCentered(
                digits,
                centerX: CGFloat(barWidth) / 2,
                baseline: fontSize * 0.25,
                fontSize: fontSize,
                in: context
            )
        }

        return context.makeImage()
    }

    // MARK: - QR

    private static func renderQR(_ digits: String, targetWidth: Int) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(digits.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage,
              !output.extent.isEmpty,
              !output.extent.isInfinite,
              !output.extent.isNull
        else {
            return nil
        }
        guard let base = ciContext.createCGImage(output, from: output.extent) else { return nil }

        let scale = max(1, Int((Double(targetWidth) / Double(base.width)).rounded()))
        let qrSize = base.width * scale
        let margin = max(8, qrSize / 10)
        let size = qrSize + margin * 2

        guard let context = makeContext(width: size, height: size) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(
            base,
            in: CGRect(x: margin, y: margin, width: qrSize, height: qrSize)
        )
        return context.makeImage()
    }

    // MARK: - Shared drawing

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    private static func drawTextCentered(
        _ string: String,
        centerX: CGFloat,
        baseline: CGFloat,
        fontSize: CGFloat,
        in context: CGContext
    ) {
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        context.textPosition = CGPoint(x: centerX - textWidth / 2, y: baseline)
        CTLineDraw(line, context)
    }
}
