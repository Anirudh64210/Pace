import SwiftUI
import AppKit

/// The apple, filled from the bottom to `fill` (0...1). Drawn from the SVG paths.
struct AppleShape: View {
    var fill: Double
    var size: CGFloat

    var body: some View {
        let scale = size / 24
        let body = Path(AppleArt.bodyPath).applying(.init(scaleX: scale, y: scale))
        let stem = Path(AppleArt.stemPath).applying(.init(scaleX: scale, y: scale))
        let leaf = Path(AppleArt.leafPath).applying(.init(scaleX: scale, y: scale))
        let top = AppleArt.bodyTop * scale
        let bottom = AppleArt.bodyBottom * scale
        let fillY = bottom - (bottom - top) * CGFloat(min(1, max(0, fill)))

        ZStack {
            body.fill(Theme.appleEmpty)
            Rectangle()
                .fill(Theme.apple)
                .frame(width: size, height: max(0, bottom - fillY))
                .position(x: size / 2, y: fillY + max(0, bottom - fillY) / 2)
                .clipShape(body)
                .animation(Theme.reduceMotion ? nil : .easeInOut(duration: 0.3), value: fill)
            body.stroke(Theme.apple, style: StrokeStyle(lineWidth: 1.3 * scale, lineJoin: .round))
            Ellipse()
                .fill(Theme.text.opacity(0.35))
                .frame(width: 1.8 * scale, height: 3.8 * scale)
                .rotationEffect(.degrees(-18))
                .position(x: 7.9 * scale, y: 12 * scale)
            stem.stroke(Theme.stem, style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
            leaf.fill(Theme.leaf)
        }
        .frame(width: size, height: size)
    }
}

/// Renders the apple as an NSImage for the menu bar item.
enum AppleImage {
    /// The label is re-evaluated every second for the countdown. Handing the
    /// status item a new image object each time makes AppKit re-lay it out, which
    /// shifts the open panel. Fill is bucketed to 5% and each bucket is drawn once.
    @MainActor private static var cache: [Int: NSImage] = [:]

    @MainActor
    static func menuBar(fill: Double) -> NSImage {
        let bucket = Int((min(1, max(0, fill)) * 20).rounded())
        if let cached = cache[bucket] { return cached }
        let image = draw(fill: Double(bucket) / 20, size: 18)
        cache[bucket] = image
        return image
    }

    private static func draw(fill: Double, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = size / 24
            ctx.scaleBy(x: scale, y: scale)
            let body = AppleArt.bodyPath

            ctx.addPath(body)
            ctx.setFillColor(NSColor(hex: 0xD97757, alpha: 0.18).cgColor)
            ctx.fillPath()

            let top = AppleArt.bodyTop, bottom = AppleArt.bodyBottom
            let fillY = bottom - (bottom - top) * CGFloat(min(1, max(0, fill)))
            ctx.saveGState()
            ctx.addPath(body)
            ctx.clip()
            ctx.setFillColor(NSColor(hex: 0xD97757).cgColor)
            ctx.fill(CGRect(x: 0, y: fillY, width: 24, height: bottom - fillY + 1))
            ctx.restoreGState()

            ctx.addPath(body)
            ctx.setStrokeColor(NSColor(hex: 0xD97757).cgColor)
            ctx.setLineWidth(1.4)
            ctx.setLineJoin(.round)
            ctx.strokePath()

            ctx.addPath(AppleArt.stemPath)
            ctx.setStrokeColor(NSColor(hex: 0x8A5A3A).cgColor)
            ctx.setLineWidth(1.6)
            ctx.setLineCap(.round)
            ctx.strokePath()

            ctx.addPath(AppleArt.leafPath)
            ctx.setFillColor(NSColor(hex: 0x8FB07A).cgColor)
            ctx.fillPath()
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct Ping {
    var scale = 1.0
    var opacity = 0.7
}

/// The apple button in the panel header: fill, idle wiggle, hover lift,
/// unseen dot, pop and floating "+1" on harvest.
struct AppleButton: View {
    @EnvironmentObject var app: AppState
    var action: () -> Void

    @State private var hovering = false
    @State private var wiggleTick = 0
    @State private var popTick = 0
    @State private var plusOne = false

    private let wiggleTimer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) { // definer: "Tokens used", set where the apple is placed
                AppleShape(fill: app.appleFill, size: 28)
                    .offset(y: hovering ? -2 : 0)
                    .scaleEffect(hovering ? 1.06 : 1)
                    .animation(.easeOut(duration: 0.2), value: hovering)
                    .keyframeAnimator(initialValue: 0.0, trigger: wiggleTick) { content, angle in
                        content.rotationEffect(.degrees(angle))
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(-9, duration: 0.2)
                            CubicKeyframe(7, duration: 0.2)
                            CubicKeyframe(-4, duration: 0.2)
                            CubicKeyframe(2, duration: 0.2)
                            CubicKeyframe(0, duration: 0.15)
                        }
                    }
                    .keyframeAnimator(initialValue: 1.0, trigger: popTick) { content, scale in
                        content.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            CubicKeyframe(1.25, duration: 0.18)
                            CubicKeyframe(1.0, duration: 0.27)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel("Tokens used so far")

            if app.settings.unseenApple {
                ZStack {
                    if !Theme.reduceMotion {
                        // keyframeAnimator scopes the pulse to this circle. A
                        // repeatForever withAnimation started in onAppear would also
                        // capture the panel's first layout and animate it forever.
                        Circle()
                            .fill(Theme.gold)
                            .frame(width: 8, height: 8)
                            .keyframeAnimator(initialValue: Ping(), repeating: true) { content, v in
                                content.scaleEffect(v.scale).opacity(v.opacity)
                            } keyframes: { _ in
                                KeyframeTrack(\.scale) { CubicKeyframe(2.6, duration: 1.6) }
                                KeyframeTrack(\.opacity) { CubicKeyframe(0, duration: 1.6) }
                            }
                    }
                    Circle()
                        .fill(Theme.gold)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.background, lineWidth: 1.5))
                }
                .padding(8)
                .allowsHitTesting(false)
            }

            if plusOne {
                Text("+1")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .offset(x: -30, y: -2)
                    .transition(.asymmetric(insertion: .offset(y: 4).combined(with: .opacity),
                                            removal: .offset(y: -14).combined(with: .opacity)))
            }
        }
        .onChange(of: app.panelOpenCount) { _, _ in hovering = false }
        .onReceive(wiggleTimer) { _ in
            if !Theme.reduceMotion, !app.justHarvested { wiggleTick += 1 }
        }
        .onChange(of: app.justHarvested) { _, harvested in
            guard harvested, !Theme.reduceMotion else { return }
            popTick += 1
            withAnimation(.easeOut(duration: 0.4)) { plusOne = true }
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(.easeIn(duration: 0.4)) { plusOne = false }
            }
        }
    }
}
