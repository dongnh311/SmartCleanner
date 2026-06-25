import Foundation
import SwiftUI
import UserNotifications

/// Always-on, userspace protection layer that rides on the menu-bar agent.
///
/// What it does (no special entitlement, works under ad-hoc signing):
///   • watches the three LaunchAgent/Daemon dirs and scores any new plist
///     with `MalwareScanner` heuristics → neutralises persistence;
///   • hashes files dropped into Downloads/Desktop/Documents against a
///     local SHA-256 blocklist;
///   • runs a `RansomwareGuard` (canary files + write-burst detector).
///
/// Response policy (the "auto-quarantine + alert" tier): **DANGER**
/// detections are moved to the reversible 7-day quarantine automatically;
/// **REVIEW** detections and ransomware signals are surfaced as alerts only
/// — we never auto-move a user's own documents, and stopping a live
/// process would need the Endpoint Security entitlement this build lacks.
@MainActor
final class RealtimeProtectionService: ObservableObject {

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isRunning = false
    @Published private(set) var watchedPathCount = 0
    @Published private(set) var recentEvents: [RealtimeEvent] = []
    @Published private(set) var signatureCount: Int = 0

    private let quarantine: QuarantineService
    private let hashStore: MalwareHashStore
    private let guardian = RansomwareGuard()
    private let vtClient = VirusTotalClient()
    /// Exposed so Settings can trigger a manual blocklist feed refresh.
    let feedUpdater: MalwareFeedUpdater
    private var watcher: FileSystemWatcher?

    /// path|kind → last surfaced; suppresses FSEvents duplicates.
    private var recentlyHandled: [String: Date] = [:]
    private let dedupWindow: TimeInterval = 30

    /// Notification debounce — events arriving within this window collapse
    /// into a single banner so a malware dump can't spam Notification Center.
    private var pendingNotify: [RealtimeEvent] = []
    private var notifyTask: Task<Void, Never>?
    private let notifyDebounce: TimeInterval = 1.5

    private static let maxEvents = 60

    init(quarantine: QuarantineService) {
        self.quarantine = quarantine
        let store = MalwareHashStore()
        self.hashStore = store
        self.feedUpdater = MalwareFeedUpdater(store: store)
        self.signatureCount = store.count
        self.isEnabled = UserDefaults.standard.bool(forKey: DefaultsKeys.realtimeProtectionEnabled)
    }

    // MARK: - Watched locations

    private var home: String { NSHomeDirectory() }
    private var persistenceDirs: [String] {
        ["\(home)/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
    }
    private var fileDropDirs: [String] {
        ["\(home)/Downloads", "\(home)/Desktop", "\(home)/Documents"]
    }
    /// Where decoys live. Content-verified, so even Pictures (heavy
    /// thumbnail/metadata churn) is safe to seed.
    private var canaryDirs: [String] {
        ["\(home)/Documents", "\(home)/Desktop", "\(home)/Pictures"]
    }
    /// Where the write-burst heuristic counts modifications. Excludes
    /// Pictures (Photos/QuickLook churn) and Downloads (bulk grabs) to keep
    /// the behavioural signal from false-firing.
    private var burstDirs: [String] {
        ["\(home)/Documents", "\(home)/Desktop"]
    }

    // MARK: - Lifecycle

    /// Called at launch by `AppContainer`.
    func startIfEnabled() {
        if isEnabled { start() }
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        UserDefaults.standard.set(on, forKey: DefaultsKeys.realtimeProtectionEnabled)
        if on { start() } else { stop() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true   // immediate UI feedback; the toggle never stalls
        Task { await AlertEngine.shared.requestAuthorizationIfNeeded() }

        // Snapshot the Sendable collaborators so the background analysis
        // never reaches back into main-actor state.
        let hashStore = self.hashStore
        let guardian = self.guardian
        let persistence = Set(persistenceDirs)
        let drops = Set(fileDropDirs)
        let bursts = Set(burstDirs)
        let canaries = canaryDirs
        let allPaths = Array(Set(persistenceDirs + fileDropDirs + canaryDirs))

        let vtClient = self.vtClient
        let watcher = FileSystemWatcher { [weak self] events in
            Task.detached(priority: .utility) {
                let result = Self.analyze(
                    events,
                    hashStore: hashStore,
                    guardian: guardian,
                    persistenceDirs: persistence,
                    fileDropDirs: drops,
                    burstDirs: bursts
                )
                var detections = result.detections
                // Unknown downloaded files → ask VirusTotal (opt-in, rate-limited).
                if VirusTotalClient.isEnabled {
                    for cand in result.vtCandidates {
                        guard case .success(let v) = await vtClient.lookup(sha256: cand.hash),
                              v.malicious > 0 else { continue }
                        let danger = v.malicious >= VirusTotalClient.quarantineThreshold
                        detections.append(Detection(
                            kind: .maliciousFile,
                            severity: danger ? .danger : .warn,
                            path: cand.path,
                            title: "VirusTotal: \(v.malicious)/\(v.total) flagged \((cand.path as NSString).lastPathComponent)",
                            detail: "\(v.malicious) of \(v.total) engines on VirusTotal flagged this download as malicious.",
                            quarantine: danger))
                    }
                }
                guard !detections.isEmpty else { return }
                await self?.apply(detections)
            }
        }
        self.watcher = watcher

        // Planting canaries hits the disk; do it off the main actor, then
        // arm the watcher and publish the location count back on main.
        Task.detached(priority: .utility) { [weak self] in
            guardian.plantCanaries(in: canaries)
            let count = allPaths.filter { FileManager.default.fileExists(atPath: $0) }.count
            watcher.start(paths: allPaths)
            // Hop back via a @MainActor method rather than `MainActor.run {
            // self?... }` — capturing self in that closure trips Swift 6's
            // region-isolation "sending 'self' risks data races" check on
            // newer toolchains (CI's Xcode caught it; local's didn't).
            await self?.setWatchedPathCount(count)
        }
        Log.scanner.info("Realtime protection starting")
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        guardian.removeCanaries()
        notifyTask?.cancel()
        pendingNotify.removeAll()
        isRunning = false
        Log.scanner.info("Realtime protection stopped")
    }

    func clearEvents() { recentEvents.removeAll() }

    private func setWatchedPathCount(_ count: Int) { watchedPathCount = count }

    /// Diagnostic/smoke-test hook — is this digest on the active blocklist?
    func isOnBlocklist(_ hash: String) -> Bool { hashStore.contains(hash) }

    /// Settings "Update now" — downloads the configured feed and refreshes
    /// the published signature count.
    func updateFeed() async -> Result<MalwareFeedUpdater.Summary, MalwareFeedUpdater.UpdateError> {
        let result = await feedUpdater.update()
        signatureCount = hashStore.count
        return result
    }

    /// Settings "Test key" — true if the VirusTotal key authenticates.
    func validateVirusTotalKey() async -> Bool {
        await vtClient.validateKey()
    }

    // MARK: - Analysis (off the main actor)

    private struct Detection: Sendable {
        let kind: RealtimeEvent.Kind
        let severity: ThreatItem.Severity
        let path: String
        let title: String
        let detail: String
        /// Only DANGER-class detections are auto-quarantined.
        let quarantine: Bool
    }

    /// An unknown (not locally blocklisted) downloaded file whose hash is
    /// worth a VirusTotal lookup. Hashing happens during analysis; the
    /// (rate-limited, async) VT call happens after, off the main actor.
    private struct VTCandidate: Sendable {
        let path: String
        let hash: String
    }

    private struct AnalyzeResult: Sendable {
        var detections: [Detection] = []
        var vtCandidates: [VTCandidate] = []
    }

    private nonisolated static func analyze(
        _ events: [RealtimeFileEvent],
        hashStore: MalwareHashStore,
        guardian: RansomwareGuard,
        persistenceDirs: Set<String>,
        fileDropDirs: Set<String>,
        burstDirs: Set<String>
    ) -> AnalyzeResult {
        var result = AnalyzeResult()
        for event in events {
            let path = event.path
            let parent = (path as NSString).deletingLastPathComponent

            // 1) Ransomware canary — content-verified so the planting event
            // and benign metadata/thumbnail touches (bytes unchanged) never
            // alarm; only a real content change or deletion does.
            if guardian.isCanary(path) {
                if guardian.isCanaryTampered(path) {
                    result.detections.append(Detection(
                        kind: .ransomwareCanary, severity: .danger, path: path,
                        title: "Ransomware canary altered",
                        detail: "A decoy file's contents changed or it was deleted. Mass file encryption may be in progress — disconnect from the network and check running processes.",
                        quarantine: false))
                }
                continue
            }

            // 2) New persistence plist.
            if parent.hasSuffix("LaunchAgents") || parent.hasSuffix("LaunchDaemons"),
               persistenceDirs.contains(parent),
               path.hasSuffix(".plist"),
               event.isCreated || event.isRenamed || event.isModified {
                let kind: ThreatItem.ThreatKind = parent.hasSuffix("LaunchDaemons") ? .launchDaemon : .launchAgent
                if let threat = MalwareScanner.evaluatePlist(at: URL(fileURLWithPath: path), kind: kind),
                   threat.severity >= .warn {
                    result.detections.append(Detection(
                        kind: .persistence, severity: threat.severity, path: path,
                        title: "New persistence item: \(threat.title)",
                        detail: threat.signals.joined(separator: " · "),
                        quarantine: threat.severity == .danger))
                }
                continue
            }

            // 3) File dropped into a watched folder → local hash blocklist,
            //    then (for actually-downloaded files) queue a VT lookup.
            if event.isFile, (event.isCreated || event.isRenamed),
               isUnder(parent, roots: fileDropDirs) {
                if let hash = MalwareHashStore.sha256Hex(ofFileAt: URL(fileURLWithPath: path)) {
                    if hashStore.contains(hash) {
                        result.detections.append(Detection(
                            kind: .maliciousFile, severity: .danger, path: path,
                            title: "Known-malicious file: \((path as NSString).lastPathComponent)",
                            detail: "SHA-256 matches the local blocklist.",
                            quarantine: true))
                    } else if hasQuarantineXattr(path) {
                        // Only internet-downloaded files (quarantine xattr)
                        // are sent to VirusTotal — conserves the API quota.
                        result.vtCandidates.append(VTCandidate(path: path, hash: hash))
                    }
                }
                continue
            }

            // 4) Write-burst behavioural signal on existing documents.
            if event.isFile, event.isModified, !event.isCreated,
               isUnder(parent, roots: burstDirs),
               guardian.noteModificationAndCheckBurst() {
                result.detections.append(Detection(
                    kind: .ransomwareBurst, severity: .warn, path: parent,
                    title: "Unusual burst of file changes",
                    detail: "Many documents in \((parent as NSString).lastPathComponent) changed at once — consistent with bulk encryption. Review what is writing to this folder.",
                    quarantine: false))
            }
        }
        return result
    }

    private nonisolated static func isUnder(_ path: String, roots: Set<String>) -> Bool {
        roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// True when the file carries the `com.apple.quarantine` xattr — i.e.
    /// it was downloaded from the internet rather than created locally.
    private nonisolated static func hasQuarantineXattr(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) > 0
    }

    // MARK: - Response (main actor)

    private func apply(_ detections: [Detection]) async {
        let now = Date()
        var surfaced: [RealtimeEvent] = []
        for d in detections {
            let key = "\(d.kind.rawValue)|\(d.path)"
            if let last = recentlyHandled[key], now.timeIntervalSince(last) < dedupWindow { continue }
            recentlyHandled[key] = now

            var action: RealtimeEvent.Action = .alerted
            if d.quarantine {
                // allowProtected: confirmed-malicious DANGER files may sit in
                // ~/Downloads etc. which the cleanup whitelist guards — but a
                // virus there is a threat to neutralise, reversibly.
                let result = await quarantine.quarantine([URL(fileURLWithPath: d.path)], allowProtected: true)
                action = result.succeeded.isEmpty ? .failed : .quarantined
            }

            let event = RealtimeEvent(
                id: UUID(), date: now, kind: d.kind, severity: d.severity,
                path: d.path, title: d.title, detail: d.detail, action: action)
            recentEvents.insert(event, at: 0)
            if recentEvents.count > Self.maxEvents { recentEvents.removeLast() }
            surfaced.append(event)
            Log.scanner.warning("Realtime: \(d.title, privacy: .public) — \(action.rawValue, privacy: .public)")
        }
        // Buffer + debounce so a bulk drop (even across several FSEvents
        // batches) raises a single banner, not one per file.
        if !surfaced.isEmpty { scheduleNotify(surfaced) }
    }

    private func scheduleNotify(_ events: [RealtimeEvent]) {
        pendingNotify.append(contentsOf: events)
        notifyTask?.cancel()
        let delay = notifyDebounce
        notifyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.flushNotify()
        }
    }

    private func flushNotify() {
        let batch = pendingNotify
        pendingNotify.removeAll()
        guard !batch.isEmpty else { return }
        notify(batch)
    }

    private func notify(_ events: [RealtimeEvent]) {
        let content = UNMutableNotificationContent()
        let quarantined = events.filter { $0.action == .quarantined }.count

        if events.count == 1 {
            let e = events[0]
            let name = (e.path as NSString).lastPathComponent
            if e.action == .quarantined {
                content.title = "🛡️ MacCleaner — Threat quarantined"
                content.body = "“\(name)” was malicious and moved to Quarantine (restorable for 7 days)."
            } else {
                content.title = "🛡️ MacCleaner — Threat detected"
                content.body = "\(e.title). Review it on the Malware Removal page."
            }
        } else {
            content.title = "🛡️ MacCleaner — \(events.count) threats handled"
            var parts: [String] = []
            if quarantined > 0 { parts.append("\(quarantined) quarantined") }
            let alerted = events.count - quarantined
            if alerted > 0 { parts.append("\(alerted) flagged") }
            content.body = "\(parts.joined(separator: ", ")). Open the Malware Removal page to review them."
        }
        content.sound = .default
        content.categoryIdentifier = "MacCleaner.realtime"
        let req = UNNotificationRequest(identifier: "rt-" + UUID().uuidString, content: content, trigger: nil)
        // No completion handler — UN dispatches it off-main and that trips
        // Swift 6's executor assertion (see AlertEngine for the same note).
        UNUserNotificationCenter.current().add(req)
    }
}

/// One realtime detection, surfaced in the Protection UI and a notification.
struct RealtimeEvent: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable {
        case persistence, maliciousFile, ransomwareCanary, ransomwareBurst

        var icon: String {
            switch self {
            case .persistence:     return "bolt.badge.clock"
            case .maliciousFile:   return "ladybug.fill"
            case .ransomwareCanary, .ransomwareBurst: return "lock.trianglebadge.exclamationmark"
            }
        }
    }

    enum Action: String, Sendable {
        case quarantined = "Quarantined"
        case alerted = "Alerted"
        case failed = "Quarantine failed"
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let severity: ThreatItem.Severity
    let path: String
    let title: String
    let detail: String
    var action: Action
}
