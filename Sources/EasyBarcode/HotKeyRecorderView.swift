import AppKit

/// A click-to-record shortcut field.
final class HotKeyRecorderView: NSView {
    static private(set) var isRecordingAny = false
    var onChange: ((HotKeyConfig) -> Bool)?

    private(set) var config: HotKeyConfig
    private let label = NSTextField(labelWithString: "")
    private var monitor: Any?
    private var isRecording = false {
        didSet { updateAppearance() }
    }

    init(config: HotKeyConfig) {
        self.config = config
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        toolTip = "点击后按下新的快捷键；Delete 恢复默认，Esc 取消"
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopMonitor()
        if isRecording {
            Self.isRecordingAny = false
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(config: HotKeyConfig) {
        self.config = config
        updateAppearance()
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        Self.isRecordingAny = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            return self.handleKey(event)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Esc
            finishRecording()
            return nil
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            apply(.default)
            return nil
        }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let required = flags.intersection([.command, .option, .control])
        guard !required.isEmpty else {
            NSSound.beep()
            return nil
        }

        apply(HotKeyConfig(keyCode: UInt32(event.keyCode), modifiers: flags))
        return nil
    }

    private func apply(_ candidate: HotKeyConfig) {
        if onChange?(candidate) == true {
            config = candidate
            updateAppearance()
        } else {
            NSSound.beep()
        }
        finishRecording()
    }

    private func finishRecording() {
        isRecording = false
        Self.isRecordingAny = false
        stopMonitor()
    }

    private func stopMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func updateAppearance() {
        if isRecording {
            label.stringValue = "按下快捷键…"
            label.textColor = .controlAccentColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            label.stringValue = config.displayString
            label.textColor = .labelColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
