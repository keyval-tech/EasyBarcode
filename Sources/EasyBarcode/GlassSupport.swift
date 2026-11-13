import AppKit

/// Liquid Glass (`NSGlassEffectView`) only exists on macOS 26 and later.
/// Earlier systems use the opaque standard background that the 玻璃质感
/// switch already renders, so the rest of the UI is unchanged.
enum GlassSupport {
    static let isAvailable: Bool = {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }()

    /// Glass can only be shown when the system supports it and the appearance
    /// follows the system (the material ignores appearance overrides).
    static var isRenderable: Bool {
        isAvailable && AppSettings.appearanceMode == .system
    }
}

/// Hosts an `NSGlassEffectView` where available; renders nothing on earlier
/// systems so callers can keep one view hierarchy everywhere.
final class LiquidGlassBackdrop: NSView {
    private var effect: NSView?

    var cornerRadius: CGFloat = 0 {
        didSet { applyCornerRadius() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            effect = glass
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyCornerRadius() {
        if #available(macOS 26.0, *) {
            (effect as? NSGlassEffectView)?.cornerRadius = cornerRadius
        }
    }
}
