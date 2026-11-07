import AppKit

/// Multi-line note editor for a history card. An NSTextView (not NSTextField)
/// so Return inserts a newline instead of ending editing.
final class NoteEditorView: NSView, NSTextViewDelegate {
    var onTextChange: ((String) -> Void)?

    private let scrollView = NSScrollView()
    private let textView = PlaceholderTextView()
    private var isUpdating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 11)
        textView.textColor = .secondaryLabelColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.placeholder = "添加备注…"
        textView.delegate = self

        scrollView.documentView = textView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setText(_ text: String) {
        isUpdating = true
        textView.string = text
        textView.needsDisplay = true
        isUpdating = false
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        textView.needsDisplay = true
        onTextChange?(textView.string)
    }
}

/// Draws a placeholder over an empty text view without stealing clicks.
final class PlaceholderTextView: NSTextView {
    var placeholder: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let rect = NSRect(
            x: textContainerInset.width,
            y: textContainerInset.height,
            width: max(0, bounds.width - textContainerInset.width * 2),
            height: 18
        )
        (placeholder as NSString).draw(in: rect, withAttributes: attributes)
    }
}
