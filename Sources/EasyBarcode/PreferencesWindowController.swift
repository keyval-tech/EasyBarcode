import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController {
    private let mainRecorder: HotKeyRecorderView
    private let historyRecorder: HotKeyRecorderView
    private let loginCheckbox: NSButton
    private let glassCheckbox = NSButton(checkboxWithTitle: "主窗口使用玻璃质感（Liquid Glass）", target: nil, action: nil)
    private let appearancePopup = NSPopUpButton(
        frame: NSRect(x: 0, y: 0, width: 110, height: 26),
        pullsDown: false
    )
    private let imagesPathLabel = NSTextField(labelWithString: "")

    var onHotKeyChange: ((HotKeySlot, HotKeyConfig) -> Bool)?

    init(mainHotKeyConfig: HotKeyConfig, historyHotKeyConfig: HotKeyConfig) {
        mainRecorder = HotKeyRecorderView(config: mainHotKeyConfig)
        historyRecorder = HotKeyRecorderView(config: historyHotKeyConfig)
        loginCheckbox = NSButton(checkboxWithTitle: "登录时自动启动 EasyBarcode", target: nil, action: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 448),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        mainRecorder.onChange = { [weak self] config in
            self?.onHotKeyChange?(.main, config) ?? false
        }
        historyRecorder.onChange = { [weak self] config in
            self?.onHotKeyChange?(.history, config) ?? false
        }

        window.title = "EasyBarcode 设置"
        window.isReleasedWhenClosed = false
        window.center()
        buildContent()
        refreshLoginState()
        refreshImagesDirectory()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshLoginState()
        refreshImagesDirectory()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let window else { return }

        let content = NSView()
        window.contentView = content

        let globalTitle = NSTextField(labelWithString: "全局快捷键")
        globalTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        let appTitle = NSTextField(labelWithString: "应用内快捷键")
        appTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        mainRecorder.translatesAutoresizingMaskIntoConstraints = false
        historyRecorder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainRecorder.widthAnchor.constraint(equalToConstant: 200),
            mainRecorder.heightAnchor.constraint(equalToConstant: 34),
            historyRecorder.widthAnchor.constraint(equalToConstant: 200),
            historyRecorder.heightAnchor.constraint(equalToConstant: 34)
        ])

        let mainRow = makeRecorderRow(label: "主窗口", recorder: mainRecorder)
        let historyRow = makeRecorderRow(label: "历史记录", recorder: historyRecorder)

        let appHint = NSTextField(labelWithString: "仅在 EasyBarcode 激活时生效，不会抢占其他 App 的按键。")
        appHint.font = .systemFont(ofSize: 11)
        appHint.textColor = .secondaryLabelColor

        let shortcutHint = NSTextField(labelWithString: "点击按钮后按下组合键，需包含 ⌘、⌥ 或 ⌃。Delete 恢复默认，Esc 取消。")
        shortcutHint.font = .systemFont(ofSize: 11)
        shortcutHint.textColor = .secondaryLabelColor
        shortcutHint.maximumNumberOfLines = 2
        shortcutHint.lineBreakMode = .byWordWrapping
        shortcutHint.preferredMaxLayoutWidth = 380

        let appearanceTitle = NSTextField(labelWithString: "外观")
        appearanceTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        let appearanceLabel = NSTextField(labelWithString: "界面外观")
        appearanceLabel.font = .systemFont(ofSize: 11)
        appearanceLabel.textColor = .secondaryLabelColor
        appearanceLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        appearancePopup.controlSize = .small
        appearancePopup.font = .systemFont(ofSize: 11)
        for mode in AppSettings.AppearanceMode.allCases {
            appearancePopup.addItem(withTitle: mode.title)
            appearancePopup.lastItem?.representedObject = mode.rawValue
        }
        appearancePopup.selectItem(
            at: AppSettings.AppearanceMode.allCases.firstIndex(of: AppSettings.appearanceMode) ?? 0
        )
        appearancePopup.target = self
        appearancePopup.action = #selector(appearancePopupChanged)

        let appearanceRow = NSStackView(views: [appearanceLabel, appearancePopup])
        appearanceRow.orientation = .horizontal
        appearanceRow.alignment = .centerY
        appearanceRow.spacing = 10

        glassCheckbox.font = .systemFont(ofSize: 13)
        glassCheckbox.state = AppSettings.useGlass ? .on : .off
        // The glass material can only follow the system appearance, so the
        // switch has no effect while a fixed appearance is selected.
        glassCheckbox.isEnabled = AppSettings.appearanceMode == .system
        glassCheckbox.target = self
        glassCheckbox.action = #selector(toggleGlass)

        let glassHint = NSTextField(
            labelWithString: "玻璃材质只跟随系统外观；选择浅色或深色时主窗口使用标准背景。"
        )
        glassHint.font = .systemFont(ofSize: 11)
        glassHint.textColor = .secondaryLabelColor
        glassHint.maximumNumberOfLines = 2
        glassHint.lineBreakMode = .byWordWrapping
        glassHint.preferredMaxLayoutWidth = 380

        let imagesTitle = NSTextField(labelWithString: "历史图片目录")
        imagesTitle.font = .systemFont(ofSize: 13, weight: .semibold)

        imagesPathLabel.font = .systemFont(ofSize: 11)
        imagesPathLabel.textColor = .secondaryLabelColor
        imagesPathLabel.lineBreakMode = .byTruncatingMiddle
        imagesPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imagesPathLabel.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let openButton = NSButton(title: "打开", target: self, action: #selector(openImagesDirectory))
        openButton.controlSize = .small
        openButton.bezelStyle = .rounded

        let chooseButton = NSButton(title: "选择…", target: self, action: #selector(chooseImagesDirectory))
        chooseButton.controlSize = .small
        chooseButton.bezelStyle = .rounded

        let resetButton = NSButton(title: "恢复默认", target: self, action: #selector(resetImagesDirectory))
        resetButton.isBordered = false
        resetButton.font = .systemFont(ofSize: 11)
        resetButton.contentTintColor = .secondaryLabelColor

        let imagesRow = NSStackView(views: [imagesPathLabel, openButton, chooseButton, resetButton])
        imagesRow.orientation = .horizontal
        imagesRow.alignment = .centerY
        imagesRow.spacing = 8
        imagesRow.widthAnchor.constraint(equalToConstant: 380).isActive = true

        let imagesHint = NSTextField(labelWithString: "生成条码时会保存一张图片到该目录，可用「打开」在 Finder 中管理。")
        imagesHint.font = .systemFont(ofSize: 11)
        imagesHint.textColor = .secondaryLabelColor

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        loginCheckbox.font = .systemFont(ofSize: 13)

        let version = NSTextField(labelWithString: versionString)
        version.font = .systemFont(ofSize: 11)
        version.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [
            globalTitle,
            mainRow,
            appTitle,
            historyRow,
            appHint,
            shortcutHint,
            appearanceTitle,
            appearanceRow,
            glassCheckbox,
            glassHint,
            imagesTitle,
            imagesRow,
            imagesHint,
            loginCheckbox,
            version
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(8, after: globalTitle)
        stack.setCustomSpacing(16, after: mainRow)
        stack.setCustomSpacing(6, after: appTitle)
        stack.setCustomSpacing(4, after: historyRow)
        stack.setCustomSpacing(10, after: appHint)
        stack.setCustomSpacing(18, after: shortcutHint)
        stack.setCustomSpacing(8, after: appearanceTitle)
        stack.setCustomSpacing(16, after: appearanceRow)
        stack.setCustomSpacing(4, after: glassCheckbox)
        stack.setCustomSpacing(8, after: glassHint)
        stack.setCustomSpacing(8, after: imagesTitle)
        stack.setCustomSpacing(6, after: imagesRow)
        stack.setCustomSpacing(18, after: imagesHint)
        stack.setCustomSpacing(14, after: loginCheckbox)

        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            shortcutHint.widthAnchor.constraint(equalToConstant: 380)
        ])
    }

    private func makeRecorderRow(label: String, recorder: HotKeyRecorderView) -> NSStackView {
        let name = NSTextField(labelWithString: label)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .secondaryLabelColor
        name.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let row = NSStackView(views: [name, recorder])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        return "EasyBarcode \(version) · 需要 macOS 26 或更高版本"
    }

    private func refreshLoginState() {
        loginCheckbox.state = LoginItem.isEnabled ? .on : .off
    }

    private func refreshImagesDirectory() {
        imagesPathLabel.stringValue = HistoryStore.shared.imagesDirectoryDisplayPath
        imagesPathLabel.toolTip = HistoryStore.shared.imagesDirectory.path
    }

    @objc private func appearancePopupChanged() {
        let index = appearancePopup.indexOfSelectedItem
        let modes = AppSettings.AppearanceMode.allCases
        guard modes.indices.contains(index) else { return }
        AppSettings.appearanceMode = modes[index]
        AppSettings.applyAppearance()
        glassCheckbox.isEnabled = modes[index] == .system
    }

    @objc private func toggleGlass() {
        AppSettings.useGlass = glassCheckbox.state == .on
    }

    @objc private func openImagesDirectory() {
        let url = HistoryStore.shared.imagesDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func chooseImagesDirectory() {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.directoryURL = HistoryStore.shared.imagesDirectory

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            HistoryStore.shared.setImagesDirectory(url)
            self?.refreshImagesDirectory()
        }
    }

    @objc private func resetImagesDirectory() {
        HistoryStore.shared.resetImagesDirectory()
        refreshImagesDirectory()
    }

    @objc private func toggleLogin() {
        let desired = loginCheckbox.state == .on
        do {
            try LoginItem.setEnabled(desired)
        } catch {
            loginCheckbox.state = desired ? .off : .on
            presentLoginError(error)
        }
    }

    private func presentLoginError(_ error: Error) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        let alert = NSAlert()
        alert.messageText = "无法修改登录项"
        alert.informativeText = "\(error.localizedDescription)\n\n请在系统设置 › 通用 › 登录项中手动添加 EasyBarcode。"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
