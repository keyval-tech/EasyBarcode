import AppKit
import BarcodeKit
import UniformTypeIdentifiers

/// A normal window showing generated barcodes as an image-first grid.
final class HistoryWindowController: NSWindowController, NSCollectionViewDataSource, NSCollectionViewDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    var onHistoryChanged: (() -> Void)?

    private let store: HistoryStore
    private let collectionView = NSCollectionView()
    private var contentView: HistoryContentView!
    private var flowLayout: NSCollectionViewFlowLayout!
    private var statusResetWorkItem: DispatchWorkItem?
    private var filter = HistoryFilter()
    private var selectedTab: String?
    private var visibleEntries: [HistoryEntry] = []

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let exportRowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

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

        let restored = window.setFrameUsingName("EasyBarcodeHistoryWindowV6")
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
        window.setFrameAutosaveName("EasyBarcodeHistoryWindowV6")

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
        content.exportButton.target = self
        content.exportButton.action = #selector(exportHistory)
        content.exportButton.isEnabled = false
        content.clearButton.target = self
        content.clearButton.action = #selector(clearHistory)

        content.searchField.delegate = self
        content.notesToggle.target = self
        content.notesToggle.action = #selector(notesToggleChanged)
        content.formatSegments.target = self
        content.formatSegments.action = #selector(formatSegmentChanged)
        for range in HistoryTimeRange.allCases {
            content.timePopup.addItem(withTitle: range.title)
        }
        content.timePopup.target = self
        content.timePopup.action = #selector(timeRangeChanged)
        content.addTabButton.target = self
        content.addTabButton.action = #selector(addTabTapped)
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

        visibleEntries = store.entries(matching: filter)
        collectionView.reloadData()

        let isEmpty = visibleEntries.isEmpty
        collectionView.isHidden = isEmpty
        contentView.emptyLabel.isHidden = !isEmpty
        contentView.emptyHint.isHidden = !isEmpty
        if isEmpty && filter.isActive {
            contentView.emptyLabel.stringValue = "没有匹配的记录"
            contentView.emptyHint.stringValue = "调整搜索或筛选条件试试"
        } else {
            contentView.emptyLabel.stringValue = "还没有历史记录"
            contentView.emptyHint.stringValue = "生成条码后会出现在这里"
        }
        contentView.clearButton.isEnabled = !store.entries.isEmpty
        contentView.exportButton.isEnabled = !store.entries.isEmpty
        restoreCountLabel(visibleCount: visibleEntries.count)

        rebuildTabStrip()
        updateItemSize()
        updateCollectionFrame()
    }

    private func rebuildTabStrip() {
        contentView.tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let allButton = tabButton(title: "全部", tabName: nil)
        styleTabButton(allButton, selected: selectedTab == nil)
        contentView.tabStack.addArrangedSubview(allButton)
        for tab in store.tabs {
            let button = tabButton(title: tab, tabName: tab)
            styleTabButton(button, selected: selectedTab == tab)
            contentView.tabStack.addArrangedSubview(button)
        }
    }

    /// Chip styling so tab boundaries and the selected tab read clearly.
    private func styleTabButton(_ button: NSButton, selected: Bool) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        if selected {
            button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            button.contentTintColor = .white
        } else {
            button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            button.contentTintColor = .secondaryLabelColor
        }
    }

    private func tabButton(title: String, tabName: String?) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(tabSelected(_:)))
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.identifier = NSUserInterfaceItemIdentifier(tabName ?? "__all__")
        button.setButtonType(.momentaryPushIn)
        button.lineBreakMode = .byTruncatingTail

        let menu = NSMenu()
        let rename = NSMenuItem(title: "重命名…", action: #selector(renameTabTapped(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = tabName
        let delete = NSMenuItem(title: "删除 Tab", action: #selector(deleteTabTapped(_:)), keyEquivalent: "")
        delete.target = self
        delete.representedObject = tabName
        menu.addItem(rename)
        menu.addItem(delete)
        button.menu = menu
        return button
    }

    private func restoreCountLabel(visibleCount: Int? = nil) {
        if let visibleCount, filter.isActive {
            contentView.countLabel.stringValue = "共 \(store.entries.count) 条 · 筛选后 \(visibleCount) 条"
        } else {
            contentView.countLabel.stringValue = "共 \(store.entries.count) 条"
        }
        contentView.countLabel.textColor = .secondaryLabelColor
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
        visibleEntries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let entry = visibleEntries[indexPath.item]
        let item = collectionView.makeItem(
            withIdentifier: HistoryItem.identifier,
            for: indexPath
        ) as! HistoryItem

        item.configure(with: entry)
        item.availableTabs = store.tabs
        item.onToggleTab = { [weak self] tab in
            guard let self else { return }
            self.store.toggleTab(id: entry.id, tab: tab)
            self.reload()
        }
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

    // MARK: - Filter & tabs

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === contentView.searchField {
            filter.query = contentView.searchField.stringValue
            reload()
        }
    }

    @objc private func notesToggleChanged() {
        filter.onlyWithNotes = contentView.notesToggle.state == .on
        reload()
    }

    @objc private func formatSegmentChanged() {
        let segment = contentView.formatSegments.selectedSegment
        let formats: [BarcodeFormat?] = [nil] + BarcodeFormat.manualFormats.map { $0 }
        filter.format = formats.indices.contains(segment) ? formats[segment] : nil
        reload()
    }

    @objc private func timeRangeChanged() {
        let index = contentView.timePopup.indexOfSelectedItem
        let ranges = HistoryTimeRange.allCases
        filter.timeRange = ranges.indices.contains(index) ? ranges[index] : .all
        reload()
    }

    @objc private func tabSelected(_ sender: NSButton) {
        let raw = sender.identifier?.rawValue
        selectedTab = (raw == nil || raw == "__all__") ? nil : raw
        filter.tab = selectedTab
        reload()
    }

    @objc private func addTabTapped() {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "新建 Tab"
        alert.informativeText = "为历史记录创建一个分类 Tab。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "Tab 名称"
        alert.accessoryView = field
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.store.addTab(field.stringValue)
            self.reload()
        }
    }

    @objc private func renameTabTapped(_ sender: NSMenuItem) {
        guard let oldName = sender.representedObject as? String, let window else { return }

        let alert = NSAlert()
        alert.messageText = "重命名 Tab"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = oldName
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.store.renameTab(oldName, to: field.stringValue)
            if self.selectedTab == oldName {
                self.selectedTab = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.filter.tab = self.selectedTab
            }
            self.reload()
        }
    }

    @objc private func deleteTabTapped(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let window else { return }

        let alert = NSAlert()
        alert.messageText = "删除 Tab「\(name)」？"
        alert.informativeText = "只移除这个分类，记录本身不会被删除。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.store.removeTab(name)
            if self.selectedTab == name {
                self.selectedTab = nil
                self.filter.tab = nil
            }
            self.reload()
        }
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

    /// The save panel's built-in format dropdown is unreliable across
    /// systems, so the export button pops up explicit choices instead.
    @objc private func exportHistory() {
        guard let window else { return }

        let menu = NSMenu()
        for (title, extensionName) in [
            ("导出为 Excel（.xlsx）…", "xlsx"),
            ("导出为 Word（.docx）…", "docx"),
            ("导出为 Markdown（.md）…", "md"),
            ("导出为 HTML（.html）…", "html"),
            ("导出为 ZIP 图片包（.zip）…", "zip")
        ] {
            let item = NSMenuItem(title: title, action: #selector(exportAs(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = extensionName
            menu.addItem(item)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: contentView.exportButton.bounds.height + 4),
            in: contentView.exportButton
        )
    }

    @objc private func exportAs(_ sender: NSMenuItem) {
        guard let window,
              let extensionName = sender.representedObject as? String else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: extensionName) ?? .data]
        let stamp = Self.exportDateFormatter.string(from: Date())
        panel.nameFieldStringValue = "EasyBarcode历史-\(stamp).\(extensionName)"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.runExport(to: url)
        }
    }

    private func runExport(to url: URL) {
        // WYSIWYG: export exactly what the list is showing — the filtered
        // set when a filter is active, everything otherwise.
        let dateFormatter = Self.exportRowDateFormatter
        let rows = visibleEntries.map { entry -> HistoryExportRow in
            let payload = BarcodePayloadBuilder.make(from: entry.digits, requested: entry.format)
            let pngData = payload.isValid
                ? BarcodeImageRenderer.pngData(for: payload, targetWidth: 900)
                : nil
            return HistoryExportRow(
                text: entry.digits,
                formatName: entry.format.displayName,
                dateString: dateFormatter.string(from: entry.createdAt),
                note: entry.note,
                pngData: pngData
            )
        }

        Task { @MainActor in
            do {
                let count: Int
                let ext = url.pathExtension.lowercased()
                switch ext {
                case "md", "markdown":
                    count = try HistoryExporter.exportMarkdown(rows: rows, to: url)
                case "docx":
                    count = try HistoryExporter.exportDOCX(rows: rows, to: url)
                case "html", "htm":
                    count = try HistoryExporter.exportHTML(rows: rows, to: url)
                case "zip":
                    count = try HistoryExporter.exportZIP(rows: rows, to: url)
                default:
                    count = try await HistoryExporter.exportXLSX(rows: rows, to: url)
                }
                let unit = url.pathExtension.lowercased() == "zip" ? "张图片" : "条"
                self.flashStatus("已导出 \(count) \(unit)")
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
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
    let tabBarScrollView = NSScrollView()
    let tabStack = NSStackView()
    let addTabButton = NSButton()
    let searchField = NSSearchField()
    let notesToggle = NSButton(checkboxWithTitle: "仅看有备注", target: nil, action: nil)
    let formatSegments = NSSegmentedControl(
        labels: ["全部", "EAN-13", "UPC-A", "Code 128", "QR"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    let timePopup = NSPopUpButton()

    let scrollView = NSScrollView()
    let separator = NSBox()
    let countLabel = NSTextField(labelWithString: "")
    let exportButton = NSButton(title: "导出", target: nil, action: nil)
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

        exportButton.isBordered = false
        exportButton.font = .systemFont(ofSize: 11)
        exportButton.contentTintColor = .secondaryLabelColor

        tabBarScrollView.hasHorizontalScroller = false
        tabBarScrollView.drawsBackground = false
        tabStack.orientation = .horizontal
        tabStack.spacing = 6
        tabStack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        tabBarScrollView.documentView = tabStack

        addTabButton.isBordered = false
        addTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建 Tab")
        addTabButton.contentTintColor = .secondaryLabelColor
        addTabButton.toolTip = "新建 Tab"

        searchField.placeholderString = "搜索内容或备注"
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 11)

        notesToggle.controlSize = .small
        notesToggle.font = .systemFont(ofSize: 11)

        formatSegments.controlSize = .small
        formatSegments.font = .systemFont(ofSize: 11)
        formatSegments.selectedSegment = 0

        timePopup.controlSize = .small
        timePopup.font = .systemFont(ofSize: 11)

        addSubview(tabBarScrollView)
        addSubview(addTabButton)
        addSubview(searchField)
        addSubview(notesToggle)
        addSubview(formatSegments)
        addSubview(timePopup)
        addSubview(scrollView)
        addSubview(separator)
        addSubview(countLabel)
        addSubview(exportButton)
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
        let tabBarHeight: CGFloat = 26
        let searchRowHeight: CGFloat = 26
        let filterRowHeight: CGFloat = 24
        let rowGap: CGFloat = 8
        let sidePadding: CGFloat = 10

        var top = bounds.height
        top -= tabBarHeight
        tabBarScrollView.frame = NSRect(x: 0, y: top, width: bounds.width, height: tabBarHeight)
        tabStack.frame = NSRect(x: 0, y: 0, width: max(tabBarScrollView.contentView.bounds.width, tabStack.fittingSize.width), height: tabBarHeight)
        addTabButton.sizeToFit()
        addTabButton.frame.origin = NSPoint(x: bounds.width - addTabButton.frame.width - sidePadding, y: top + (tabBarHeight - addTabButton.frame.height) / 2)

        top -= rowGap
        top -= searchRowHeight
        searchField.frame = NSRect(x: sidePadding, y: top, width: bounds.width - sidePadding * 2 - 110, height: searchRowHeight)
        notesToggle.sizeToFit()
        notesToggle.frame.origin = NSPoint(x: bounds.width - notesToggle.frame.width - sidePadding, y: top + (searchRowHeight - notesToggle.frame.height) / 2)

        top -= rowGap
        top -= filterRowHeight
        timePopup.sizeToFit()
        timePopup.frame = NSRect(x: bounds.width - timePopup.frame.width - sidePadding, y: top - 2, width: timePopup.frame.width, height: filterRowHeight + 4)
        formatSegments.frame = NSRect(x: sidePadding, y: top, width: bounds.width - sidePadding * 2 - timePopup.frame.width - 10, height: filterRowHeight)

        let scrollRect = NSRect(
            x: 0,
            y: footerHeight + 1,
            width: bounds.width,
            height: max(0, top - footerHeight - 1 - 4)
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

        exportButton.sizeToFit()
        exportButton.frame.origin = NSPoint(
            x: clearButton.frame.minX - exportButton.frame.width - 14,
            y: footerHeight / 2 - exportButton.frame.height / 2
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
