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

    init() {
        let savedEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.scrollDenoiserEnabled)
        let savedSettings = Self.loadSettings() ?? .default

        self.filter = DirectionLockFilter(settings: savedSettings)
        self.isEnabled = savedEnabled
        self.settings = savedSettings

        // macOS sometimes invalidates a CGEventTap across sleep without
        // firing `.tapDisabledByUserInput` — callback recovery never runs
        // and the filter goes silently dead until toggled off+on.
        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }

        if savedEnabled {
            // No prompt on init — permission was granted previously when the
            // user enabled the feature. A bare `AXIsProcessTrusted()` here
            // also dodges the post-login race where TCC briefly reports
            // not-trusted (and would falsely re-prompt).
            startWithRetry(initialPrompt: false)
        }
    }

    // No deinit: this service lives for the app's lifetime
    // (owned by AppContainer). Swift 6 disallows accessing
    // non-Sendable CFMachPort from a nonisolated deinit,
    // and the process teardown reclaims the tap regardless.

    func start() {
        startWithRetry(initialPrompt: true)
    }

    /// 500ms settle delay lets WindowServer/TCC re-establish trust state
    /// post-wake — without it, `AXIsProcessTrusted()` can briefly return
    /// false even when permission is granted.
    private func handleWake() {
        guard isEnabled else { return }
        stop()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, self.isEnabled else { return }
            self.startWithRetry(initialPrompt: false)
        }
    }

    /// TCC can take several seconds to load the trust DB after fresh login
    /// (and occasionally after wake), so a single AX check right at process
    /// launch returns false even when permission was previously granted.
    /// Retry silently with backoff before leaving the user with an error
    /// banner — the next-day-after-login case where the feature "just
    /// stopped working" was this.
    private func startWithRetry(initialPrompt: Bool) {
        startInternal(promptIfNeeded: initialPrompt)
        if isRunning { return }

        Task { @MainActor [weak self] in
            for delaySec: UInt64 in [1, 2, 4] {
                try? await Task.sleep(nanoseconds: delaySec * 1_000_000_000)
                guard let self, self.isEnabled, !self.isRunning else { return }
                self.startInternal(promptIfNeeded: false)
                if self.isRunning { return }
            }
        }
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

    func stop() {
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
