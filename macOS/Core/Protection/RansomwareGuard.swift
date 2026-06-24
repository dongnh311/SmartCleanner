import Foundation

/// Behavioural ransomware tripwire — the userspace technique popularised by
/// Patrick Wardle's RansomWhere?.
///
/// Two signals, no kernel hooks required:
///   1. **Canary files** — small hidden decoys planted in the user's
///      document folders. Nothing legitimate ever touches them, so any
///      modify / rename / delete is a high-confidence encryption signal.
///   2. **Write-burst** — a flood of modifications to pre-existing files in
///      a short window, the footprint of bulk encryption. Lower confidence
///      (a backup tool or unzip can look similar), surfaced as REVIEW.
///
/// We can detect and alert; we cannot *block* the writes without the
/// Endpoint Security entitlement (unavailable to an ad-hoc build), and we
/// deliberately never quarantine the user's own documents.
///
/// `@unchecked Sendable`: mutable state is guarded by `lock`; the FSEvents
/// queue and the main actor both call in.
final class RansomwareGuard: @unchecked Sendable {

    private let lock = NSLock()
    private var canaryPaths: Set<String> = []
    private var modificationTimes: [Date] = []

    /// Burst window + count. Tuned to ignore an unzip of a dozen files but
    /// catch sustained mass-rewrite.
    private let burstWindow: TimeInterval = 5
    private let burstThreshold = 30

    private static let marker = "MacCleaner ransomware canary — do not edit or delete. If this file changed unexpectedly your files may be under attack."
    private static let markerData = Data(marker.utf8)
    private static let extensions = ["docx", "pdf", "jpg", "xlsx"]

    // MARK: - Canaries

    /// Plants (or repairs) one decoy per extension in each directory.
    /// Idempotent — safe to call on every launch. A canary whose content
    /// drifted from the marker is rewritten so a stale one doesn't read as
    /// an attack forever.
    func plantCanaries(in directories: [String]) {
        var planted: Set<String> = []
        for dir in directories {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            for ext in Self.extensions {
                let path = "\(dir)/.maccleaner_canary.\(ext)"
                planted.insert(path)
                let url = URL(fileURLWithPath: path)
                let current = try? Data(contentsOf: url)
                if current != Self.markerData {
                    try? Self.markerData.write(to: url)
                }
            }
        }
        lock.lock()
        canaryPaths = planted
        lock.unlock()
        Log.scanner.info("RansomwareGuard planted \(planted.count, privacy: .public) canaries")
    }

    func isCanary(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return canaryPaths.contains(path)
    }

    /// True only when a known canary's content actually changed or the file
    /// is gone — the real attack signal. Content-based, so the file-creation
    /// event from planting and benign metadata/thumbnail touches (which keep
    /// the bytes intact) never raise a false alarm.
    func isCanaryTampered(_ path: String) -> Bool {
        guard isCanary(path) else { return false }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return true   // deleted or unreadable
        }
        return data != Self.markerData
    }

    /// Removes every planted canary — called when realtime protection is
    /// switched off so we don't leave decoys behind.
    func removeCanaries() {
        lock.lock()
        let paths = canaryPaths
        canaryPaths.removeAll()
        lock.unlock()
        for p in paths { try? FileManager.default.removeItem(atPath: p) }
    }

    // MARK: - Write-burst

    /// Records a modification of a pre-existing user file and reports
    /// whether the burst threshold just tripped. Resets the window on a
    /// trip so the caller fires once per burst, not once per file.
    func noteModificationAndCheckBurst(now: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-burstWindow)
        modificationTimes.removeAll { $0 < cutoff }
        modificationTimes.append(now)
        if modificationTimes.count >= burstThreshold {
            modificationTimes.removeAll()
            return true
        }
        return false
    }
}
