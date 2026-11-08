import AppKit
import Foundation

/// Small typed wrapper around the app's UserDefaults keys.
enum AppSettings {
    static let glassChangedNotification = Notification.Name("EasyBarcodeGlassChanged")
    static let appearanceChangedNotification = Notification.Name("EasyBarcodeAppearanceChanged")

    /// Whether the main window renders with Liquid Glass. Defaults to on;
    /// `bool(forKey:)` alone would report false for an unset key.
    static var useGlass: Bool {
        get {
            let defaults = UserDefaults.standard
            return defaults.object(forKey: "EasyBarcode.useGlass") == nil
                ? true
                : defaults.bool(forKey: "EasyBarcode.useGlass")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "EasyBarcode.useGlass")
            NotificationCenter.default.post(name: glassChangedNotification, object: nil)
        }
    }

    // MARK: - Appearance

    enum AppearanceMode: String, CaseIterable {
        case system
        case light
        case dark

        var title: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        /// `nil` means follow the system.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Interface appearance for the whole app; defaults to following the
    /// system.
    static var appearanceMode: AppearanceMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "EasyBarcode.appearance")
            return raw.flatMap(AppSettings.AppearanceMode.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "EasyBarcode.appearance")
            NotificationCenter.default.post(name: appearanceChangedNotification, object: nil)
        }
    }

    /// Applies the stored appearance to the whole app.
    static func applyAppearance() {
        NSApp.appearance = appearanceMode.nsAppearance
    }
}
