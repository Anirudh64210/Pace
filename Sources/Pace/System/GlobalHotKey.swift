import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut that toggles the panel from any app.
///
/// Uses the Carbon hot key API, which needs no Accessibility or Input
/// Monitoring permission: macOS delivers only this one key combination to
/// Pace and nothing else you type.
@MainActor
final class GlobalHotKey {
    /// The default, Control-Option-P, is rarely taken by other apps, unlike
    /// Command-Option-P (Finder's path bar). Users can record their own.
    static var display: String { Shortcut.default.display }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Carbon calls back through a C function pointer, which cannot capture
    /// context, so the action lives here. There is only ever one hot key.
    private static var action: (() -> Void)?

    private(set) var isRegistered = false

    func register(_ shortcut: Shortcut = .default, action: @escaping () -> Void) {
        unregister()
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { GlobalHotKey.action?() } }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x5041_4345), id: 1)   // "PACE"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        isRegistered = status == noErr
        if !isRegistered { unregister() }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        isRegistered = false
    }
}
