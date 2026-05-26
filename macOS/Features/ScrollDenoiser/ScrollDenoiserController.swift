import Foundation
import CoreGraphics
import AppKit

// Holder passed to the C callback via `userInfo`. Owns the filter and
// a reference to the tap itself, so the callback can re-enable the tap
// if macOS disables it (long-running callback / user-input flood).
//
// Lifetime: the controller retains this for the duration of start()/stop(),
// so the callback can use `passUnretained` safely.
private final class ScrollDenoiserTapContext: @unchecked Sendable {
    let filter: DirectionLockFilter
    // Assigned exactly once, right after CGEvent.tapCreate returns,
    // before the run-loop source is added. The callback only reads it.
    var tap: CFMachPort?

    init(filter: DirectionLockFilter) { self.filter = filter }
}

// Free-function C callback so the conversion to `@convention(c)`
// CGEventTapCallBack is clean under Swift 6 strict concurrency.
// The context pointer is passed via `userInfo`; no captures.
private let scrollDenoiserTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<ScrollDenoiserTapContext>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // macOS disabled the tap. Re-enable using the retained CFMachPort
        // so subsequent scroll events keep flowing through the filter.
        if let tap = context.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel else {
        return Unmanaged.passUnretained(event)
    }

    // Continuous (trackpad gesture) events bypass the filter — those
    // come from pixel-precise input, not a notched wheel.
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
    if isContinuous != 0 {
        return Unmanaged.passUnretained(event)
    }

    let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let now = CFAbsoluteTimeGetCurrent()

    return context.filter.shouldPass(delta: Int(delta), now: TimeInterval(now))
        ? Unmanaged.passUnretained(event)
        : nil
}

@MainActor
final class ScrollDenoiserController: ObservableObject {

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKeys.scrollDenoiserEnabled)
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    @Published var settings: DirectionLockSettings {
        didSet {
            filter.update(settings: settings)
            persistSettings()
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var totalTicks = 0
    @Published private(set) var droppedTicks = 0

    private let filter: DirectionLockFilter
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapContext: ScrollDenoiserTapContext?
    private var wakeObserver: NSObjectProtocol?
    private var screensWakeObserver: NSObjectProtocol?
    private var sessionActiveObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var healthCheckTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    // True from the moment a recovery rebuild is scheduled until its backoff
    // loop settles. Set/read only on MainActor, so the flag is the cheap,
    // race-free way for the notification storm and the health-check poll to
    // coalesce onto the single in-flight restart instead of piling on.
    private var restartInFlight = false

    init() {
        let savedEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.scrollDenoiserEnabled)
        let savedSettings = Self.loadSettings() ?? .default

        self.filter = DirectionLockFilter(settings: savedSettings)
        self.isEnabled = savedEnabled
        self.settings = savedSettings

        registerRecoveryObservers()
        startHealthCheck()

        if savedEnabled {
            // No prompt on init — permission was granted previously when the
            // user enabled the feature. The silent retry path also dodges the
            // post-login race where TCC briefly reports not-trusted (and would
            // falsely re-prompt).
            scheduleRestart(settleMs: 0)
        }
    }

    /// CGEventTap dies silently for more than just S3 sleep — display sleep,
    /// screen lock, fast user switching, and WindowServer restarts can all
    /// invalidate the tap without firing `.tapDisabledByUserInput`. Listen on
    /// every recovery edge we know about; each one routes through `handleWake`
    /// which rebuilds the tap after a short TCC settle delay.
    private func registerRecoveryObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeHandler: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleWake() }
        }

        wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: nil, using: wakeHandler
        )
        screensWakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: nil, using: wakeHandler
        )
        sessionActiveObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil, queue: nil, using: wakeHandler
        )

        // `com.apple.screenIsUnlocked` is posted by loginwindow when the user
        // unlocks the screen — not covered by NSWorkspace's wake/session
        // notifications, but a frequent killer of long-lived event taps.
        screenUnlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main, using: wakeHandler
        )
    }

    /// Polls `CGEventTapIsEnabled` every 2s. The callback-driven recovery only
    /// fires when macOS sends `.tapDisabledBy*` events, which doesn't happen
    /// for every silent-death path (TCC drift, WindowServer restart, ad-hoc
    /// signature re-evaluation on local builds). The poll cost is negligible
    /// and it's the only way to catch those cases without user interaction.
    /// Defers to any restart already in flight so it never resets a backoff
    /// that's mid-wait.
    private func startHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                guard self.isEnabled, !self.restartInFlight else { continue }
                if self.isTapHealthy { continue }
                self.scheduleRestart(settleMs: 0)
            }
        }
    }

    private var isTapHealthy: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    // No deinit: this service lives for the app's lifetime
    // (owned by AppContainer). Swift 6 disallows accessing
    // non-Sendable CFMachPort from a nonisolated deinit,
    // and the process teardown reclaims the tap regardless.

    /// User-initiated enable (toggle on). Prompt once, then hand off to the
    /// silent retry path if TCC isn't ready yet so the toggle doesn't bounce
    /// back to a permission banner during the brief trust-DB load.
    func start() {
        restartTask?.cancel()
        restartTask = nil
        restartInFlight = false
        ensureHealthy(promptIfNeeded: true)
        if isRunning { return }
        scheduleRestart(settleMs: 0)
    }

    /// Every recovery edge (display/system wake, session activation, screen
    /// unlock) funnels here. A 600ms settle lets WindowServer/TCC re-establish
    /// trust before the first probe.
    private func handleWake() {
        scheduleRestart(settleMs: 600)
    }

    /// THE single, coalesced recovery entry point. macOS fires a burst of
    /// notifications at unlock — didWake + screensDidWake +
    /// sessionDidBecomeActive + screenIsUnlocked — often spread across a
    /// couple of seconds. The old code ran `stop()` + a delayed rebuild on
    /// each one, so every later notification tore down the tap the previous
    /// one had just built, leaving repeated unfiltered-scroll gaps: the
    /// "works, then doesn't, never smooth" symptom. The `restartInFlight`
    /// guard collapses the whole storm into one rebuild.
    ///
    /// The backoff loop covers the post-login case where TCC's trust DB loads
    /// several seconds after the session becomes active, and — because each
    /// pass only rebuilds when the tap is actually unhealthy — it also catches
    /// a late invalidation that lands after the first probe found things fine.
    private func scheduleRestart(settleMs: UInt64) {
        guard isEnabled, !restartInFlight else { return }
        restartInFlight = true
        restartTask = Task { @MainActor [weak self] in
            defer { self?.restartInFlight = false }
            if settleMs > 0 {
                try? await Task.sleep(nanoseconds: settleMs * 1_000_000)
            }
            for backoffMs: UInt64 in [0, 500, 1_000, 2_000, 4_000] {
                if backoffMs > 0 {
                    try? await Task.sleep(nanoseconds: backoffMs * 1_000_000)
                }
                guard let self, self.isEnabled, !Task.isCancelled else { return }
                self.ensureHealthy(promptIfNeeded: false)
                if self.isTapHealthy { return }
            }
        }
    }

    /// Brings the tap to a healthy state with the least disruption possible:
    /// a live tap is left alone; a merely-disabled tap (the common lock/unlock
    /// case) is re-enabled in place with no teardown gap and no TCC round-trip;
    /// only a missing or orphaned tap triggers a full rebuild.
    private func ensureHealthy(promptIfNeeded: Bool) {
        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) {
                isRunning = true
                lastError = nil
                return
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                isRunning = true
                lastError = nil
                return
            }
            // Re-enable didn't take — tap is orphaned (WindowServer restart,
            // session switch). Drop it and build fresh below.
            teardownTap()
        }
        startInternal(promptIfNeeded: promptIfNeeded)
    }

    private func startInternal(promptIfNeeded: Bool) {
        guard tap == nil else { return }

        // `.defaultTap` requires Accessibility access, not Input Monitoring.
        // Wake-driven restarts skip the prompt — permission is already
        // granted, we just need a fresh tap, and popping the system dialog
        // would surprise the user.
        let trusted = promptIfNeeded
            ? PermissionsService.requestAccessibilityPrompt()
            : PermissionsService.isAccessibilityTrusted()
        guard trusted else {
            lastError = "MacCleaner needs Accessibility access to filter scroll events. Open System Settings → Privacy & Security → Accessibility, enable MacCleaner, then toggle the filter again."
            isRunning = false
            return
        }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let context = ScrollDenoiserTapContext(filter: filter)
        let opaque = UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollDenoiserTapCallback,
            userInfo: opaque
        ) else {
            lastError = "Failed to create event tap even though Accessibility is granted. Try toggling the permission off and on, or restart the app."
            isRunning = false
            return
        }

        // Publish tap into the context before run-loop attachment so the
        // very first re-enable callback (should one fire) has a valid ref.
        context.tap = eventTap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.tap = eventTap
        self.runLoopSource = source
        self.tapContext = context
        self.isRunning = true
        self.lastError = nil
    }

    /// User-initiated disable (toggle off). Cancels any pending recovery so a
    /// scheduled rebuild can't resurrect the tap after the user turned it off,
    /// then tears the tap down.
    func stop() {
        restartTask?.cancel()
        restartTask = nil
        restartInFlight = false
        teardownTap()
    }

    /// Releases the CG tap + run-loop source without touching the recovery
    /// machinery. Shared by the public `stop()` and the in-place rebuild in
    /// `ensureHealthy`, which must not cancel the restart task it runs inside.
    private func teardownTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        tapContext = nil
        isRunning = false
    }

    func resetCounters() {
        filter.resetCounters()
        totalTicks = 0
        droppedTicks = 0
    }

    /// Pulls current counters from the filter. Called by the view's
    /// `refreshTask(every:)` so polling auto-pauses while the screen
    /// is off-stack. Guarded against no-op writes so SwiftUI doesn't
    /// re-render when the wheel is idle.
    func refreshStats() {
        let stats = filter.snapshot()
        if stats.total != totalTicks { totalTicks = stats.total }
        if stats.dropped != droppedTicks { droppedTicks = stats.dropped }
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: DefaultsKeys.scrollDenoiserSettings)
        }
    }

    private static func loadSettings() -> DirectionLockSettings? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKeys.scrollDenoiserSettings),
              let cfg = try? JSONDecoder().decode(DirectionLockSettings.self, from: data)
        else { return nil }
        return cfg
    }
}
