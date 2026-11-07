import AppKit
import QuartzCore

/// The shared Liquid Glass "已复制" feedback used by both the history cards
/// and the main preview.
final class CopyFeedbackView: NSGlassEffectView {
    private let label = NSTextField(labelWithString: "已复制")
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
        content.addSubview(label)
        contentView = content

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
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
