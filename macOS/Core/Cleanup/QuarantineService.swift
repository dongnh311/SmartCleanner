import Foundation

actor QuarantineService {

    static let retentionDays: Int = 7

    let root: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.root = home.appendingPathComponent(".MacCleanerQuarantine", isDirectory: true)
    }

    struct MoveResult: Sendable {
        let succeeded: [URL: URL]
        let failed: [(URL, String)]
    }

    struct DeleteResult: Sendable {
        let succeeded: [URL]
        let failed: [(URL, String)]
    }

    /// On-disk manifest persisted alongside quarantined items so the manager UI
    /// can show their original paths and offer Restore. Each session folder
    /// contains its own `manifest.json`.
    struct Manifest: Codable, Sendable {
        var sessionID: String
        var createdAt: Date
        var origin: String?
        var entries: [Entry]

        struct Entry: Codable, Sendable, Hashable {
            let from: String     // original absolute path
            let to: String       // filename inside the session folder
            let size: Int64
        }
    }

    struct SessionInfo: Sendable, Identifiable, Hashable {
        let id: String                     // session timestamp (folder name)
        let url: URL
        let createdAt: Date
        let origin: String?
        let entries: [Manifest.Entry]
        let totalBytes: Int64
        let daysRemaining: Int
    }

    /// Moves URLs into a timestamped quarantine session. Used for non-cache items.
    /// `allowProtected` bypasses the cleanup whitelist (which guards
    /// ~/Downloads, ~/Desktop, ~/Documents, etc. from the *cleaner*). The
    /// realtime engine sets it for confirmed-malicious DANGER files: a known
    /// virus sitting in Downloads is a threat to neutralise, not personal
    /// data to protect — and the move is reversible from quarantine anyway.
    func quarantine(_ urls: [URL], onProgress: CleanProgressHandler? = nil, allowProtected: Bool = false) async -> MoveResult {
        await MainActor.run { WhitelistGuard.refreshLiveProcesses(force: true) }
        let sessionID = timestampString()
        let session = root.appendingPathComponent(sessionID, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        } catch {
            Log.scanner.error("quarantine create-dir failed: \(error.localizedDescription, privacy: .public)")
            return MoveResult(succeeded: [:], failed: urls.map { ($0, error.localizedDescription) })
        }

        var succeeded: [URL: URL] = [:]
        var failed: [(URL, String)] = []
        var entries: [Manifest.Entry] = []

        for url in urls {
            if !allowProtected, WhitelistGuard.isProtected(url) {
                failed.append((url, "Refused: protected path"))
                Log.scanner.fault("quarantine refused on protected \(url.path, privacy: .public)")
                onProgress?(url)
                continue
            }
            let dest = Self.uniqueDestination(in: session, for: url)
            do {
                let size = Self.fileSize(at: url)
                try FileManager.default.moveItem(at: url, to: dest)
                succeeded[url] = dest
                entries.append(Manifest.Entry(from: url.path, to: dest.lastPathComponent, size: size))
                Log.scanner.info("quarantined \(url.path, privacy: .public) -> \(dest.path, privacy: .public)")
            } catch {
                failed.append((url, error.localizedDescription))
                Log.scanner.error("quarantine failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            onProgress?(url)
        }
        writeManifest(in: session, sessionID: sessionID, origin: nil, entries: entries)
        return MoveResult(succeeded: succeeded, failed: failed)
    }

    /// Uninstaller path: moves an app bundle plus its leftovers into quarantine.
    /// `/Applications` and `~/Applications` are blanket-protected by WhitelistGuard
    /// (so cleaners never wander into them), but the user explicitly choosing to
    /// uninstall an app is exactly when we *should* be allowed in. We re-check the
    /// app URL is a direct .app child of one of those folders before bypassing.
    /// Leftovers still go through the normal guard.
    func quarantineApp(_ appURL: URL, leftovers: [URL], onProgress: CleanProgressHandler? = nil) async -> MoveResult {
        await MainActor.run { WhitelistGuard.refreshLiveProcesses(force: true) }
        guard Self.isAppBundleDirectChild(appURL) else {
            Log.scanner.fault("quarantineApp refused — not an app bundle: \(appURL.path, privacy: .public)")
            return MoveResult(succeeded: [:], failed: [(appURL, "Not an app bundle in /Applications")])
        }

        let sessionID = timestampString()
        let session = root.appendingPathComponent(sessionID, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        } catch {
            Log.scanner.error("quarantineApp create-dir failed: \(error.localizedDescription, privacy: .public)")
            return MoveResult(succeeded: [:], failed: [(appURL, error.localizedDescription)])
        }

        var succeeded: [URL: URL] = [:]
        var failed: [(URL, String)] = []
        var entries: [Manifest.Entry] = []

        let appDest = Self.uniqueDestination(in: session, for: appURL)
        do {
            let appSize = Self.fileSize(at: appURL)
            try FileManager.default.moveItem(at: appURL, to: appDest)
            succeeded[appURL] = appDest
            entries.append(Manifest.Entry(from: appURL.path, to: appDest.lastPathComponent, size: appSize))
            Log.scanner.info("quarantined app \(appURL.path, privacy: .public) -> \(appDest.path, privacy: .public)")
        } catch {
            failed.append((appURL, error.localizedDescription))
            Log.scanner.error("quarantineApp failed for \(appURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            writeManifest(in: session, sessionID: sessionID, origin: appURL.path, entries: entries)
            onProgress?(appURL)
            return MoveResult(succeeded: succeeded, failed: failed)
        }
        onProgress?(appURL)

        for url in leftovers {
            if WhitelistGuard.isProtected(url) {
                failed.append((url, "Refused: protected path"))
                onProgress?(url)
                continue
            }
            let dest = Self.uniqueDestination(in: session, for: url)
            do {
                let size = Self.fileSize(at: url)
                try FileManager.default.moveItem(at: url, to: dest)
                succeeded[url] = dest
                entries.append(Manifest.Entry(from: url.path, to: dest.lastPathComponent, size: size))
                Log.scanner.info("quarantined leftover \(url.path, privacy: .public) -> \(dest.path, privacy: .public)")
            } catch {
                failed.append((url, error.localizedDescription))
            }
            onProgress?(url)
        }
        writeManifest(in: session, sessionID: sessionID, origin: appURL.path, entries: entries)
        return MoveResult(succeeded: succeeded, failed: failed)
    }

    private static func isAppBundleDirectChild(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let parents = ["/Applications", NSHomeDirectory() + "/Applications"]
        for parent in parents {
            let prefix = parent + "/"
            guard path.hasPrefix(prefix) else { continue }
            let rest = String(path.dropFirst(prefix.count))
            if !rest.contains("/") && rest.hasSuffix(".app") {
                return true
            }
        }
        return false
    }

    /// Permanently removes URLs. Used only for safe cache items where the OS regenerates content.
    func directDelete(_ urls: [URL], onProgress: CleanProgressHandler? = nil) async -> DeleteResult {
        await MainActor.run { WhitelistGuard.refreshLiveProcesses(force: true) }
        var succeeded: [URL] = []
        var failed: [(URL, String)] = []

        for url in urls {
            if WhitelistGuard.isProtected(url) {
                failed.append((url, "Refused: protected path"))
                Log.scanner.fault("directDelete refused on protected \(url.path, privacy: .public)")
                onProgress?(url)
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                succeeded.append(url)
                Log.scanner.info("deleted \(url.path, privacy: .public)")
            } catch {
                failed.append((url, error.localizedDescription))
                Log.scanner.error("delete failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            onProgress?(url)
        }
        return DeleteResult(succeeded: succeeded, failed: failed)
    }

    /// Removes quarantine sessions older than retentionDays.
    func purgeOld() async {
        guard let sessions = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        for session in sessions {
            let v = try? session.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = v?.contentModificationDate, modified < cutoff else { continue }
            do {
                try FileManager.default.removeItem(at: session)
                Log.scanner.info("purged quarantine session \(session.lastPathComponent, privacy: .public)")
            } catch {
                Log.scanner.error("failed to purge \(session.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Manager API

    /// Lists all quarantine sessions currently on disk, newest first.
    func listSessions() async -> [SessionInfo] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sessions: [SessionInfo] = []
        for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let info = sessionInfo(for: folder)
            sessions.append(info)
        }
        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    /// Moves a single quarantined entry back to its original path. Fails if the
    /// destination already exists or the parent directory is missing.
    func restore(sessionID: String, entry: Manifest.Entry) async -> Result<URL, Error> {
        let session = root.appendingPathComponent(sessionID, isDirectory: true)
        let src = session.appendingPathComponent(entry.to)
        let dst = URL(fileURLWithPath: entry.from)

        guard FileManager.default.fileExists(atPath: src.path) else {
            return .failure(NSError(domain: "Quarantine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Source missing in quarantine"]))
        }
        if FileManager.default.fileExists(atPath: dst.path) {
            return .failure(NSError(domain: "Quarantine", code: 409, userInfo: [NSLocalizedDescriptionKey: "Destination already exists: \(dst.path)"]))
        }
        let parent = dst.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
            catch { return .failure(error) }
        }
        do {
            try FileManager.default.moveItem(at: src, to: dst)
            removeEntryFromManifest(in: session, entry: entry)
            Log.scanner.info("restored \(dst.path, privacy: .public)")
            return .success(dst)
        } catch {
            Log.scanner.error("restore failed for \(dst.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    /// Permanently deletes a single session folder.
    func deleteSession(_ sessionID: String) async -> Bool {
        let session = root.appendingPathComponent(sessionID, isDirectory: true)
        do {
            try FileManager.default.removeItem(at: session)
            Log.scanner.info("deleted session \(sessionID, privacy: .public)")
            return true
        } catch {
            Log.scanner.error("delete session failed \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Permanently deletes everything under quarantine root.
    func deleteAllSessions(onProgress: CleanProgressHandler? = nil) async -> Int {
        let sessions = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var deleted = 0
        for s in sessions {
            if (try? FileManager.default.removeItem(at: s)) != nil { deleted += 1 }
            onProgress?(s)
        }
        return deleted
    }

    // MARK: - Manifest

    private func writeManifest(in session: URL, sessionID: String, origin: String?, entries: [Manifest.Entry]) {
        let manifest = Manifest(sessionID: sessionID, createdAt: Date(), origin: origin, entries: entries)
        let url = session.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: url)
        }
    }

    private func readManifest(in session: URL) -> Manifest? {
        let url = session.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Manifest.self, from: data)
    }

    private func removeEntryFromManifest(in session: URL, entry: Manifest.Entry) {
        guard var manifest = readManifest(in: session) else { return }
        manifest.entries.removeAll { $0 == entry }
        writeManifest(in: session, sessionID: manifest.sessionID, origin: manifest.origin, entries: manifest.entries)
    }

    /// Builds a SessionInfo by reading the manifest if present, falling back to
    /// directory enumeration for legacy sessions written before manifests existed.
    private func sessionInfo(for folder: URL) -> SessionInfo {
        let id = folder.lastPathComponent
        let createdAt = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        if let manifest = readManifest(in: folder) {
            let total = manifest.entries.reduce(Int64(0)) { $0 + $1.size }
            return SessionInfo(
                id: id,
                url: folder,
                createdAt: manifest.createdAt,
                origin: manifest.origin,
                entries: manifest.entries,
                totalBytes: total,
                daysRemaining: Self.daysRemaining(from: manifest.createdAt)
            )
        }

        // Legacy session — enumerate to synthesise entries. Origin is unknown for
        // arbitrary files but for `.app` bundles we infer `/Applications/<name>`
        // since that's by far the most common origin. Restore re-checks that the
        // destination doesn't already exist, so a bad guess just fails safely.
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let entries: [Manifest.Entry] = contents.compactMap { url in
            let name = url.lastPathComponent
            guard name != "manifest.json" else { return nil }
            let from: String
            if name.hasSuffix(".app") {
                from = "/Applications/\(name)"
            } else {
                from = ""
            }
            return Manifest.Entry(from: from, to: name, size: Self.fileSize(at: url))
        }
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        return SessionInfo(
            id: id,
            url: folder,
            createdAt: createdAt,
            origin: nil,
            entries: entries,
            totalBytes: total,
            daysRemaining: Self.daysRemaining(from: createdAt)
        )
    }

    private static func daysRemaining(from createdAt: Date) -> Int {
        let elapsed = Date().timeIntervalSince(createdAt) / 86_400
        return max(0, retentionDays - Int(elapsed))
    }

    /// Recursively totals the size on disk under a URL. Used so the manifest
    /// records sizes before the move makes the original path unreachable.
    private static func fileSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var size: Int64 = 0
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) {
            for case let item as URL in enumerator {
                let v = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true {
                    size += Int64(v?.totalFileAllocatedSize ?? 0)
                }
            }
        } else {
            let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            size = Int64(v?.totalFileAllocatedSize ?? 0)
        }
        return size
    }

    private func timestampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    private static func uniqueDestination(in session: URL, for url: URL) -> URL {
        var dest = session.appendingPathComponent(url.lastPathComponent)
        var counter = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            let name = ext.isEmpty ? "\(base)_\(counter)" : "\(base)_\(counter).\(ext)"
            dest = session.appendingPathComponent(name)
            counter += 1
        }
        return dest
    }
}
