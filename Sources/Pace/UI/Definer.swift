import SwiftUI

/// Small hover labels ("Session left", "Tokens used") that say what a number is.
///
/// Each labelled view publishes its frame through a preference; the panel draws
/// the one being hovered in a single overlay on top of everything. Drawing it in
/// the view itself would let later siblings paint over it, and would clip at
/// the panel edge.
struct DefinerItem: Equatable {
    var text: String
    var anchor: Anchor<CGRect>
}

struct DefinerKey: PreferenceKey {
    static let defaultValue: DefinerItem? = nil
    static func reduce(value: inout DefinerItem?, nextValue: () -> DefinerItem?) {
        value = nextValue() ?? value
    }
}

/// Changes every time the panel opens. Hover state from the last opening is
/// dropped, because a hidden window never receives a hover-exit.
struct PanelGenerationKey: EnvironmentKey { static let defaultValue = 0 }

/// Lets tests and the screenshot renderer draw every row as hovered.
struct ForcedHoverKey: EnvironmentKey { static let defaultValue = false }

/// Lets the screenshot renderer show one hover label without a mouse.
struct ForcedDefinerKey: EnvironmentKey { static let defaultValue: String? = nil }

/// Lets the screenshot renderer show the first-run Install step on a machine
/// where the status line is already installed.
struct InstalledOverrideKey: EnvironmentKey { static let defaultValue: Bool? = nil }

extension EnvironmentValues {
    var panelGeneration: Int {
        get { self[PanelGenerationKey.self] }
        set { self[PanelGenerationKey.self] = newValue }
    }
    var forcedHover: Bool {
        get { self[ForcedHoverKey.self] }
        set { self[ForcedHoverKey.self] = newValue }
    }
    var forcedDefiner: String? {
        get { self[ForcedDefinerKey.self] }
        set { self[ForcedDefinerKey.self] = newValue }
    }
    var installedOverride: Bool? {
        get { self[InstalledOverrideKey.self] }
        set { self[InstalledOverrideKey.self] = newValue }
    }
}

private struct DefinerModifier: ViewModifier {
    let text: String
    @Environment(\.panelGeneration) private var generation
    @Environment(\.forcedDefiner) private var forced
    @State private var hovering = false
    @State private var shown = false
    @State private var delay: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                delay?.cancel()
                if inside {
                    delay = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        if !Task.isCancelled, hovering { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            .onDisappear { delay?.cancel(); shown = false }
            .onChange(of: generation) { _, _ in
                delay?.cancel()
                hovering = false
                shown = false
            }
            .anchorPreference(key: DefinerKey.self, value: .bounds) { anchor in
                (shown || forced == text) ? DefinerItem(text: text, anchor: anchor) : nil
            }
            .accessibilityHint(text)
    }
}

extension View {
    /// Attach a two-word hover label.
    func definer(_ text: String) -> some View { modifier(DefinerModifier(text: text)) }

    /// Host the hover labels of every descendant. Apply once, at the panel root.
    func definerHost() -> some View {
        overlayPreferenceValue(DefinerKey.self) { item in
            GeometryReader { geo in
                if let item {
                    let rect = geo[item.anchor]
                    DefinerBubble(text: item.text)
                        .fixedSize()
                        .position(x: clamp(rect.midX, lo: 60, hi: geo.size.width - 60),
                                  y: rect.minY > 34 ? rect.minY - 14 : rect.maxY + 14)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(Theme.reduceMotion ? nil : .easeOut(duration: 0.12), value: item?.text)
        }
    }
}

private func clamp(_ x: CGFloat, lo: CGFloat, hi: CGFloat) -> CGFloat { min(max(x, lo), max(lo, hi)) }

struct DefinerBubble: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.toast, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.text.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}
