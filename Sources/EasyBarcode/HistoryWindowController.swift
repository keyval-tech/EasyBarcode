import AppKit
import BarcodeKit

/// A normal window showing generated barcodes as an image-first grid.
final class HistoryWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSWindowDelegate {
    var onHistoryChanged: (() -> Void)?

    private let store: HistoryStore
    private let collectionView = NSCollectionView()
    private var contentView: HistoryContentView!
    private var flowLayout: NSCollectionViewFlowLayout!
    private var statusResetWorkItem: DispatchWorkItem?

    init(store: HistoryStore) {
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "历史记录"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = NSSize(width: 290, height: 400)
        window.delegate = self

        let restored = window.setFrameUsingName("EasyBarcodeHistoryWindowV5")
        if restored {
            let frame = window.frame
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
            if frame.width < 290 || frame.height < 400 || !onScreen {
                window.setContentSize(NSSize(width: 300, height: 560))
                centerOnActiveScreen()
            }
        } else {
            centerOnActiveScreen()
        }
        window.setFrameAutosaveName("EasyBarcodeHistoryWindowV5")

        buildContent()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        updateItemSize()
        DispatchQueue.main.async { [weak self] in
            self?.updateItemSize()
        }
    }

    // MARK: - Content

    private func buildContent() {
        guard let window else { return }

        let content = HistoryContentView(frame: NSRect(x: 0, y: 0, width: 300, height: 560))
        content.onLayout = { [weak self] in
            self?.updateItemSize()
        }
        content.clearButton.target = self
        content.clearButton.action = #selector(clearHistory)
        window.contentView = content
        contentView = content

        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = NSSize(width: 380, height: HistoryItem.itemHeight)
        flowLayout.minimumInteritemSpacing = 12
        flowLayout.minimumLineSpacing = 12
        flowLayout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            HistoryItem.self,
            forItemWithIdentifier: HistoryItem.identifier
        )

        content.scrollView.documentView = collectionView
        content.scrollView.hasVerticalScroller = true
        content.scrollView.autohidesScrollers = true
        content.scrollView.drawsBackground = false
    }

    func reload() {
        statusResetWorkItem?.cancel()
        statusResetWorkItem = nil

        collectionView.reloadData()

        let isEmpty = store.entries.isEmpty
        collectionView.isHidden = isEmpty
        contentView.emptyLabel.isHidden = !isEmpty
        contentView.emptyHint.isHidden = !isEmpty
        contentView.clearButton.isEnabled = !isEmpty
        restoreCountLabel()

        updateItemSize()
        updateCollectionFrame()
    }

    // MARK: - Layout

    func windowDidResize(_ notification: Notification) {
        updateItemSize()
    }

    private func updateItemSize() {
        guard let flowLayout, let contentView else { return }

        let cardWidth: CGFloat = 250
        let spacing: CGFloat = 12
        let scrollWidth = contentView.scrollView.contentView.bounds.width
        let available = max(258, scrollWidth - 32)
        let columns = max(1, Int((available + spacing) / (cardWidth + spacing)))
        let totalWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing
        let sideInset = 16 + max(0, (available - totalWidth) / 2)

        flowLayout.itemSize = NSSize(width: cardWidth, height: HistoryItem.itemHeight)
        flowLayout.sectionInset = NSEdgeInsets(top: 16, left: sideInset, bottom: 16, right: sideInset)
        flowLayout.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
        updateCollectionFrame()
    }

    private func updateCollectionFrame() {
        guard let contentView, let layout = collectionView.collectionViewLayout else { return }
        let visible = contentView.scrollView.contentView.bounds
        let content = layout.collectionViewContentSize
        collectionView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(visible.width, content.width),
            height: max(visible.height, content.height)
        )
    }

    private func centerOnActiveScreen() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        let size = window.frame.size
        let origin = NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2).rounded()
        )
        window.setFrameOrigin(origin)
    }

    // MARK: - Collection view

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        store.entries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let entry = store.entries[indexPath.item]
        let item = collectionView.makeItem(
            withIdentifier: HistoryItem.identifier,
            for: indexPath
        ) as! HistoryItem

        item.configure(with: entry)
        item.onCopy = { [weak self] in
            self?.copyEntry(entry) ?? false
        }
        item.onDelete = { [weak self] in
            self?.confirmDelete(entry)
        }
        item.onNoteChange = { [weak self] note in
            self?.store.updateNote(id: entry.id, note: note)
        }

        return item
    }

    // MARK: - Actions

    @discardableResult
    private func copyEntry(_ entry: HistoryEntry) -> Bool {
        let payload = BarcodePayloadBuilder.make(from: entry.digits, requested: entry.format)
        guard payload.isValid,
              let image = BarcodeImageRenderer.image(for: payload, targetWidth: 1600),
              let png = BarcodeImageRenderer.pngData(for: payload, targetWidth: 1600) else {
            NSSound.beep()
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        pasteboard.setString(payload.digits, forType: .string)

        flashStatus("已复制")
        return true
    }

    private func confirmDelete(_ entry: HistoryEntry) {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "删除这条条码记录？"
        alert.informativeText = entry.digits
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.store.delete(id: entry.id)
            self.reload()
            self.onHistoryChanged?()
        }
    }

    private func flashStatus(_ text: String) {
        statusResetWorkItem?.cancel()
        contentView.countLabel.stringValue = text
        contentView.countLabel.textColor = .labelColor

        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreCountLabel()
        }
        statusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: workItem)
    }

    private func restoreCountLabel() {
        contentView.countLabel.stringValue = "共 \(store.entries.count) 条记录"
        contentView.countLabel.textColor = .secondaryLabelColor
    }

    @objc private func clearHistory() {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "清空全部历史记录？"
        alert.informativeText = "此操作无法撤销。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.store.clear()
            HistoryItem.clearCache()
            self.reload()
            self.onHistoryChanged?()
        }
    }
}

/// Manual layout on purpose: Auto Layout at the window's content root made
/// AppKit collapse the window to a 1pt width when it was first shown.
final class HistoryContentView: NSView {
    let scrollView = NSScrollView()
    let separator = NSBox()
    let countLabel = NSTextField(labelWithString: "")
    let clearButton = NSButton(title: "清空历史", target: nil, action: nil)
    let emptyLabel = NSTextField(labelWithString: "还没有历史记录")
    let emptyHint = NSTextField(labelWithString: "生成条码后会出现在这里")
    var onLayout: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        separator.boxType = .separator

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor

        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 11)
        clearButton.contentTintColor = .secondaryLabelColor

        emptyLabel.font = .systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.textColor = .tertiaryLabelColor
        emptyHint.alignment = .center

        addSubview(scrollView)
        addSubview(separator)
        addSubview(countLabel)
        addSubview(clearButton)
        addSubview(emptyLabel)
        addSubview(emptyHint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let footerHeight: CGFloat = 36
        let scrollRect = NSRect(
            x: 0,
            y: footerHeight + 1,
            width: bounds.width,
            height: max(0, bounds.height - footerHeight - 1)
        )
        scrollView.frame = scrollRect
        separator.frame = NSRect(x: 0, y: footerHeight, width: bounds.width, height: 1)

        countLabel.sizeToFit()
        countLabel.frame.origin = NSPoint(
            x: 16,
            y: footerHeight / 2 - countLabel.frame.height / 2
        )

        clearButton.sizeToFit()
        clearButton.frame.origin = NSPoint(
            x: bounds.width - clearButton.frame.width - 16,
            y: footerHeight / 2 - clearButton.frame.height / 2
        )

        emptyLabel.sizeToFit()
        emptyLabel.frame.origin = NSPoint(
            x: (bounds.width - emptyLabel.frame.width) / 2,
            y: scrollRect.midY + 4
        )

        emptyHint.sizeToFit()
        emptyHint.frame.origin = NSPoint(
            x: (bounds.width - emptyHint.frame.width) / 2,
            y: scrollRect.midY - emptyHint.frame.height - 6
        )

        onLayout?()
    }
}
