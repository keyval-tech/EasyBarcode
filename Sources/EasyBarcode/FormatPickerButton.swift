import AppKit
import BarcodeKit

/// A compact "自动 ▾" chip that opens the format menu.
final class FormatPickerButton: NSButton {
    var onSelect: ((BarcodeFormat) -> Void)?

    private(set) var selectedFormat: BarcodeFormat = .automatic
    private let formatMenu = NSMenu()
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        isBordered = false
        title = "自动"
        font = .systemFont(ofSize: 11, weight: .medium)
        contentTintColor = .secondaryLabelColor
        alignment = .center
        imagePosition = .imageTrailing
        imageHugsTitle = true
        imageScaling = .scaleProportionallyDown
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            image = chevron.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
            )
        }

        target = self
        action = #selector(showMenu)
        toolTip = "选择条码格式"
        setAccessibilityLabel("条码格式")

        wantsLayer = true
        layer?.cornerRadius = 6
        buildMenu()
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setFormat(_ format: BarcodeFormat) {
        selectedFormat = format
        updateAppearance()
        updateMenuStates()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    private func updateAppearance() {
        title = selectedFormat.displayName
        withEffectiveAppearance {
            layer?.backgroundColor = NSColor.labelColor
                .withAlphaComponent(isHovered ? 0.10 : 0.06)
                .cgColor
        }
    }

    private func buildMenu() {
        formatMenu.autoenablesItems = false
        for format in BarcodeFormat.allCases {
            let item = NSMenuItem(
                title: format.displayName,
                action: #selector(selectFormat(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = format.rawValue
            formatMenu.addItem(item)
        }
        updateMenuStates()
    }

    private func updateMenuStates() {
        for item in formatMenu.items {
            guard let raw = item.representedObject as? String,
                  let format = BarcodeFormat(rawValue: raw) else { continue }
            item.state = format == selectedFormat ? .on : .off
        }
    }

    @objc private func showMenu() {
        updateMenuStates()
        formatMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: bounds.height + 4),
            in: self
        )
    }

    @objc private func selectFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = BarcodeFormat(rawValue: raw) else { return }
        setFormat(format)
        onSelect?(format)
    }
}
