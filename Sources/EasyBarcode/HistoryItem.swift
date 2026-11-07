import AppKit
import BarcodeKit

/// A collection-view card: barcode image first, with digits / format / time
/// and an editable note as secondary information.
final class HistoryItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryItem")
    static let itemHeight: CGFloat = 240

    var onCopy: (() -> Bool)?
    var onDelete: (() -> Void)?
    var onNoteChange: ((String) -> Void)?

    private let cardView = HistoryCardView()
    private let imageContainer = ClickableImageView()
    private let digitsLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let noteEditor = NoteEditorView()
    private let deleteButton = NSButton()
    private let copyFeedbackView = CopyFeedbackView()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static var imageCache: [String: NSImage] = [:]

    static func clearCache() {
        imageCache.removeAll()
    }

    override func loadView() {
        cardView.onAppearanceChange = { [weak self] in
            self?.updateAppearance()
        }
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 10
        cardView.layer?.borderWidth = 1
        cardView.layer?.masksToBounds = true
        view = cardView

        imageContainer.wantsLayer = true
        imageContainer.layer?.backgroundColor = NSColor.white.cgColor
        imageContainer.layer?.cornerRadius = 6
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.borderWidth = 1
        imageContainer.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.onClick = { [weak self] in
            guard let self else { return }
            if self.onCopy?() == true {
                self.showCopiedFeedback()
            }
        }

        digitsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        digitsLabel.textColor = .labelColor
        digitsLabel.lineBreakMode = .byTruncatingMiddle
        digitsLabel.usesSingleLineMode = true
        digitsLabel.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.usesSingleLineMode = true
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        noteEditor.translatesAutoresizingMaskIntoConstraints = false
        noteEditor.toolTip = "点击编辑备注（支持多行）"
        noteEditor.onTextChange = { [weak self] text in
            self?.onNoteChange?(text)
        }

        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        deleteButton.imageScaling = .scaleProportionallyDown
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        deleteButton.toolTip = "删除这条记录"
        deleteButton.setAccessibilityLabel("删除这条记录")
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        copyFeedbackView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(copyFeedbackView)

        cardView.addSubview(imageContainer)
        cardView.addSubview(digitsLabel)
        cardView.addSubview(metaLabel)
        cardView.addSubview(noteEditor)
        cardView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            imageContainer.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            imageContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10),
            imageContainer.widthAnchor.constraint(equalToConstant: 230),
            imageContainer.heightAnchor.constraint(equalToConstant: 120),

            digitsLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            digitsLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            digitsLabel.topAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: 8),

            metaLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            metaLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            metaLabel.topAnchor.constraint(equalTo: digitsLabel.bottomAnchor, constant: 2),

            noteEditor.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            noteEditor.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            noteEditor.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 4),
            noteEditor.heightAnchor.constraint(equalToConstant: 56),

            deleteButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            deleteButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            deleteButton.widthAnchor.constraint(equalToConstant: 20),
            deleteButton.heightAnchor.constraint(equalToConstant: 20),

            copyFeedbackView.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            copyFeedbackView.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
            copyFeedbackView.widthAnchor.constraint(equalToConstant: 76),
            copyFeedbackView.heightAnchor.constraint(equalToConstant: 30)
        ])

        updateAppearance()
    }

    func configure(with entry: HistoryEntry) {
        copyFeedbackView.reset()

        digitsLabel.stringValue = entry.digits
        metaLabel.stringValue = "\(entry.format.displayName) · \(Self.dateFormatter.string(from: entry.createdAt))"
        noteEditor.setText(entry.note ?? "")
        imageContainer.imageView.image = Self.image(for: entry)
        updateAppearance()
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    private func showCopiedFeedback() {
        copyFeedbackView.show()
    }

    private func updateAppearance() {
        cardView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        cardView.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private static func image(for entry: HistoryEntry) -> NSImage? {
        let key = entry.imagePath ?? "\(entry.format.rawValue):\(entry.digits)"
        if let cached = imageCache[key] {
            return cached
        }

        if let path = entry.imagePath, let image = NSImage(contentsOfFile: path) {
            imageCache[key] = image
            return image
        }

        let payload = BarcodePayloadBuilder.make(from: entry.digits, requested: entry.format)
        guard payload.isValid,
              let cgImage = BarcodeImageRenderer.image(for: payload, targetWidth: 480) else {
            return nil
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2)
        )
        imageCache[key] = image
        return image
    }
}

/// Clicking anywhere on the barcode image copies it.
final class ClickableImageView: NSView {
    let imageView = NSImageView()
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class HistoryCardView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
