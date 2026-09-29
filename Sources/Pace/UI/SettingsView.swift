import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var settings: Settings
    @Binding var isPresented: Bool
    @State private var installStatus = StatusLineInstaller.status()
    @State private var installError: String?

    init(settings: Settings, isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _settings = ObservedObject(wrappedValue: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { isPresented = false } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text("Back")
                    }
                }
                .buttonStyle(LinkStyle())
                .font(.system(size: 12))
                .definer("Main view")
                Spacer()
                Text("Settings").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text("Back").font(.system(size: 12)).hidden()
            }
            .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 16) {
            section("Usage source") {
                sourceRow(.statusLine,
                          detail: "A script in Claude Code saves your limits to a local file. No credentials. Updates while Claude Code runs.")
                sourceRow(.oauth,
                          detail: "Uses your Claude Code sign-in to ask Anthropic directly. Adds model limits, credits and usage by product. The token stays in memory.")
            }

            if settings.source == .oauth {
                section("Connection") {
                    HStack(spacing: 10) {
                        connectionLabel
                        Spacer()
                        Button("Check now") { app.retryNow() }
                            .buttonStyle(SmallButtonStyle())
                            .definer("Test connection")
                            .disabled(app.isRefreshing)
                    }
                    .font(.system(size: 12))
                    if let message = app.status.message, app.status.isFailure {
                        Text(message)
                            .font(.system(size: 11))
                            .lineSpacing(2)
                            .foregroundStyle(app.isWaitingForSignIn ? Theme.muted : Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if settings.source == .statusLine {
                section("Claude Code status line") {
                    HStack(spacing: 10) {
                        switch installStatus {
                        case .installed:
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.leaf)
                        case .notInstalled:
                            Text("Not installed").foregroundStyle(Theme.muted)
                        case .otherStatusLine:
                            Text("You have a status line already. Pace will keep it and just save the numbers.")
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if installStatus == .installed {
                            Button("Remove") { uninstall() }
                                .buttonStyle(SmallButtonStyle())
                                .definer("Undo install")
                        }
                        Button(installStatus == .installed ? "Reinstall" : "Install") { install() }
                            .buttonStyle(SmallButtonStyle())
                            .definer(installStatus == .installed ? "Rewrite script" : "Add script")
                    }
                    .font(.system(size: 12))
                    if let installError {
                        Text(installError).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                    Text("Adds ~/.claude/pace-statusline.sh and points Claude Code at it. A backup of your settings is kept.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Behaviour") {
                toggle("Countdown in the menu bar", isOn: $settings.showCountdownInMenuBar)
                toggle("Show a pill when your status changes", isOn: $settings.showPill)
                toggle("Also send notifications", isOn: $settings.notificationsEnabled)
                if Settings.canLaunchAtLogin {
                    toggle("Start at login", isOn: $settings.launchAtLogin)
                }
                HStack(spacing: 10) {
                    Text("Open from anywhere")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    if settings.hotKeyEnabled {
                        ShortcutRecorder(settings: settings)
                    }
                    Button { settings.hotKeyEnabled.toggle() } label: { // definer: "Shortcut on" or "Shortcut off", below
                        PaceSwitch(isOn: settings.hotKeyEnabled).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .definer(settings.hotKeyEnabled ? "Shortcut on" : "Shortcut off")
                }
            }

            HStack {
                Text(settings.apples == 1 ? "1 apple harvested" : "\(settings.apples) apples harvested").foregroundStyle(Theme.muted)
                Spacer()
                Button("Reset") { settings.apples = 0; settings.unseenApple = false }
                    .buttonStyle(SmallButtonStyle())
                    .definer("Clear count")
            }
            .font(.system(size: 12))

            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Hairline().padding(.top, 18).padding(.bottom, 12)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pace \(PaceVersion.string)\(app.isDemo ? " · demo data" : "")").foregroundStyle(Theme.muted)
                    Text("Unofficial. Not affiliated with Anthropic.").foregroundStyle(Theme.faint)
                }
                .font(.system(size: 11))
                Spacer()
                Button("Quit Pace") { NSApp.terminate(nil) }
                    .buttonStyle(SmallButtonStyle())
                    .definer("Quit app")
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(20)
        .frame(width: Theme.panelWidth, alignment: .top)
        .onAppear {
            installStatus = StatusLineInstaller.status()
            settings.syncLaunchAtLogin()
        }
        .onChange(of: settings.notificationsEnabled) { _, on in
            if on { Notifier.shared.requestPermissionIfNeeded() }
        }
    }

    @ViewBuilder private var connectionLabel: some View {
        switch app.status {
        case .live:
            let plan = app.snapshot?.plan.map { " · \($0.capitalized) plan" } ?? ""
            Label("Connected\(plan)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.leaf)
        case .failed where app.isWaitingForSignIn:
            Label("Waiting for sign-in renewal", systemImage: "clock")
                .foregroundStyle(Theme.muted)
        case .failed(_, let retryAt?):
            Label("Paused · retrying in \(Formatting.shortCountdown(to: retryAt, now: app.now))", systemImage: "pause.circle.fill")
                .foregroundStyle(Theme.accent)
        case .failed:
            Label("Not connected", systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.accent)
        default:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Connecting").foregroundStyle(Theme.muted)
            }
        }
    }

    private func uninstall() {
        do {
            try StatusLineInstaller.uninstall()
            installError = nil
        } catch {
            installError = error.localizedDescription
        }
        installStatus = StatusLineInstaller.status()
        app.retryNow()
    }

    private func install() {
        do {
            try StatusLineInstaller.install()
            installError = nil
        } catch {
            installError = error.localizedDescription
        }
        installStatus = StatusLineInstaller.status()
        app.retryNow()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.faint)
            content()
        }
    }

    private func sourceRow(_ source: UsageSource, detail: String) -> some View {
        Button { // definer: "In use" or "Use this", after the button style below
            settings.source = source
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: settings.source == source ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(settings.source == source ? Theme.apple : Theme.faint)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.text)
                    Text(detail).font(.system(size: 11)).lineSpacing(2).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .definer(settings.source == source ? "In use" : "Use this")
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.secondary) }
            .toggleStyle(PaceToggleStyle())
    }
}

/// A small capsule switch drawn in the panel's palette.
struct PaceToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { // definer: none, the switch is labelled by its own text
            HStack {
                configuration.label
                Spacer()
                PaceSwitch(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The switch itself, shared so every row's switch lines up exactly.
struct PaceSwitch: View {
    var isOn: Bool
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.apple : Theme.text.opacity(0.14))
            Circle().fill(Theme.text).padding(2)
        }
        .frame(width: 30, height: 18)
        .animation(Motion.snappy, value: isOn)
    }
}

struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.text.opacity(configuration.isPressed ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
    }
}

/// The single Settings instance, created before the SwiftUI scene so views can
/// observe it directly. Demo runs use a separate, wiped store so fake apples,
/// the unseen dot and the reset history never leak into real settings.
@MainActor
enum SettingsHolder {
    static let demoSuite = "org.pace-menubar.Pace.demo"
    static let isDemo = CommandLine.arguments.contains("--demo")

    static let shared: Settings = {
        guard isDemo, let demo = UserDefaults(suiteName: demoSuite) else { return Settings() }
        demo.removePersistentDomain(forName: demoSuite)
        return Settings(defaults: demo)
    }()
}

enum PaceVersion {
    static let string = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.4.0"
}

/// Click, then press the keys you want. Esc cancels.
struct ShortcutRecorder: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var settings: Settings
    @State private var monitor: Any?
    @State private var rejected = false

    private var recording: Bool { app.isRecordingShortcut }

    var body: some View {
        Button { // definer: "Change shortcut", after the button style below
            recording ? stop() : start()
        } label: {
            Text(recording ? (rejected ? "Add ⌃, ⌥ or ⌘" : "Type keys…") : settings.shortcut.display)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(recording ? Theme.gold : Theme.text)
                .frame(minWidth: 64)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Theme.text.opacity(recording ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(recording ? Theme.gold.opacity(0.6) : Theme.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .definer(recording ? "Esc cancels" : "Change shortcut")
        .accessibilityLabel("Shortcut, \(settings.shortcut.spoken)")
        .onDisappear { stop() }
    }

    private func start() {
        rejected = false
        app.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 { stop(); return }                 // Esc
                if let s = Shortcut.from(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                         characters: event.charactersIgnoringModifiers) {
                    settings.shortcut = s
                    stop()
                } else {
                    rejected = true
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        rejected = false
        if app.isRecordingShortcut { app.isRecordingShortcut = false }
    }
}
