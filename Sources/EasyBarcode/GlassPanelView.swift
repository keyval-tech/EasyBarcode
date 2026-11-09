import AppKit
import BarcodeKit

/// The Liquid Glass surface and every control inside it.
///
/// `NSGlassEffectView` only guarantees that its `contentView` is hosted inside
/// the glass, so the complete UI lives in that one subtree.
final class GlassPanelView: NSView {
    let glass = NSGlassEffectView()
    let content = NSView()

    /// Toggled from 设置 › 外观; off renders an opaque standard background.
    var glassEnabled: Bool = true {
        didSet {
            guard glassEnabled != oldValue else { return }
            applyGlassMode()
        }
    }

    let solidBackground = SolidBackgroundView()

    @objc private func applyGlassMode() {
        // The glass material follows the SYSTEM appearance and ignores
        // NSApp/window/view overrides, so a forced light/dark would render
        // mismatched text and background. Fall back to the opaque standard
        // look whenever the user pins the appearance.
        let useGlassNow = glassEnabled && AppSettings.appearanceMode == .system
        glass.isHidden = !useGlassNow
        solidBackground.isHidden = useGlassNow
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyGlassMode()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glassEnabled = AppSettings.useGlass
        build()
        applyGlassMode()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyGlassMode),
            name: AppSettings.appearanceChangedNotification,
            object: nil
        )
    }

    let textField = NSTextField()
    let formatButton = FormatPickerButton()
    let statusLabel = NSTextField(labelWithString: "")
    let previewCard = NSView()
    let previewView = BarcodePreviewView()
    let placeholderLabel = NSTextField(labelWithString: "输入数字，按 ⏎ 生成条码")
    let hintLabel = NSTextField(labelWithString: "⏎ / 点击图片复制   ⌘W 关闭")
    let historyButton = NSButton()
    let copyFeedback = CopyFeedbackView()
    let buttonContainer = NSGlassEffectContainerView()
    let buttonStack = NSStackView()

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func build() {
        wantsLayer = true

        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.style = .regular
        glass.cornerRadius = 0
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        solidBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(solidBackground)
        NSLayoutConstraint.activate([
            solidBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidBackground.topAnchor.constraint(equalTo: topAnchor),
            solidBackground.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        content.translatesAutoresizingMaskIntoConstraints = false
        // Content sits as a sibling ABOVE the glass (not inside
        // glass.contentView) so the glass can be hidden entirely without
        // hiding the UI in non-glass mode.
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        configureTextField()
        configureFormatButton()
        configureStatusLabel()
        configurePreview()
        configureHint()
        configureButtons()
        layoutContent()
    }

    private func configureTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        textField.textColor = .labelColor
        textField.alignment = .left
        textField.usesSingleLineMode = true
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        updatePlaceholder(for: .automatic)
        content.addSubview(textField)
    }

    private func configureFormatButton() {
        formatButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(formatButton)
    }

    func updatePlaceholder(for format: BarcodeFormat) {
        textField.placeholderAttributedString = NSAttributedString(
            string: format.inputPlaceholder,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular),
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
    }

    private func configureStatusLabel() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.usesSingleLineMode = true
        content.addSubview(statusLabel)
    }

    private func configurePreview() {
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.wantsLayer = true
        previewCard.layer?.backgroundColor = NSColor.white.cgColor
        previewCard.layer?.cornerRadius = Theme.previewCornerRadius
        previewCard.layer?.masksToBounds = true
        previewCard.layer?.borderWidth = 1
        previewCard.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        content.addSubview(previewCard)

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.isHidden = true
        previewCard.addSubview(previewView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alignment = .center
        placeholderLabel.font = .systemFont(ofSize: 13)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.maximumNumberOfLines = 2
        placeholderLabel.lineBreakMode = .byWordWrapping
        previewCard.addSubview(placeholderLabel)

        copyFeedback.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(copyFeedback)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: previewCard.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor),

            placeholderLabel.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: previewCard.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: previewCard.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: previewCard.trailingAnchor, constant: -16),

            copyFeedback.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            copyFeedback.centerYAnchor.constraint(equalTo: previewCard.centerYAnchor),
            copyFeedback.widthAnchor.constraint(equalToConstant: 76),
            copyFeedback.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func configureHint() {
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        content.addSubview(hintLabel)
    }

    private func configureButtons() {
        configureGlassButton(
            historyButton,
            symbol: "clock.arrow.circlepath",
            label: "历史记录",
            prominence: .secondary
        )
        historyButton.isEnabled = true

        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        buttonStack.spacing = 8
        buttonStack.addArrangedSubview(historyButton)

        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.spacing = 0
        buttonContainer.contentView = buttonStack
        content.addSubview(buttonContainer)

        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor),
            buttonStack.topAnchor.constraint(equalTo: buttonContainer.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor),
            buttonContainer.widthAnchor.constraint(equalToConstant: 38),
            buttonContainer.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func configureGlassButton(
        _ button: NSButton,
        symbol: String,
        label: String,
        prominence: NSTintProminence
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .glass
        button.isBordered = true
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.tintProminence = prominence
        button.isEnabled = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 38),
            button.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func layoutContent() {
        let padding = Theme.contentPadding

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: padding),
            textField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),
            textField.topAnchor.constraint(equalTo: content.topAnchor, constant: Theme.contentTopInset),
            textField.heightAnchor.constraint(equalToConstant: 34),

            formatButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),
            formatButton.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 5),
            formatButton.heightAnchor.constraint(equalToConstant: 22),
            formatButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: padding),
            statusLabel.centerYAnchor.constraint(equalTo: formatButton.centerYAnchor),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: formatButton.leadingAnchor, constant: -8),

            previewCard.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: padding),
            previewCard.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),
            previewCard.topAnchor.constraint(equalTo: formatButton.bottomAnchor, constant: 10),
            previewCard.bottomAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: -16),
            previewCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),

            hintLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: padding),
            hintLabel.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttonContainer.leadingAnchor, constant: -10),

            buttonContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),
            buttonContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
    }

    // MARK: - State

    var selectedFormat: BarcodeFormat {
        formatButton.selectedFormat
    }

    func setFormat(_ format: BarcodeFormat) {
        formatButton.setFormat(format)
        updatePlaceholder(for: format)
    }

    func update(payload: BarcodePayload?, image: CGImage?, status: String, warning: Bool, placeholder: String) {
        previewView.cgImage = image
        previewView.isHidden = image == nil

        if image == nil {
            placeholderLabel.isHidden = false
            placeholderLabel.stringValue = placeholder
            placeholderLabel.textColor = payload?.error != nil
                ? .systemOrange
                : NSColor(white: 0.45, alpha: 1)
        } else {
            placeholderLabel.isHidden = true
        }

        statusLabel.stringValue = status
        statusLabel.textColor = warning ? .systemOrange : .secondaryLabelColor
    }

    func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }
}


/// Opaque stand-in for the glass surface when the user pins light/dark. It
/// resolves `windowBackgroundColor` in `updateLayer`, so the colour always
/// matches the current effective appearance (a `cgColor` captured at init
/// would keep the old appearance's colour).
final class SolidBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
