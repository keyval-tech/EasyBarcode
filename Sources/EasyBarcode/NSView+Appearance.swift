import AppKit

extension NSView {
    /// Resolves dynamic `NSColor`s in this view's effective appearance before
    /// they are snapshotted into a layer. A bare `NSColor.cgColor` outside a
    /// drawing context resolves against the default (light) appearance, which
    /// left light backgrounds behind dark-mode text.
    func withEffectiveAppearance(_ body: () -> Void) {
        effectiveAppearance.performAsCurrentDrawingAppearance(body)
    }
}
