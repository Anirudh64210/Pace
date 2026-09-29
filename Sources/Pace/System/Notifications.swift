import Foundation
import UserNotifications

/// System notifications for session and weekly resets.
///
/// Only a bundled `Pace.app` posts them: macOS attributes a notification to the
/// app that sent it, and a bare `swift run` binary has no bundle to attribute
/// to. Unbundled runs show the in-panel toast only.
@MainActor
final class Notifier {
    static let shared = Notifier()
    private var requested = false

    var canNotify: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func requestPermissionIfNeeded() {
        guard canNotify, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(title: String, body: String) {
        guard canNotify else { return }
        requestPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // A stable identifier per title replaces an earlier copy instead of stacking.
        let request = UNNotificationRequest(identifier: "pace.\(title)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
