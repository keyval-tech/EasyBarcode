import AppKit
import QuartzCore

/// The shared "已复制" feedback used by both the history cards and the main
/// preview. It sits on an always-white image card: on macOS 26 in
/// follow-system mode it is a Liquid Glass capsule, otherwise an opaque white
/// pill with dark text (readable regardless of the system appearance).
final class CopyFeedbackView: NSView {
    private let glass = LiquidGlassBackdrop()
    private let solidPill = NSView()
    private let label = NSTextField(labelWithString: "已复制")
    private var resetWorkItem: DispatchWorkItem?

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 15
        isHidden = true

        glass.cornerRadius = 15
        glass.translatesAutoresizingMaskIntoConstraints = false

        solidPill.translatesAutoresizingMaskIntoConstraints = false
        solidPill.wantsLayer = true
        solidPill.layer?.cornerRadius = 15
        solidPill.layer?.backgroundColor = NSColor.white.cgColor
        solidPill.layer?.borderWidth = 1
        solidPill.layer?.borderColor = NSColor.black.withAlphaComponent(0.10).cgColor

        label.isBordered = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glass)
        addSubview(solidPill)
        addSubview(label)

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            solidPill.leadingAnchor.constraint(equalTo: leadingAnchor),
            solidPill.trailingAnchor.constraint(equalTo: trailingAnchor),
            solidPill.topAnchor.constraint(equalTo: topAnchor),
            solidPill.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        refreshTint()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshTint),
            name: AppSettings.appearanceChangedNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 76, height: 30)
    }

    /// Feedback is purely visual; clicks pass through to the barcode below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    @objc private func refreshTint() {
        let useGlass = GlassSupport.isRenderable
        glass.isHidden = !useGlass
        solidPill.isHidden = useGlass
        label.textColor = useGlass ? .labelColor : NSColor(white: 0.12, alpha: 1)
    }

    func show() {
        resetWorkItem?.cancel()
        isHidden = false
        alphaValue = 0
        layer?.removeAnimation(forKey: "copyFeedbackScale")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.0
        scale.duration = 0.18
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(scale, forKey: "copyFeedbackScale")
        layer?.setAffineTransform(.identity)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                self?.isHidden = true
                self?.alphaValue = 1
                self?.layer?.removeAnimation(forKey: "copyFeedbackScale")
            }
        }
        resetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }

    func reset() {
        resetWorkItem?.cancel()
        resetWorkItem = nil
        isHidden = true
        alphaValue = 1
        layer?.removeAnimation(forKey: "copyFeedbackScale")
    }
}
