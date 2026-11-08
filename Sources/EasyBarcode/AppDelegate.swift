import AppKit
import BarcodeKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKey = GlobalHotKey.shared
    private var mainHotKeyConfig: HotKeyConfig = .default
    private var historyHotKeyConfig: HotKeyConfig = .historyDefault
    private var panelController: BarcodePanelController!
    private var statusController: StatusItemController!
    private var preferencesController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController = BarcodePanelController()

        statusController = StatusItemController()
        statusController.onTogglePanel = { [weak self] in self?.togglePanel() }
        statusController.onShowHistory = { [weak self] in self?.panelController.showHistoryWindow() }
        statusController.isPanelVisible = { [weak self] in self?.panelController.isVisible ?? false }
        statusController.currentFormatProvider = { [weak self] in self?.panelController.selectedFormat ?? .automatic }
        statusController.onFormatChange = { [weak self] format in
            self?.panelController.selectedFormat = format
        }
        statusController.onOpenPreferences = { [weak self] in self?.showPreferences() }

        configureMainMenu()
        configureHotKey()
        AppSettings.applyAppearance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceSettingChanged),
            name: AppSettings.appearanceChangedNotification,
            object: nil
        )

        let arguments = CommandLine.arguments
        let shouldShow = arguments.contains("--show")
            || arguments.contains("--print-window-id")
            || arguments.contains("--demo")
        if shouldShow {
            showPanel()
        }
        if let demoIndex = arguments.firstIndex(of: "--demo"), arguments.count > demoIndex + 1 {
            panelController.setText(arguments[demoIndex + 1])
        }
        if arguments.contains("--preferences") {
            showPreferences()
        }
        if arguments.contains("--copy") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.panelController.copyImage()
            }
        }
        if arguments.contains("--print-window-id") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                print("WINDOW_ID=\(self.panelController.window.windowNumber)")
                fflush(stdout)
            }
        }
    }

    // MARK: - Hot key

    @objc private func appearanceSettingChanged() {
        AppSettings.applyAppearance()
    }

    private var historyKeyMonitor: Any?

    private func configureHotKey() {
        mainHotKeyConfig = HotKeyConfig.load(for: .main)
        historyHotKeyConfig = HotKeyConfig.load(for: .history)

        installHistoryShortcutMonitor()

        let mainRegistered = hotKey.register(
            mainHotKeyConfig,
            id: EasyBarcodeHotKeyID.main
        ) { [weak self] in
            self?.togglePanel()
        }

        statusController.hotKeyDisplay = mainHotKeyConfig.displayString
        statusController.historyHotKeyDisplay = historyHotKeyConfig.displayString

        if !mainRegistered {
            let failedConfig = mainHotKeyConfig
            DispatchQueue.main.async { [weak self] in
                self?.presentHotKeyConflict([failedConfig])
            }
        }
    }

    /// The history shortcut is intentionally app-only: a local monitor only
    /// receives keys while EasyBarcode is active.
    private func installHistoryShortcutMonitor() {
        guard historyKeyMonitor == nil else { return }

        historyKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.isActive else { return event }
            guard !HotKeyRecorderView.isRecordingAny else { return event }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

            // Standard app shortcut for Settings.
            if flags == [.command], event.charactersIgnoringModifiers == "," {
                self.showPreferences()
                return nil
            }

            guard event.keyCode == UInt16(self.historyHotKeyConfig.keyCode),
                  flags == self.historyHotKeyConfig.modifiers else {
                return event
            }

            self.toggleHistoryWindow()
            return nil
        }
    }

    private func presentDuplicateHotKey(_ config: HotKeyConfig) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        let alert = NSAlert()
        alert.messageText = "快捷键重复"
        alert.informativeText = "\(config.displayString) 已经用于另一个功能，请换一个组合键。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentHotKeyConflict(_ configs: [HotKeyConfig]) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        let list = configs.map(\.displayString).joined(separator: "、")
        let alert = NSAlert()
        alert.messageText = "快捷键不可用"
        alert.informativeText = "\(list) 可能已被其他应用占用。\n请从菜单栏打开「设置」更换组合键。"
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Panel

    @objc private func showPanel() {
        panelController.show()
        statusController.currentFormat = panelController.selectedFormat
    }

    private func togglePanel() {
        panelController.toggle()
    }

    private func toggleHistoryWindow() {
        panelController.toggleHistoryWindow()
    }

    // MARK: - Preferences

    private func showPreferences() {
        if preferencesController == nil {
            let controller = PreferencesWindowController(
                mainHotKeyConfig: mainHotKeyConfig,
                historyHotKeyConfig: historyHotKeyConfig
            )
            controller.onHotKeyChange = { [weak self] slot, newConfig in
                guard let self else { return false }

                let otherConfig = slot == .main ? self.historyHotKeyConfig : self.mainHotKeyConfig
                guard newConfig != otherConfig else {
                    self.presentDuplicateHotKey(newConfig)
                    return false
                }

                // ⌘, is reserved for opening Settings.
                if newConfig.keyCode == 43, newConfig.modifiers == [.command] {
                    self.presentDuplicateHotKey(newConfig)
                    return false
                }

                switch slot {
                case .main:
                    let handler: () -> Void = { [weak self] in self?.togglePanel() }
                    guard self.hotKey.register(
                        newConfig,
                        id: EasyBarcodeHotKeyID.main,
                        handler: handler
                    ) else {
                        self.presentHotKeyConflict([newConfig])
                        return false
                    }
                    newConfig.save(for: .main)
                    self.mainHotKeyConfig = newConfig
                    self.statusController.hotKeyDisplay = newConfig.displayString
                case .history:
                    // App-internal shortcut: handled by a local key monitor.
                    newConfig.save(for: .history)
                    self.historyHotKeyConfig = newConfig
                    self.statusController.historyHotKeyDisplay = newConfig.displayString
                }
                return true
            }
            preferencesController = controller
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        preferencesController?.showWindow(nil)
    }

    // MARK: - Main menu (hidden for LSUIElement, still routes key equivalents)

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "关于 EasyBarcode",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openPreferencesFromMenu(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "隐藏 EasyBarcode",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: "退出 EasyBarcode",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu

        let copyItem = NSMenuItem(title: "复制条码图片", action: #selector(copyBarcode), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = [.command, .shift]
        copyItem.target = self
        fileMenu.addItem(copyItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "缩放",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = windowMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    @objc private func copyBarcode() {
        panelController.copyImage()
    }

    @objc private func openPreferencesFromMenu(_ sender: Any?) {
        showPreferences()
    }
}
