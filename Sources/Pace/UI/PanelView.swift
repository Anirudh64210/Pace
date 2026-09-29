import SwiftUI

/// The panel. It sits at the top of a fixed, transparent window and animates its
/// own height when a row opens. The window itself never moves or resizes while
/// open, so nothing can jump, and the content's height never depends on the
/// window.
struct PanelView: View {
    @EnvironmentObject var app: AppState
    @State private var popoverOpen = false

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if app.showSettings {
                    SettingsView(settings: app.settings, isPresented: $app.showSettings)
                        .transition(.push(from: .trailing))
                } else {
                    main
                        .transition(.push(from: .leading))
                }
            }
            if let toast = app.toast {
                ToastView(title: toast.title, body: toast.body)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.background)
        .clipped()
        .definerHost()
        .environment(\.colorScheme, .dark)
        .environment(\.panelGeneration, app.panelOpenCount)
        .animation(Motion.smooth, value: app.showSettings)
        .background(GeometryReader { geo in
            Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(PanelHeightKey.self) { height in
            MainActor.assumeIsolated { app.reportPanelHeight(height) }
        }
        .onChange(of: app.showSettings) { _, _ in popoverOpen = false }
        .onChange(of: app.panelOpenCount) { _, _ in popoverOpen = false }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let t = app.panelText {
                hero(t)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                Hairline()
                details(t)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            } else {
                welcome
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
            }
            Hairline()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
        }
        .overlay(alignment: .topTrailing) {
            if popoverOpen {
                tokenPopover
                    .padding(.top, 42)
                    .padding(.trailing, 12)
                    .transition(.scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .background {
            if popoverOpen {
                Color.clear.contentShape(Rectangle()).onTapGesture { closePopover() }
            }
        }
    }

    // MARK: Hero

    /// Two figures of equal weight, how much is used and how long until it
    /// resets, over one bar and one line that says what they mean together.
    private func hero(_ t: PanelText) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(t.heroTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                apple
            }
            HStack(alignment: .top, spacing: 16) {
                Figure(value: "\(t.used)%", caption: t.usedCaption, accent: false, countsDown: false)
                    .definer(t.usedName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Figure(value: t.timer, caption: t.timerCaption, accent: t.timerAccent, countsDown: true)
                    .definer(t.timerName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            UsageBar(used: t.barUsed, height: 6, fill: t.state == .weeklyLimit || t.state == .sessionLimit ? Theme.accent : Theme.barFill)
            if let outlook = t.outlook {
                Text(outlook)
                    .font(.system(size: 12.5))
                    .foregroundStyle(color(t.outlookTone))
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .definer(t.outlookTone == .reward ? "Apple earned" : "Pace forecast")
            }
        }
        .animation(Motion.smooth, value: t.outlook)
    }

    private var apple: some View {
        AppleButton {
            if popoverOpen { closePopover() } else {
                withAnimation(Motion.snappy) { popoverOpen = true }
                app.popoverOpens += 1
                app.settings.unseenApple = false
            }
        }
        .definer("Tokens used")
        .padding(.vertical, -12)      // keep the 44 pt hit area without growing the row
        .padding(.trailing, -10)
    }

    private func closePopover() {
        withAnimation(Motion.snappy) { popoverOpen = false }
    }

    private var tokenPopover: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("About \(Formatting.tokens(app.estimatedTokens)) tokens")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.gold)
            Text("used so far. \(Comparisons.sentence(tokens: app.estimatedTokens, index: app.popoverOpens))")
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.text.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 15, y: 10)
    }

    // MARK: Details

    private func details(_ t: PanelText) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(t.rows) { row in
                DetailRow(row: row, isOpen: app.isOpen(row.id)) {
                    withAnimation(Motion.smooth) { app.toggleRow(row.id) }
                }
                .transition(.opacity)
            }
            if let rows = breakdownRows, !rows.isEmpty {
                breakdown(rows)
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: t.rows.map(\.id))
    }

    private var breakdownRows: [ProductShare]? {
        app.snapshot?.breakdown.filter { $0.percent > 0 }
    }

    private func breakdown(_ rows: [ProductShare]) -> some View {
        DisclosureRow(isOpen: app.isOpen("breakdown"), accessibility: "Weekly share") {
            withAnimation(Motion.smooth) { app.toggleRow("breakdown") }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("This week").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        HStack(spacing: 4) {
                            Circle().fill(Theme.text.opacity(Self.shade(i))).frame(width: 5, height: 5)
                            Text(row.name).foregroundStyle(Theme.muted)
                            Text("\(Int(row.percent.rounded()))").foregroundStyle(Theme.text)
                        }
                    }
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
        } expanded: {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let total = max(1, rows.reduce(0) { $0 + $1.percent })
                    let gaps = CGFloat(rows.count - 1) * 2
                    HStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                            Capsule()
                                .fill(Theme.text.opacity(Self.shade(i)))
                                .frame(width: max(2, (geo.size.width - gaps) * row.percent / total))
                        }
                    }
                }
                .frame(height: 4)
                .padding(.bottom, 2)
                Text(Self.breakdownInsight(rows))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The open part of the product row says something the numbers do not.
    static func breakdownInsight(_ rows: [ProductShare]) -> String {
        guard let top = rows.first else { return "" }
        let name = top.key == "claude_code" ? "Claude Code" : top.name
        if top.percent >= 50 { return "Most of this week went to \(name)." }
        if rows.count > 1 { return "This week is spread across \(rows.count) products, led by \(name)." }
        return "All of this week went to \(name)."
    }

    private static func shade(_ i: Int) -> Double { [0.85, 0.55, 0.32, 0.18][min(i, 3)] }

    // MARK: Welcome (no data yet)

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pace")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Your Claude limits at a glance")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                apple
            }
            OnboardingView()
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if app.isWaitingForSignIn, app.snapshot != nil {
                Text(app.footerText)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .definer("Sign-in renewing")
            } else if app.status.isFailure, app.snapshot != nil {
                Text(app.footerText)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .definer("Sync problem")
                Button("Retry") { app.retryNow() }
                    .buttonStyle(LinkStyle())
                    .disabled(app.isRefreshing)
                    .definer("Try again")
            } else {
                Text(app.footerText)
                    .foregroundStyle(app.isStale ? Theme.accent : Theme.faint)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .definer("Last update")
            }
            Spacer()
            Button(action: app.openUsageSettings) {
                HStack(spacing: 3) {
                    Text("Usage")
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                }
            }
            .buttonStyle(LinkStyle())
            .definer("claude.ai usage")
            Button { app.showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(LinkStyle())
            .definer("Settings")
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 11.5))
    }

    private func color(_ tone: PanelText.Tone) -> Color {
        switch tone {
        case .normal: return Theme.text
        case .muted: return Theme.muted
        case .warning: return Theme.accent
        case .reward: return Theme.gold
        }
    }
}

// MARK: - Pieces

/// A big number with a caption under it. Digits roll when they change.
private struct Figure: View {
    var value: String
    var caption: String
    var accent: Bool
    var countsDown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .kerning(-0.5)
                .foregroundStyle(accent ? Theme.accent : Theme.text)
                .contentTransition(.numericText(countsDown: countsDown))
                .animation(Motion.digits, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
    }
}

/// A list row that highlights on hover and opens on click.
///
/// Hover only draws a highlight and shows the chevron: it never changes size,
/// so nothing moves under the pointer. A click opens or closes the row.
struct DisclosureRow<Header: View, Expanded: View>: View {
    var isOpen: Bool
    var accessibility: String
    var toggle: () -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var expanded: () -> Expanded

    @Environment(\.panelGeneration) private var generation
    @Environment(\.forcedHover) private var forcedHover
    @State private var hoveringNow = false
    private var hovering: Bool { hoveringNow || forcedHover }

    var body: some View {
        Button(action: toggle) { // definer: applied to the row below
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    header()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .opacity(hovering || isOpen ? 1 : 0)
                        .frame(width: 10)
                }
                if isOpen {
                    expanded()
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                        .transition(.opacity.combined(with: .offset(y: -3)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.text.opacity(isOpen ? 0.06 : (hovering ? 0.045 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(RowPressStyle())
        .definer(isOpen ? "Hide details" : "Show details")
        .padding(.horizontal, -10)
        .onHover { hoveringNow = $0 }
        .onChange(of: generation) { _, _ in hoveringNow = false }
        .animation(Motion.snappy, value: hovering)
        .accessibilityLabel(accessibility)
        .accessibilityValue(isOpen ? "expanded" : "collapsed")
        .accessibilityHint("Shows the exact figures")
    }
}

/// A slight dim while pressed, so the click registers.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// One secondary limit: name and detail, value on the right. Opens to its bar
/// and exact figures.
private struct DetailRow: View {
    var row: PanelText.Row
    var isOpen: Bool
    var toggle: () -> Void

    var body: some View {
        DisclosureRow(isOpen: isOpen, accessibility: row.definer, toggle: toggle) {
            // Two lines, like a macOS list row: name and value, then the detail
            // on its own line with the full width, so it is never cut off.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(valueColor)
                        .contentTransition(.numericText())
                        .animation(Motion.digits, value: row.value)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(detailColor)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } expanded: {
            VStack(alignment: .leading, spacing: 6) {
                if let used = row.used {
                    UsageBar(used: used, height: 4, fill: row.valueTone == .warning ? Theme.accent : Theme.barFill, marker: row.marker)
                        .padding(.bottom, 2)
                }
                ForEach(row.lines, id: \.self) { line in
                    Text(line.text)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(line.tone == .warning ? Theme.accent : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var detailColor: Color {
        switch row.detailTone {
        case .warning: return Theme.accent
        case .reward: return Theme.gold
        case .normal: return Theme.secondary
        default: return Theme.faint
        }
    }

    private var valueColor: Color {
        switch row.valueTone {
        case .warning: return Theme.accent
        case .muted: return Theme.muted
        default: return Theme.text
        }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.text.opacity(0.07)).frame(height: 1)
    }
}

/// The panel's rendered height, used only for hit testing (see StatusItemController).
struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Shared motion, so everything moves the same way. Springs, short, no bounce.
enum Motion {
    static var smooth: Animation? { Theme.reduceMotion ? nil : .smooth(duration: 0.35) }
    static var snappy: Animation? { Theme.reduceMotion ? nil : .snappy(duration: 0.22) }
    static var digits: Animation? { Theme.reduceMotion ? nil : .smooth(duration: 0.3) }
    /// The pill drops in with a touch of spring, like the system's.
    static var pill: Animation? { Theme.reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.45, bounce: 0.25) }
}

struct ToastView: View {
    var title: String
    var body_: String
    init(title: String, body: String) { self.title = title; self.body_ = body }

    var body: some View {
        HStack(spacing: 12) {
            AppleShape(fill: 1, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text(body_).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            Text("now").font(.system(size: 11)).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .background(Theme.toast, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.text.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
    }
}

struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Theme.text.opacity(configuration.isPressed ? 0.8 : 0.95), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct LinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Theme.text : Theme.muted)
            .contentShape(Rectangle())
    }
}

/// Shown until the first numbers arrive. One clear step per situation, for each source.
struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.installedOverride) private var installedOverride
    @State private var installed = StatusLineInstaller.status() == .installed
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch app.settings.source {
            case .oauth: oauth
            default: statusLine
            }
        }
        .onAppear { installed = installedOverride ?? (StatusLineInstaller.status() == .installed) }
    }

    @ViewBuilder private var statusLine: some View {
        if !installed {
            step("Connect to Claude Code",
                 "Adds a small status line script to Claude Code. It saves your limits to a local file. No credentials, nothing leaves your Mac.")
            Button("Install status line") { install() }
                .buttonStyle(FooterButtonStyle())
                .definer("Connect Claude")
            if let installError {
                Text(installError).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            hint("For model limits, credits and usage by product, pick the sign-in source in Settings.")
        } else {
            step("Almost there",
                 "Send any message in Claude Code and your limits appear here. If Claude Code was already open, restart it once.")
            hint("Claude Code reports limits on Pro and Max plans. Open this panel any time with \(app.settings.shortcut.display).")
        }
    }

    @ViewBuilder private var oauth: some View {
        switch app.status {
        case .failed(let message, let retryAt):
            step("Couldn't connect", message)
            Button(app.isRefreshing ? "Checking…" : (retryAt == nil ? "Try again" : "Try now")) { app.retryNow() }
                .buttonStyle(FooterButtonStyle())
                .disabled(app.isRefreshing)
                .definer("Check again")
            Button("Use the status line instead") { app.settings.source = .statusLine }
                .buttonStyle(LinkStyle())
                .font(.system(size: 12))
                .definer("Switch source")
        default:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Reading your Claude Code sign-in")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func step(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            Text(body).font(.system(size: 12.5)).lineSpacing(2).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .foregroundStyle(Theme.faint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func install() {
        do {
            try StatusLineInstaller.install()
            installError = nil
            withAnimation(Motion.smooth) { installed = true }
        } catch {
            installError = error.localizedDescription
        }
        app.retryNow()
    }
}
