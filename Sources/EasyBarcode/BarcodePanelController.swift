import AppKit
import BarcodeKit

final class BarcodePanelController: NSObject, NSTextFieldDelegate {
    private(set) var window: BarcodeWindow
    private let view: GlassPanelView

    private var generatedPayload: BarcodePayload?
    private var lastGeneratedInput: String?
    private var lastGeneratedFormat: BarcodeFormat?
    private var statusResetWorkItem: DispatchWorkItem?
    private var historyWindowController: HistoryWindowController?

    var selectedFormat: BarcodeFormat {
        get { view.selectedFormat }
        set {
            applyFormat(newValue)
        }
    }

    override init() {
        let contentRect = NSRect(x: 0, y: 0, width: Theme.windowWidth, height: Theme.windowHeight)
        let window = BarcodeWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "EasyBarcode"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: Theme.minWindowWidth, height: Theme.minWindowHeight)
        // Utility app: windows must follow whatever Space is active, or a
        // hotkey summon on another Space finds nothing on screen.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.window = window
        view = GlassPanelView(frame: contentRect)
        super.init()

        window.contentView = view
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(glassSettingChanged),
            name: AppSettings.glassChangedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceSettingChanged),
            name: AppSettings.appearanceChangedNotification,
            object: nil
        )
        // Window-level override so the NSGlassEffectView material follows
        // the configured appearance instead of the system one.
        window.appearance = AppSettings.appearanceMode.nsAppearance
        restoreOrPositionWindow()
        configureInteractions()
        showInputState()
        updateHistoryTooltip()
    }

    @objc private func glassSettingChanged() {
        view.glassEnabled = AppSettings.useGlass
    }

    @objc private func appearanceSettingChanged() {
        window.appearance = AppSettings.appearanceMode.nsAppearance
    }
    // MARK: - Presentation

    func toggle() {
        if window.isVisible && !window.isMiniaturized {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        // macOS 14+ activation is cooperative: the old ignoringOtherApps flag
        // is a no-op, so use activateAllWindows and raise the window as well.
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        window.makeFirstResponder(view.textField)
        view.textField.selectText(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    var isVisible: Bool {
        window.isVisible && !window.isMiniaturized
    }

    /// Debug/verification helper used by `--demo`.
    func setText(_ text: String) {
        let clean = BarcodePayloadBuilder.sanitize(text, for: view.selectedFormat)
        if let editor = view.textField.currentEditor() as? NSTextView {
            editor.string = clean
            editor.selectedRange = NSRange(location: (clean as NSString).length, length: 0)
        }
        view.textField.stringValue = clean
        _ = generate(recordHistory: false)
    }

    // MARK: - Generate

    /// Switching modes re-applies the mode's input restriction to whatever
    /// is currently in the field (e.g. text typed for QR is stripped to its
    /// digits when the user moves to EAN-13).
    private func applyFormat(_ format: BarcodeFormat) {
        view.setFormat(format)
        view.textField.stringValue = BarcodePayloadBuilder.sanitize(
            view.textField.stringValue,
            for: format
        )
        showInputState()
    }

    /// Shows the resolved format and any validation message without drawing a
    /// barcode. Generation only happens on Return / history selection.
    private func showInputState() {
        view.copyFeedback.reset()
        statusResetWorkItem?.cancel()
        statusResetWorkItem = nil
        generatedPayload = nil
        lastGeneratedInput = nil
        lastGeneratedFormat = nil

        let result = BarcodePayloadBuilder.make(
            from: view.textField.stringValue,
            requested: view.selectedFormat
        )

        if result.isEmpty {
            view.update(
                payload: result,
                image: nil,
                status: "",
                warning: false,
                placeholder: "输入内容，按 ⏎ 生成条码"
            )
        } else if let error = result.error {
            view.update(
                payload: result,
                image: nil,
                status: error,
                warning: true,
                placeholder: "无法生成条码"
            )
        } else {
            view.update(
                payload: result,
                image: nil,
                status: statusText(for: result),
                warning: result.notice != nil,
                placeholder: "按 ⏎ 生成条码"
            )
        }
    }

    @discardableResult
    private func generate(recordHistory: Bool) -> Bool {
        statusResetWorkItem?.cancel()
        statusResetWorkItem = nil

        let raw = view.textField.stringValue
        let result = BarcodePayloadBuilder.make(from: raw, requested: view.selectedFormat)
        guard result.isValid else {
            view.update(
                payload: result,
                image: nil,
                status: result.error ?? "",
                warning: true,
                placeholder: "无法生成条码"
            )
            NSSound.beep()
            return false
        }
        guard let image = BarcodeImageRenderer.image(for: result, targetWidth: Theme.previewTargetWidth) else {
            NSSound.beep()
            return false
        }

        generatedPayload = result
        lastGeneratedInput = BarcodePayloadBuilder.sanitize(raw, for: view.selectedFormat)
        lastGeneratedFormat = view.selectedFormat
        view.update(
            payload: result,
            image: image,
            status: statusText(for: result),
            warning: result.notice != nil,
            placeholder: ""
        )

        if recordHistory {
            HistoryStore.shared.record(digits: result.digits, format: result.format)
            historyWindowController?.reload()
            updateHistoryTooltip()
        }

        return true
    }

    @objc func generateAndCopy() {
        guard generate(recordHistory: true) else { return }
        copyGeneratedImage(statusText: "已生成并复制图片")
    }

    private func statusText(for payload: BarcodePayload) -> String {
        guard payload.isValid else { return payload.error ?? "" }
        let unit = payload.format.acceptsArbitraryText ? "字符" : "位"
        var parts = [payload.format.displayName, "\(payload.digits.count) \(unit)"]
        if (payload.format == .ean13 || payload.format == .upcA), let last = payload.digits.last {
            parts.append("校验位 \(last)")
        }
        if let notice = payload.notice {
            parts.append(notice)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions

    @objc func copyImage() {
        copyGeneratedImage(statusText: "已复制图片")
    }

    private func copyGeneratedImage(statusText: String) {
        guard let payload = generatedPayload,
              let image = BarcodeImageRenderer.image(for: payload, targetWidth: Theme.outputTargetWidth),
              let png = BarcodeImageRenderer.pngData(for: payload, targetWidth: Theme.outputTargetWidth)
        else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        pasteboard.setString(payload.digits, forType: .string)

        view.copyFeedback.show()
        flashStatus(statusText)
    }

    // MARK: - History

    @objc func showHistoryWindow() {
        if historyWindowController == nil {
            let controller = HistoryWindowController(store: HistoryStore.shared)
            controller.onHistoryChanged = { [weak self] in
                self?.updateHistoryTooltip()
            }
            historyWindowController = controller
        }

        updateHistoryTooltip()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        historyWindowController?.showWindow(nil)
    }

    func toggleHistoryWindow() {
        if let historyWindow = historyWindowController?.window,
           historyWindow.isVisible,
           !historyWindow.isMiniaturized,
           historyWindow.isKeyWindow,
           NSApp.isActive {
            historyWindow.orderOut(nil)
        } else {
            showHistoryWindow()
        }
    }

    private func updateHistoryTooltip() {
        let count = HistoryStore.shared.entries.count
        let text = count == 0 ? "历史记录" : "历史记录（\(count)）"
        view.historyButton.toolTip = text
        view.historyButton.setAccessibilityLabel(text)
    }

    // MARK: - Status flash

    private func flashStatus(_ text: String) {
        statusResetWorkItem?.cancel()
        view.setStatus(text, color: .labelColor)
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreStatus()
        }
        statusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    private func restoreStatus() {
        guard let payload = generatedPayload else { return }
        view.setStatus(
            statusText(for: payload),
            color: payload.notice != nil ? .systemOrange : .secondaryLabelColor
        )
    }

    // MARK: - Wiring

    private func configureInteractions() {
        view.textField.delegate = self
        view.textField.target = self
        view.textField.action = #selector(generateAndCopy)

        view.formatButton.onSelect = { [weak self] format in
            self?.applyFormat(format)
        }

        view.historyButton.target = self
        view.historyButton.action = #selector(showHistoryWindow)

        view.previewView.onCopy = { [weak self] in
            self?.copyImage()
        }
    }

    private func restoreOrPositionWindow() {
        if !window.setFrameUsingName("EasyBarcodeMainWindow") {
            positionOnActiveScreen()
        } else if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            positionOnActiveScreen()
        }
        window.setFrameAutosaveName("EasyBarcodeMainWindow")
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        let size = window.frame.size
        let origin = NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded()
        )
        window.setFrameOrigin(origin)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        let raw = view.textField.stringValue
        let clean = BarcodePayloadBuilder.sanitize(raw, for: view.selectedFormat)

        if clean != raw {
            if let editor = view.textField.currentEditor() as? NSTextView {
                if editor.string != clean {
                    editor.string = clean
                }
                editor.selectedRange = NSRange(location: (clean as NSString).length, length: 0)
            } else {
                view.textField.stringValue = clean
            }
        }

        let current = BarcodePayloadBuilder.sanitize(view.textField.stringValue, for: view.selectedFormat)
        if generatedPayload != nil,
           current == lastGeneratedInput,
           view.selectedFormat == lastGeneratedFormat {
            return
        }

        showInputState()
    }
}
