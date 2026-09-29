import AppKit
import SwiftUI

/// The pill that drops from under the menu bar icon when your status changes,
/// like the Focus pill. It never takes focus and never blocks a click: the
/// window ignores the mouse entirely.
@MainActor
final class PillModel: ObservableObject {
    @Published var alert: StatusAlert?
    @Published var visible = false
}

struct StatusPillView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        VStack {
            if let alert = model.alert {
                HStack(spacing: 8) {
                    AppleShape(fill: alert.kind == .good ? 0.2 : 1, size: 16)
                    Text(alert.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(titleColor(alert.kind))
                    Text(alert.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Theme.background.opacity(0.55))
                }
                .overlay(Capsule().strokeBorder(Theme.text.opacity(0.1)))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                .environment(\.colorScheme, .dark)
                .id(alert.id)
                .transition(.opacity)
            }
        }
        .offset(y: model.visible ? 0 : -10)
        .scaleEffect(model.visible ? 1 : 0.96, anchor: .top)
        .opacity(model.visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func titleColor(_ kind: StatusAlert.Kind) -> Color {
        switch kind {
        case .good: return Theme.text
        case .warning: return Theme.accent
        case .reward: return Theme.gold
        }
    }
}

@MainActor
final class PillController {
    static let size = NSSize(width: 420, height: 64)
    static let showFor: TimeInterval = 3.2

    let model = PillModel()
    private let window: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        window = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                         styleMask: [.nonactivatingPanel, .borderless],
                         backing: .buffered, defer: true)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true           // never blocks a click
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle, .stationary]
        let host = NSHostingView(rootView: StatusPillView(model: model))
        host.sizingOptions = []
        window.contentView = host
    }

    /// Centred under the icon, kept on screen.
    static func frame(icon: NSRect, visible: NSRect) -> NSRect {
        var x = icon.midX - size.width / 2
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)
        return NSRect(x: x.rounded(), y: (icon.minY - 2 - size.height).rounded(), width: size.width, height: size.height)
    }

    func show(_ alert: StatusAlert, icon: NSRect, visible: NSRect) {
        hideTask?.cancel()
        let alreadyShowing = window.isVisible && model.visible
        if !alreadyShowing {
            window.setFrame(Self.frame(icon: icon, visible: visible), display: false)
            model.alert = alert
            model.visible = false
            window.orderFrontRegardless()
            withAnimation(Motion.pill) { model.visible = true }
        } else {
            // A newer change replaces the text in place instead of stacking.
            withAnimation(Motion.smooth) { model.alert = alert }
        }
        hideTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(Self.showFor * 1_000_000_000)) } catch { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        guard window.isVisible else { return }
        withAnimation(Motion.smooth) { model.visible = false }
        hideTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            guard let self, !self.model.visible else { return }
            self.window.orderOut(nil)
        }
    }
}
