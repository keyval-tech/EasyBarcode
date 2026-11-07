import AppKit
import BarcodeKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var showItem: NSMenuItem!
    private var historyItem: NSMenuItem!
    private var formatItems: [BarcodeFormat: NSMenuItem] = [:]
    private var loginItem: NSMenuItem!

    var onTogglePanel: (() -> Void)?
    var onShowHistory: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onFormatChange: ((BarcodeFormat) -> Void)?
    var isPanelVisible: (() -> Bool)?
    var currentFormatProvider: (() -> BarcodeFormat)?

    var currentFormat: BarcodeFormat = .automatic {
        didSet { updateFormatStates() }
    }

    var hotKeyDisplay: String = "⌥B" {
        didSet { updateShowTitle() }
    }

    var historyHotKeyDisplay: String = "⌥H" {
        didSet { updateHistoryTitle() }
    }

    override init() {
        super.init()
        configureStatusItem()
        buildMenu()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "barcode", accessibilityDescription: "EasyBarcode")
            button.image?.isTemplate = true
            button.toolTip = "EasyBarcode"
        }
        statusItem.menu = menu
    }

    private func buildMenu() {
        menu.delegate = self

        showItem = NSMenuItem(title: "显示 EasyBarcode", action: #selector(showPanel), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())

        let formatRoot = NSMenuItem(title: "条码格式", action: nil, keyEquivalent: "")
        let formatMenu = NSMenu(title: "条码格式")
        for format in BarcodeFormat.allCases {
            let item = NSMenuItem(title: format.displayName, action: #selector(selectFormat(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = format.rawValue
            item.state = format == currentFormat ? .on : .off
            formatMenu.addItem(item)
            formatItems[format] = item
        }
        formatRoot.submenu = formatMenu
        menu.addItem(formatRoot)

        historyItem = NSMenuItem(title: "历史记录", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        let preferences = NSMenuItem(title: "设置", action: #selector(openPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "关于 EasyBarcode", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "退出 EasyBarcode", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func updateShowTitle() {
        let verb = (isPanelVisible?() ?? false) ? "隐藏" : "显示"
        showItem.title = "\(verb) EasyBarcode    \(hotKeyDisplay)"
    }

    private func updateHistoryTitle() {
        historyItem.title = "历史记录    \(historyHotKeyDisplay)"
    }

    private func updateFormatStates() {
        for (format, item) in formatItems {
            item.state = format == currentFormat ? .on : .off
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginItem.state = LoginItem.isEnabled ? .on : .off
        if let provider = currentFormatProvider {
            currentFormat = provider()
        }
        updateShowTitle()
        updateHistoryTitle()
    }

    @objc private func showPanel() {
        onTogglePanel?()
    }

    @objc private func showHistory() {
        onShowHistory?()
    }

    @objc private func selectFormat(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let format = BarcodeFormat(rawValue: raw) else { return }
        currentFormat = format
        onFormatChange?(format)
    }

    @objc private func toggleLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            presentLoginError(error)
        }
    }

    @objc private func openPreferences() {
        onOpenPreferences?()
    }

    @objc private func showAbout() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
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
