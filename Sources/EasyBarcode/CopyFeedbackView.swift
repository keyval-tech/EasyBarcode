import AppKit
import QuartzCore

/// The shared Liquid Glass "已复制" feedback used by both the history cards
/// and the main preview. In forced light/dark modes the glass material is
/// covered by an opaque pill so the label stays readable.
final class CopyFeedbackView: NSGlassEffectView {
    private let label = NSTextField(labelWithString: "已复制")
    private let solidPill = NSView()
    private var resetWorkItem: DispatchWorkItem?

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        style = .regular
        cornerRadius = 15
        isHidden = true

        label.isBordered = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        solidPill.translatesAutoresizingMaskIntoConstraints = false
        solidPill.wantsLayer = true
        solidPill.layer?.cornerRadius = 15
        solidPill.layer?.backgroundColor = NSColor.white.cgColor
        solidPill.layer?.borderWidth = 1
        solidPill.layer?.borderColor = NSColor.black.withAlphaComponent(0.10).cgColor
        solidPill.isHidden = true
        content.addSubview(solidPill)
        content.addSubview(label)
        contentView = content

        NSLayoutConstraint.activate([
            solidPill.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            solidPill.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            solidPill.topAnchor.constraint(equalTo: content.topAnchor),
            solidPill.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
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
        // The pill always sits on a white image card. In system mode the
        // glass material adapts to the system and semantic colours work; in
        // forced modes tint the glass light and use dark text so the label
        // stays readable regardless of the system appearance.
        let pinned = AppSettings.appearanceMode != .system
        solidPill.isHidden = !pinned
        if pinned {
            label.textColor = NSColor(white: 0.12, alpha: 1)
        } else {
            label.textColor = .labelColor
        }
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
