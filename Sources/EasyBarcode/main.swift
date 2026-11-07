import AppKit
import BarcodeKit
import Foundation

private func runCLI() -> Bool {
    let arguments = CommandLine.arguments
    guard let renderIndex = arguments.firstIndex(of: "--render"), arguments.count > renderIndex + 1 else {
        return false
    }

    let digits = arguments[renderIndex + 1]

    var format = BarcodeFormat.automatic
    if let formatIndex = arguments.firstIndex(of: "--format"), arguments.count > formatIndex + 1 {
        switch arguments[formatIndex + 1].lowercased() {
        case "ean13", "ean-13": format = .ean13
        case "upca", "upc-a": format = .upcA
        case "code128", "code-128": format = .code128
        case "qr": format = .qr
        default: format = .automatic
        }
    }

    var width = 1600
    if let widthIndex = arguments.firstIndex(of: "--width"),
       arguments.count > widthIndex + 1,
       let value = Int(arguments[widthIndex + 1]) {
        width = value
    }

    let output: String
    if let outIndex = arguments.firstIndex(of: "--out"), arguments.count > outIndex + 1 {
        output = arguments[outIndex + 1]
    } else {
        output = "barcode-\(digits).png"
    }

    let payload = BarcodePayloadBuilder.make(from: digits, requested: format)
    guard payload.isValid else {
        FileHandle.standardError.write(Data("error: \(payload.error ?? "无效输入")\n".utf8))
        exit(1)
    }

    guard let data = BarcodeImageRenderer.pngData(for: payload, targetWidth: width) else {
        FileHandle.standardError.write(Data("error: 无法生成条码图片\n".utf8))
        exit(1)
    }

    do {
        try data.write(to: URL(fileURLWithPath: output))
        print("\(payload.format.displayName)  \(payload.digits)  ->  \(output)")
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

    return true
}

if runCLI() {
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
