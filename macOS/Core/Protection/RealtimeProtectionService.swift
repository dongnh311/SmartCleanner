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

    let signatureCount: Int

    private let quarantine: QuarantineService
    private let hashStore: MalwareHashStore
    private let guardian = RansomwareGuard()
    private var watcher: FileSystemWatcher?

    /// path|kind → last surfaced; suppresses FSEvents duplicates.
    private var recentlyHandled: [String: Date] = [:]
    private let dedupWindow: TimeInterval = 30

    private static let maxEvents = 60

    init(quarantine: QuarantineService) {
        self.quarantine = quarantine
        let store = MalwareHashStore()
        self.hashStore = store
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

        let watcher = FileSystemWatcher { [weak self] events in
            Task.detached(priority: .utility) {
                let detections = Self.analyze(
                    events,
                    hashStore: hashStore,
                    guardian: guardian,
                    persistenceDirs: persistence,
                    fileDropDirs: drops,
                    burstDirs: bursts
                )
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
            await MainActor.run { self?.watchedPathCount = count }
        }
        Log.scanner.info("Realtime protection starting")
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        guardian.removeCanaries()
        isRunning = false
        Log.scanner.info("Realtime protection stopped")
    }

    func clearEvents() { recentEvents.removeAll() }

    /// Diagnostic/smoke-test hook — is this digest on the active blocklist?
    func isOnBlocklist(_ hash: String) -> Bool { hashStore.contains(hash) }

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

    private nonisolated static func analyze(
        _ events: [RealtimeFileEvent],
        hashStore: MalwareHashStore,
        guardian: RansomwareGuard,
        persistenceDirs: Set<String>,
        fileDropDirs: Set<String>,
        burstDirs: Set<String>
    ) -> [Detection] {
        var out: [Detection] = []
        for event in events {
            let path = event.path
            let parent = (path as NSString).deletingLastPathComponent

            // 1) Ransomware canary — content-verified so the planting event
            // and benign metadata/thumbnail touches (bytes unchanged) never
            // alarm; only a real content change or deletion does.
            if guardian.isCanary(path) {
                if guardian.isCanaryTampered(path) {
                    out.append(Detection(
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
                    out.append(Detection(
                        kind: .persistence, severity: threat.severity, path: path,
                        title: "New persistence item: \(threat.title)",
                        detail: threat.signals.joined(separator: " · "),
                        quarantine: threat.severity == .danger))
                }
                continue
            }

            // 3) File dropped into a watched folder → hash blocklist.
            if event.isFile, (event.isCreated || event.isRenamed),
               isUnder(parent, roots: fileDropDirs) {
                if let hash = MalwareHashStore.sha256Hex(ofFileAt: URL(fileURLWithPath: path)),
                   hashStore.contains(hash) {
                    out.append(Detection(
                        kind: .maliciousFile, severity: .danger, path: path,
                        title: "Known-malicious file: \((path as NSString).lastPathComponent)",
                        detail: "SHA-256 matches the local blocklist.",
                        quarantine: true))
                }
                continue
            }

            // 4) Write-burst behavioural signal on existing documents.
            if event.isFile, event.isModified, !event.isCreated,
               isUnder(parent, roots: burstDirs),
               guardian.noteModificationAndCheckBurst() {
                out.append(Detection(
                    kind: .ransomwareBurst, severity: .warn, path: parent,
                    title: "Unusual burst of file changes",
                    detail: "Many documents in \((parent as NSString).lastPathComponent) changed at once — consistent with bulk encryption. Review what is writing to this folder.",
                    quarantine: false))
            }
        }
        return out
    }

    private nonisolated static func isUnder(_ path: String, roots: Set<String>) -> Bool {
        roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    // MARK: - Response (main actor)

    private func apply(_ detections: [Detection]) async {
        let now = Date()
        for d in detections {
            let key = "\(d.kind.rawValue)|\(d.path)"
            if let last = recentlyHandled[key], now.timeIntervalSince(last) < dedupWindow { continue }
            recentlyHandled[key] = now

            var action: RealtimeEvent.Action = .alerted
            if d.quarantine {
                let result = await quarantine.quarantine([URL(fileURLWithPath: d.path)])
                action = result.succeeded.isEmpty ? .failed : .quarantined
            }

            let event = RealtimeEvent(
                id: UUID(), date: now, kind: d.kind, severity: d.severity,
                path: d.path, title: d.title, detail: d.detail, action: action)
            recentEvents.insert(event, at: 0)
            if recentEvents.count > Self.maxEvents { recentEvents.removeLast() }

            notify(event)
            Log.scanner.warning("Realtime: \(d.title, privacy: .public) — \(action.rawValue, privacy: .public)")
        }
    }

    private func notify(_ event: RealtimeEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.action == .quarantined
            ? "Moved to quarantine. \(event.detail)"
            : event.detail
        content.sound = .default
        content.categoryIdentifier = "MacCleaner.realtime"
        let req = UNNotificationRequest(identifier: "rt-" + event.id.uuidString, content: content, trigger: nil)
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
