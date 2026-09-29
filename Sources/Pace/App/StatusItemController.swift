import AppKit
import SwiftUI
import Combine

/// The menu bar item and its panel.
///
/// Left click toggles the panel. Right click (or Control-click) opens a small
/// menu with Refresh, Settings and Quit. The panel closes on Esc, on a click
/// anywhere else, or when the icon is clicked again. Closing never quits.
@MainActor
final class StatusItemController: NSObject {
    private let app: AppState
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: PacePanel
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastTitle: String?
    private var lastFillBucket: Int?
    private let hotKey = GlobalHotKey()
    private let pill = PillController()

    init(app: AppState) {
        self.app = app
        // A fixed, transparent window. The panel sits at its top and animates its
        // own height; the window never resizes, so nothing can jump. The shadow
        // is the native macOS window shadow, which follows the panel's shape
        // because everything else in the window is fully transparent.
        let m = Theme.windowMargin
        let root = PanelView()
            .environmentObject(app)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Theme.text.opacity(0.1)))
            .padding(.horizontal, m)
            .padding(.bottom, m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        panel = PacePanel(root: root, size: Self.windowSize)
        super.init()

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.setAccessibilityTitle("Pace")
        }
        // Losing focus closes the panel, except when the click that took focus
        // is on the icon itself: that click toggles the panel in statusItemClicked.
        panel.onResignKey = { [weak self] in
            guard let self else { return }
            if self.mouseIsOverIcon { return }
            self.hidePanel()
        }

        // AppState publishes every second for the countdown. The button is only
        // touched when what it shows actually changes.
        app.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        updateButton()

        // The native shadow is computed from the panel's shape. Recompute it when
        // the panel's height changes: once right away and once after the
        // animation has settled, so no stale shadow lingers.
        app.$panelHeight
            .removeDuplicates()
            .sink { [weak self] _ in self?.refreshShadow() }
            .store(in: &cancellables)

        // Status changes drop the pill from under the icon while the panel is closed.
        app.$pill
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] alert in self?.showPill(alert) }
            .store(in: &cancellables)

        // The shortcut toggles the panel from anywhere. Re-registered when it is
        // switched on or off or re-recorded, and paused while recording.
        Publishers.CombineLatest3(app.settings.$hotKeyEnabled, app.settings.$shortcut, app.$isRecordingShortcut)
            .sink { [weak self] on, shortcut, recording in
                guard let self else { return }
                if on, !recording {
                    self.hotKey.register(shortcut) { [weak self] in self?.togglePanel() }
                } else {
                    self.hotKey.unregister()
                }
            }
            .store(in: &cancellables)
    }

    private var shadowTask: Task<Void, Never>?

    private func refreshShadow() {
        guard panel.isVisible else { return }
        panel.invalidateShadow()
        shadowTask?.cancel()
        shadowTask = Task { [weak self] in
            for delay in [120, 250, 450] as [UInt64] {
                do { try await Task.sleep(nanoseconds: delay * 1_000_000) } catch { return }
                self?.panel.invalidateShadow()
            }
        }
    }

    private var iconAndScreen: (icon: NSRect, visible: NSRect)? {
        guard let button = item.button, let window = button.window else { return nil }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        return (icon, (window.screen ?? NSScreen.main)?.visibleFrame ?? icon)
    }

    private func showPill(_ alert: StatusAlert) {
        guard !panel.isVisible, let geo = iconAndScreen else { return }
        pill.show(alert, icon: geo.icon, visible: geo.visible)
    }

    func togglePanel() { panel.isVisible ? hidePanel() : showPanel() }

    /// Called when Pace is opened again while already running.
    func showPanelFromOutside() { if !panel.isVisible { showPanel() } }

    // MARK: Button

    private func updateButton() {
        guard let button = item.button else { return }
        let bucket = Int((app.appleFill * 20).rounded())
        if bucket != lastFillBucket {
            lastFillBucket = bucket
            button.image = AppleImage.menuBar(fill: app.appleFill)
        }
        let text = app.settings.showCountdownInMenuBar
            ? app.panelText.flatMap { PanelText.menuBarText($0, now: app.now) } ?? ""
            : ""
        if text != lastTitle {
            lastTitle = text
            button.title = text.isEmpty ? "" : " " + text
            button.setAccessibilityLabel(text.isEmpty ? "Pace" : "Pace, \(text) until reset")
            // The panel is never moved while it is open, even though the icon's
            // width just changed: a panel that slides sideways reads as a glitch.
        }
    }

    private var mouseIsOverIcon: Bool {
        guard let button = item.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.contains(NSEvent.mouseLocation)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePanel()
        }
    }

    // MARK: Menu

    private func showMenu() {
        hidePanel()
        let menu = NSMenu()
        let shortcut = app.settings.shortcut
        let open = menu.addItem(withTitle: "Open Pace", action: #selector(menuOpen),
                                keyEquivalent: app.settings.hotKeyEnabled && shortcut.key.count == 1 ? shortcut.key.lowercased() : "")
        open.keyEquivalentModifierMask = shortcut.menuModifiers
        open.target = self
        menu.addItem(withTitle: "Refresh Now", action: #selector(menuRefresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        if Settings.canLaunchAtLogin {
            let login = menu.addItem(withTitle: "Start at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
            login.state = app.settings.launchAtLogin ? .on : .off
            login.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pace", action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
        item.button?.performClick(nil)   // shows the menu and blocks until it closes
        item.menu = nil                  // so the next left click opens the panel again
    }

    // Menu actions run while the menu is still tracking; open the panel after it closes.
    @objc private func menuOpen() { DispatchQueue.main.async { self.showPanel() } }
    @objc private func menuRefresh() { app.retryNow() }
    @objc private func menuSettings() {
        DispatchQueue.main.async {
            self.app.showSettings = true
            self.showPanel()
        }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuToggleLogin() { app.settings.launchAtLogin.toggle() }

    // MARK: Panel

    static var windowSize: NSSize {
        NSSize(width: Theme.panelWidth + 2 * Theme.windowMargin, height: Theme.panelHeight + Theme.windowMargin)
    }

    /// Where the window goes: the panel's top edge 6 pt under the icon, its right
    /// edge lined up with the icon's right edge, kept on screen.
    ///
    /// The right edge, not the centre: menu bar items are laid out from the
    /// right, so when the countdown text next to the apple changes width the
    /// icon's centre moves but its right edge does not. Anchoring there keeps the
    /// panel in the same place every time it opens.
    static func windowFrame(icon: NSRect, visible: NSRect) -> NSRect {
        let size = windowSize
        let m = Theme.windowMargin
        var panelX = icon.maxX + 10 - Theme.panelWidth
        panelX = min(max(panelX, visible.minX + 8), visible.maxX - Theme.panelWidth - 8)
        let top = min(icon.minY - 6, visible.maxY)
        return NSRect(x: (panelX - m).rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
    }

    private func positionPanel() {
        guard let button = item.button, let buttonWindow = button.window else { return }
        let icon = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? icon
        panel.setFrame(Self.windowFrame(icon: icon, visible: visible), display: true)
    }

    /// The panel's own rectangle inside the window, in window coordinates.
    private var panelRectInWindow: NSRect {
        let size = Self.windowSize
        let h = min(max(app.panelHeight, 1), Theme.panelHeight)
        return NSRect(x: Theme.windowMargin, y: size.height - h, width: Theme.panelWidth, height: h)
    }

    private func showPanel() {
        guard let button = item.button else { return }
        pill.dismiss()
        app.isPanelVisible = true
        app.panelDidOpen()               // clears leftovers from last time before it is visible
        positionPanel()
        if Theme.reduceMotion {
            panel.alphaValue = 1
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        button.highlight(true)
        refreshShadow()
        installMonitors()
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        app.isPanelVisible = false
        panel.orderOut(nil)
        item.button?.highlight(false)
        removeMonitors()
        app.panelDidClose()
    }

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps or on the desktop close the panel.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.mouseIsOverIcon else { return }
                self.hidePanel()
            }
        }) { monitors.append(m) }
        // A click on the transparent space around the panel counts as outside.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let inside = MainActor.assumeIsolated { self.panelRectInWindow.contains(event.locationInWindow) }
            if inside { return event }
            MainActor.assumeIsolated { self.hidePanel() }
            return nil
        }) { monitors.append(m) }
        // Esc closes it.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let recording = MainActor.assumeIsolated { self?.app.isRecordingShortcut ?? false }
            if recording { return event }          // the shortcut recorder handles Esc
            MainActor.assumeIsolated { self?.hidePanel() }
            return nil
        }) { monitors.append(m) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

/// A borderless floating panel that can take keyboard focus without activating
/// the app, so the frontmost app keeps its menu bar.
final class PacePanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(root: some View, size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true             // native; recomputed from the panel's shape when it changes
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: root)
        // The controller owns the window size. SwiftUI must not resize the
        // window on its own; that is how the old menu bar window looped.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
