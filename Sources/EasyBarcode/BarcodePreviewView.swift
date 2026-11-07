import AppKit

/// Draws the barcode image on the white preview card and supports dragging it
/// out to other applications.
final class BarcodePreviewView: NSView, NSDraggingSource {
    var cgImage: CGImage? {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var onCopy: (() -> Void)?

    private let imageInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    private var didDrag = false

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let cgImage else { return }

        let available = NSRect(
            x: bounds.minX + imageInsets.left,
            y: bounds.minY + imageInsets.top,
            width: bounds.width - imageInsets.left - imageInsets.right,
            height: bounds.height - imageInsets.top - imageInsets.bottom
        )
        guard available.width > 1, available.height > 1 else { return }

        let imageAspect = CGFloat(cgImage.width) / CGFloat(cgImage.height)
        var drawRect = available
        if available.width / available.height > imageAspect {
            drawRect.size.width = available.height * imageAspect
            drawRect.origin.x = available.midX - drawRect.width / 2
        } else {
            drawRect.size.height = available.width / imageAspect
            drawRect.origin.y = available.midY - drawRect.height / 2
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        image.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag, cgImage != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onCopy?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let cgImage else { return }
        didDrag = true
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2)
        )
        let item = NSDraggingItem(pasteboardWriter: image)
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func resetCursorRects() {
        if cgImage != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}
