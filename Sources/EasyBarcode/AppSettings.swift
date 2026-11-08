import Foundation

/// Small typed wrapper around the app's UserDefaults keys.
enum AppSettings {
    static let glassChangedNotification = Notification.Name("EasyBarcodeGlassChanged")

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
}
