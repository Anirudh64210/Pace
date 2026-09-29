import Foundation
import Combine
import ServiceManagement

/// User preferences, backed by UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var source: UsageSource { didSet { defaults.set(source.rawValue, forKey: "source") } }
    @Published var showCountdownInMenuBar: Bool { didSet { defaults.set(showCountdownInMenuBar, forKey: "showCountdownInMenuBar") } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") } }
    @Published var apples: Int { didSet { defaults.set(apples, forKey: "apples") } }
    @Published var unseenApple: Bool { didSet { defaults.set(unseenApple, forKey: "unseenApple") } }
    @Published var eventGate: EventGate {
        didSet { if let data = try? JSONEncoder().encode(eventGate) { defaults.set(data, forKey: "eventGate") } }
    }
    @Published var launchAtLogin: Bool {
        didSet { Self.setLaunchAtLogin(launchAtLogin) }
    }
    /// Which detail rows are open. Remembered, so the panel reopens as you left it.
    @Published var openRows: Set<String> { didSet { defaults.set(Array(openRows).sorted(), forKey: "openRows") } }
    /// The pill under the menu bar icon when your status changes.
    @Published var showPill: Bool { didSet { defaults.set(showPill, forKey: "showPill") } }
    /// The keys that open the panel from anywhere.
    @Published var shortcut: Shortcut {
        didSet { if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: "shortcut") } }
    }
    /// Whether that shortcut is on.
    @Published var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: "hotKeyEnabled") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = UsageSource(rawValue: defaults.string(forKey: "source") ?? "") ?? .statusLine
        source = saved == .demo ? .statusLine : saved
        showCountdownInMenuBar = defaults.object(forKey: "showCountdownInMenuBar") as? Bool ?? true
        // The pill announces changes; system notifications are an extra, off by default.
        notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? false
        showPill = defaults.object(forKey: "showPill") as? Bool ?? true
        openRows = Set(defaults.stringArray(forKey: "openRows") ?? [])
        apples = defaults.integer(forKey: "apples")
        unseenApple = defaults.bool(forKey: "unseenApple")
        eventGate = defaults.data(forKey: "eventGate").flatMap { try? JSONDecoder().decode(EventGate.self, from: $0) } ?? EventGate()
        launchAtLogin = Self.launchAtLoginEnabled
        hotKeyEnabled = defaults.object(forKey: "hotKeyEnabled") as? Bool ?? true
        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
    }

    /// A menu bar app is only useful if it is there. The first time Pace runs
    /// from /Applications, it turns on Start at login once. After that the
    /// toggle in Settings (or System Settings › Login Items) is the user's.
    func applyFirstRunDefaults() {
        guard Self.isInstalled, !defaults.bool(forKey: "didDefaultLaunchAtLogin") else { return }
        defaults.set(true, forKey: "didDefaultLaunchAtLogin")
        launchAtLogin = true
    }

    /// Re-read the login item state; the user can change it in System Settings.
    func syncLaunchAtLogin() {
        let actual = Self.launchAtLoginEnabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }

    static var isInstalled: Bool {
        canLaunchAtLogin && Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    static var canLaunchAtLogin: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static var launchAtLoginEnabled: Bool {
        guard canLaunchAtLogin else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    private static func setLaunchAtLogin(_ on: Bool) {
        guard canLaunchAtLogin, on != launchAtLoginEnabled else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Pace: launch at login change failed: \(error.localizedDescription)")
        }
    }
}
