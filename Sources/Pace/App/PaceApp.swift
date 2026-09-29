import SwiftUI
import AppKit

/// Entry point. Pace is a plain AppKit menu bar app that hosts SwiftUI views.
///
///   Pace                 run normally
///   Pace --demo          cycle through every state with fake data
///   Pace --check         test both data sources from the terminal and exit
///   Pace --snapshot DIR  render every state to PNG and exit
@main
enum PaceLauncher {
    @MainActor private static var delegate: AppDelegate?

    static func main() {
        Hygiene.run()
        if CommandLine.arguments.contains("--check") {
            Task {
                await HealthCheck.run()
                exit(0)
            }
            dispatchMain()
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let d = AppDelegate()
            delegate = d
            app.delegate = d
            app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Task { @MainActor in
                await SnapshotRenderer.render(to: URL(fileURLWithPath: args[i + 1]))
                NSApp.terminate(nil)
            }
            return
        }
        let settings = SettingsHolder.shared
        if !SettingsHolder.isDemo {
            settings.applyFirstRunDefaults()
            StatusLineInstaller.refreshInstalledScript()   // keep an installed script current after updates
        }
        let state = AppState(settings: settings, demo: SettingsHolder.isDemo)
        self.state = state
        statusItem = StatusItemController(app: state)
    }

    /// Opening Pace again (Spotlight, Launchpad, Finder) while it is running
    /// shows the panel, so it never looks like nothing happened.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem?.showPanelFromOutside()
        return false
    }
}

/// Renders every state to PNG for the README. Demo data only.
@MainActor
enum SnapshotRenderer {
    static func render(to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "org.pace-menubar.Pace.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let settings = Settings(defaults: UserDefaults(suiteName: suite) ?? .standard)
        let app = AppState(settings: settings, demo: true, autoPoll: false)
        for name in ["normal", "climbing", "session-limit", "session-reset", "weekly-limit", "weekly-reset"] {
            await app.refresh()
            if name != "session-reset" { app.toast = nil }   // keep one toast example
            write(PanelView().environmentObject(app), to: dir.appendingPathComponent("\(name).png"))
            if name == "normal" {
                write(PanelView().environmentObject(app).environment(\.forcedDefiner, "Session used"),
                      to: dir.appendingPathComponent("hover.png"))
                write(PanelView().environmentObject(app).environment(\.forcedHover, true),
                      to: dir.appendingPathComponent("hover-rows.png"))
                app.settings.openRows = ["week", "scoped-Fable weekly", "credits", "breakdown"]
                write(PanelView().environmentObject(app), to: dir.appendingPathComponent("expanded-all.png"))
                app.settings.openRows = []
            }
        }

        app.showSettings = true
        write(PanelView().environmentObject(app), to: dir.appendingPathComponent("settings.png"))
        settings.source = .oauth   // the demo keeps its provider; this only changes the settings layout
        write(PanelView().environmentObject(app), to: dir.appendingPathComponent("settings-signin.png"))

        let freshSuite = suite + ".fresh"
        UserDefaults().removePersistentDomain(forName: freshSuite)
        let fresh = AppState(settings: Settings(defaults: UserDefaults(suiteName: freshSuite) ?? .standard),
                             autoPoll: false, provider: DemoProvider())
        fresh.setStatusForPreview(.waiting("Waiting for Claude Code."))
        write(PanelView().environmentObject(fresh).environment(\.installedOverride, false),
              to: dir.appendingPathComponent("onboarding.png"))

        // The status pill.
        let pillModel = PillModel()
        pillModel.alert = StatusAlert(title: "Session limit", detail: "back at 3:32 AM", kind: .reward)
        pillModel.visible = true
        let pillRenderer = ImageRenderer(content: StatusPillView(model: pillModel).frame(width: PillController.size.width, height: PillController.size.height))
        pillRenderer.scale = 2
        if let cg = pillRenderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("pill.png"))
        }

        for name in [suite, freshSuite] {
            UserDefaults().removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(name).plist"))
        }
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
