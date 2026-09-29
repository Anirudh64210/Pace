import Foundation
import Combine
import AppKit
import SwiftUI

/// Owns the data source, the poll loop, the sync status, reset events and the
/// reward loop. Every screen reads from here, so they always agree.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var status: SyncStatus = .idle
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastAttempt: Date?

    // Reward loop and transient UI flags.
    @Published var justHarvested = false
    @Published var weekFresh = false
    @Published var toast: (title: String, body: String)?
    @Published private(set) var tokenTotal: Int?
    @Published var popoverOpens = 0
    /// Which screen the panel shows. Reset to the main screen whenever it closes.
    @Published var showSettings = false
    /// Bumped every time the panel opens, so hover labels and popovers left
    /// over from the last time are cleared.
    @Published private(set) var panelOpenCount = 0
    /// The panel's measured content height. The window never resizes to it; the
    /// controller only uses it to tell clicks on the panel from clicks on the
    /// transparent space below it.
    @Published private(set) var panelHeight: CGFloat = 0

    func reportPanelHeight(_ height: CGFloat) {
        guard height > 0, abs(height - panelHeight) > 0.5 else { return }
        panelHeight = height
    }

    /// True while Settings is recording a new shortcut: Esc and the current
    /// shortcut go to the recorder instead of closing or toggling the panel.
    @Published var isRecordingShortcut = false

    /// Rows open on click, never on hover, and each one independently, so
    /// several can be compared at once. Remembered between openings.
    func isOpen(_ id: String) -> Bool { settings.openRows.contains(id) }

    func toggleRow(_ id: String) {
        if settings.openRows.contains(id) { settings.openRows.remove(id) } else { settings.openRows.insert(id) }
    }

    /// Called when the panel closes: back to the main screen. Open rows stay open.
    func panelDidClose() {
        showSettings = false
    }

    let settings: Settings
    let isDemo: Bool
    private var provider: UsageProvider
    /// One sign-in provider for the app's lifetime, so its in-memory token
    /// survives source switches (no repeated Keychain reads).
    private lazy var oauthProvider = OAuthUsageProvider()
    /// Bumped whenever the provider changes, so a fetch that started against the
    /// old source cannot land on screen after the switch.
    private var generation = 0
    private var failures = 0
    private var lastError: ProviderError?
    /// A 429 applies to the account, not the source. Kept across switches and retries.
    private var rateLimitedUntil: Date?
    private var pendingRetry = false
    /// Set by a source switch until the new source answers once. The old numbers
    /// stay on screen meanwhile, so nothing flashes empty.
    private var switching = false
    private let tokenReader = TokenLogReader()
    private var clock: Timer?
    private var pollTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var harvestTask: Task<Void, Never>?
    private var asleep = false
    private var cancellables = Set<AnyCancellable>()
    private var cachedText: (key: TextKey, value: PanelText?)?

    /// Tests pass `providerFactory` so that switching sources never touches the
    /// real Keychain or the network.
    init(settings: Settings, demo: Bool = false, autoPoll: Bool = true, provider: UsageProvider? = nil,
         providerFactory: ((UsageSource) -> UsageProvider)? = nil) {
        self.settings = settings
        self.isDemo = demo
        self.providerFactory = providerFactory
        self.provider = provider ?? DemoProvider()
        if provider == nil { self.provider = makeProvider(demo ? .demo : settings.source) }

        settings.$source
            .dropFirst()
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] source in
                guard let self, !self.isDemo, source != self.provider.kind else { return }
                self.switchProvider(to: source)
            }
            .store(in: &cancellables)

        // Views read settings through AppState; forward its changes so they redraw.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        guard autoPoll else { return }

        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        clock.map { RunLoop.main.add($0, forMode: .common) }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.asleep = true }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        }

        if settings.notificationsEnabled, !demo { Notifier.shared.requestPermissionIfNeeded() }
        restartPolling()
        Task { await refreshTokens() }
    }

    private let providerFactory: ((UsageSource) -> UsageProvider)?

    private func makeProvider(_ source: UsageSource) -> UsageProvider {
        if let providerFactory { return providerFactory(source) }
        switch source {
        case .statusLine: return StatusLineProvider()
        case .oauth: return oauthProvider
        case .demo: return DemoProvider()
        }
    }

    // MARK: - Clock

    private func tick() {
        now = Date()
        checkLapsedWindows()
    }

    /// The status line file only changes while Claude Code runs. When a limit
    /// window ends while it is idle, notice it on the clock instead of waiting
    /// for the next message.
    private func checkLapsedWindows() {
        guard let s = snapshot else { return }
        var events: [(PaceEvent, Date?)] = []
        if let w = s.session, let r = w.resetsAt, r <= now, w.utilization > 0 { events.append((.sessionReset, r)) }
        if let w = s.week, let r = w.resetsAt, r <= now, w.utilization > 0 { events.append((.weeklyReset, r)) }
        if !events.isEmpty { handle(events) }
    }

    // MARK: - Derived

    var state: PaceState {
        snapshot.map { PaceState.derive(from: $0, now: now) } ?? .freshSession
    }

    private struct TextKey: Equatable {
        var now: Int, snapshot: UsageSnapshot?, weekFresh: Bool, apples: Int, harvested: Bool
    }

    /// Built at most once per second, however many views ask.
    var panelText: PanelText? {
        let key = TextKey(now: Int(now.timeIntervalSince1970), snapshot: snapshot, weekFresh: weekFresh,
                          apples: settings.apples, harvested: harvestedThisWindow)
        if let cachedText, cachedText.key == key { return cachedText.value }
        let value = snapshot.map {
            PanelText(.init(snapshot: $0, now: now, weekFresh: weekFresh, apples: settings.apples,
                            harvested: harvestedThisWindow))
        }
        cachedText = (key, value)
        return value
    }

    /// Whether this session window's apple was actually awarded.
    var harvestedThisWindow: Bool {
        guard let key = snapshot?.session?.resetsAt, let mark = settings.eventGate.harvest?.key else { return isDemo }
        return abs(mark.timeIntervalSince(key)) < 60
    }

    /// Session fill for the apple, 0...1.
    var appleFill: Double {
        guard let s = snapshot else { return 0 }
        switch state {
        case .freshSession: return 0
        case .sessionLimit, .weeklyLimit: return 1
        case .normal: return min(1, max(0, (s.normalized(now: now).session?.utilization ?? 0) / 100))
        }
    }

    /// Total tokens: real Claude Code numbers when available, otherwise an estimate
    /// from harvested sessions plus the current one. Always shown as "about".
    var estimatedTokens: Int {
        if let tokenTotal, tokenTotal > 0 { return tokenTotal }
        let current = Double(Comparisons.tokensPerSession) * appleFill
        return settings.apples * Comparisons.tokensPerSession + Int(current)
    }

    /// Only the sign-in source is expected to be fresh. The status line is quiet
    /// whenever Claude Code is, and that is normal.
    var isStale: Bool {
        guard let s = snapshot, provider.kind == .oauth else { return false }
        return now.timeIntervalSince(s.fetchedAt) > 15 * 60
    }

    /// The sign-in has expired (or is missing) and Pace is waiting for Claude Code
    /// to renew it. Not an error the user caused, so it is shown calmly.
    var isWaitingForSignIn: Bool {
        guard status.isFailure else { return false }
        return lastError?.isRecheckable == true
    }

    /// One short line for the panel footer.
    var footerText: String {
        if isWaitingForSignIn, let s = snapshot {
            return "Paused · numbers from \(Formatting.clockTime(s.fetchedAt))"
        }
        if isRefreshing, status.isFailure { return "Retrying…" }
        switch status {
        case .failed(_, let retryAt):
            if let retryAt, retryAt > now {
                return "Couldn't update · retrying in \(Formatting.shortCountdown(to: retryAt, now: now))"
            }
            return "Couldn't update"
        default:
            guard let s = snapshot else { return "" }
            return "synced \(Formatting.relativeAge(of: s.fetchedAt, now: now))"
        }
    }

    // MARK: - Polling

    var source: UsageSource { provider.kind }

    /// Seconds until the next scheduled attempt, given the current state.
    var nextDelay: TimeInterval {
        if case .failed(_, let retryAt) = status {
            guard let retryAt else { return .infinity }      // needs the user
            return max(1, retryAt.timeIntervalSinceNow)
        }
        return SyncPolicy.interval(for: provider.kind, urgent: SyncPolicy.isUrgent(snapshot, now: Date()))
    }

    private func switchProvider(to source: UsageSource) {
        provider = makeProvider(source)
        generation += 1
        failures = 0
        lastError = nil
        pendingRetry = false
        switching = snapshot != nil
        if snapshot == nil { status = .connecting }
        isRefreshing = false
        restartPolling()
    }

    func restartPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.asleep { await self.refresh() }
                let delay = self.nextDelay
                guard delay.isFinite, !Task.isCancelled else { return }   // wait for the user
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Retry, Refresh Now, Check now. Never interrupts a fetch in flight and never
    /// jumps a rate limit.
    func retryNow() {
        if isRefreshing {
            pendingRetry = true
            return
        }
        if let until = rateLimitedUntil, until > Date(), provider.kind == .oauth {
            status = .failed(ProviderError.rateLimited(retryAfter: nil).localizedDescription, retryAt: until)
            return
        }
        failures = 0
        if snapshot == nil { status = .connecting }
        restartPolling()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        if provider.kind == .oauth, let until = rateLimitedUntil, until > Date() {
            status = .failed(ProviderError.rateLimited(retryAfter: nil).localizedDescription, retryAt: until)
            return
        }
        isRefreshing = true
        let gen = generation
        let provider = self.provider
        lastAttempt = Date()
        if snapshot == nil, !status.isFailure { status = .connecting }

        let result: Result<UsageSnapshot, Error>
        do { result = .success(try await provider.fetch()) } catch { result = .failure(error) }

        guard gen == generation else { return }     // the source changed meanwhile
        isRefreshing = false
        apply(result, from: provider.kind)

        if pendingRetry {
            pendingRetry = false
            if status.isFailure { retryNow() }
        }
    }

    private func apply(_ result: Result<UsageSnapshot, Error>, from source: UsageSource) {
        // The first answer from a new source: its numbers are not comparable with
        // the old source's, so no reset events are derived from the switch.
        let wasSwitching = switching
        switching = false
        if wasSwitching, case .failure = result { snapshot = nil }

        switch result {
        case .success(let next):
            let previous = wasSwitching ? nil : snapshot
            snapshot = next
            failures = 0
            lastError = nil
            rateLimitedUntil = nil
            status = .live
            var events = StateMachine.events(from: previous, to: next, now: Date()).map { event -> (PaceEvent, Date?) in
                switch event {
                case .sessionReset: return (event, previous?.session?.resetsAt)
                case .weeklyReset: return (event, previous?.week?.resetsAt)
                case .sessionLimitHit, .paceWarning: return (event, next.session?.resetsAt)
                case .weeklyLimitHit: return (event, next.week?.resetsAt)
                }
            }
            // Running fast: the first time this session's forecast says it will
            // run out before the reset. Once per session window (the gate).
            if let w = next.session,
               PanelText.runsOut(used: w.utilization, resetsAt: w.resetsAt, length: PanelText.sessionLength, now: Date()) != nil {
                events.append((.paceWarning, w.resetsAt))
            }
            handle(events)

        case .failure(let error):
            // A cancelled request is not a failure: nothing changes.
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            let err = error as? ProviderError
            lastError = err
            let message = err?.localizedDescription ?? error.localizedDescription

            if let err, err.isWaiting {
                failures = 0
                snapshot = nil          // e.g. the status line was removed
                status = .waiting(message)
                return
            }
            failures += 1
            switch err {
            case .some(let e) where e.needsUser:
                status = .failed(message, retryAt: nil)
            case .some(let e) where e.isRecheckable:
                status = .failed(message, retryAt: Date().addingTimeInterval(SyncPolicy.signInRecheck))
            case .some(.offline):
                status = .failed(message, retryAt: Date().addingTimeInterval(SyncPolicy.offlineRetry))
            case .some(.rateLimited(let retryAfter)):
                let delay = SyncPolicy.backoff(for: source, failures: failures, retryAfter: retryAfter)
                rateLimitedUntil = Date().addingTimeInterval(delay)
                status = .failed(message, retryAt: rateLimitedUntil)
            default:
                let delay = SyncPolicy.backoff(for: source, failures: failures, retryAfter: nil)
                status = .failed(message, retryAt: Date().addingTimeInterval(delay))
            }
        }
    }

    private func didWake() {
        asleep = false
        failures = 0
        if case .failed(_, nil) = status { return }        // needs the user; do not prompt again
        // Give the network a moment to come back before the first fetch.
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.restartPolling()
        }
    }

    func refreshTokens() async {
        let total = await tokenReader.total()
        tokenTotal = total
    }

    // MARK: - Events

    private func handle(_ events: [(PaceEvent, Date?)]) {
        for (event, key) in events {
            // Demo data cycles on purpose, so it skips the once-per-window gate.
            if !isDemo {
                var gate = settings.eventGate
                guard gate.admit(event, key: key, now: Date()) else { continue }
                settings.eventGate = gate
            }
            switch event {
            case .sessionLimitHit:
                settings.apples += 1
                settings.unseenApple = true
                justHarvested = true
                harvestTask?.cancel()
                harvestTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
                    self?.justHarvested = false
                }
            case .weeklyReset:
                weekFresh = true
            case .sessionReset, .weeklyLimitHit, .paceWarning:
                break
            }
            announce(StatusAlert.make(event, snapshot: snapshot, now: Date()))
        }
        // "Fresh week" wears off once the week is in use again.
        if weekFresh, let w = snapshot?.week, w.utilization >= 5, w.resetsAt.map({ $0 > now }) ?? true { weekFresh = false }
    }

    // MARK: - Announcing changes

    /// The latest status change, for the pill under the menu bar icon. The status
    /// item controller shows it when the panel is closed.
    @Published private(set) var pill: StatusAlert?
    /// Set by the status item controller.
    var isPanelVisible = false

    /// One place decides where a change is shown: inside the panel when it is
    /// open, otherwise the pill. A system notification is an optional extra.
    func announce(_ alert: StatusAlert) {
        if isPanelVisible {
            showToast(title: alert.title, body: alert.detail)
        } else if settings.showPill {
            pill = alert
        }
        // Demo data is for looking at the panel. It never posts system notifications.
        guard settings.notificationsEnabled, !isDemo else { return }
        Notifier.shared.send(title: alert.notificationTitle, body: alert.detail.prefix(1).uppercased() + alert.detail.dropFirst() + ".")
    }

    func showToast(title: String, body: String) {
        let anim: Animation? = Theme.reduceMotion ? nil : .easeOut(duration: 0.4)
        withAnimation(anim) { toast = (title, body) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            // A newer toast cancels this task; it must not clear the newer toast.
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            withAnimation(anim) { self?.toast = nil }
        }
    }

    /// Snapshot rendering and tests only.
    func setStatusForPreview(_ status: SyncStatus) { self.status = status }

    /// Opening the panel refreshes stale data. It never hammers the source,
    /// never jumps a backoff, and re-checks a sign-in the user may have fixed.
    func panelDidOpen() {
        panelOpenCount += 1
        Task { await refreshTokens() }
        if case .failed = status {
            if lastError?.isRecheckable == true,
               Date().timeIntervalSince(lastAttempt ?? .distantPast) > 5 {
                retryNow()
            }
            return
        }
        if let last = lastAttempt, Date().timeIntervalSince(last) < SyncPolicy.openRefreshAge(for: provider.kind) { return }
        Task { await refresh() }
    }

    func openUsageSettings() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }
}
