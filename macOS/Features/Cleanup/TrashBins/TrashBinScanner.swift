import Foundation

actor TrashBinScanner: CleanupScanner {

    let id = "trash_bins"
    let displayName = "Trash Bins"

    private let quarantine: QuarantineService

    init(quarantine: QuarantineService) {
        self.quarantine = quarantine
    }

    func scan() async throws -> [CleanableItem] {
        var items: [CleanableItem] = []

        let userTrash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        items.append(contentsOf: await scanTrash(at: userTrash, label: "User Trash"))

        if let volumes = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: nil
        ) {
            for volume in volumes {
                let trashes = volume.appendingPathComponent(".Trashes")
                if FileManager.default.fileExists(atPath: trashes.path) {
                    if let userBins = try? FileManager.default.contentsOfDirectory(
                        at: trashes,
                        includingPropertiesForKeys: nil
                    ) {
                        for bin in userBins {
                            items.append(contentsOf: await scanTrash(at: bin, label: "Trash on \(volume.lastPathComponent)"))
                        }
                    }
                }
            }
        }

        Log.scanner.info("trash scan found \(items.count) items totalling \(items.reduce(Int64(0)) { $0 + $1.size }) bytes")
        return items
    }

    private func scanTrash(at directory: URL, label: String) async -> [CleanableItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .totalFileAllocatedSizeKey,
                .fileSizeKey
            ],
            options: []
        ) else { return [] }

        return await withTaskGroup(of: CleanableItem?.self) { group in
            for url in entries {
                group.addTask {
                    let v = try? url.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .contentModificationDateKey,
                        .totalFileAllocatedSizeKey,
                        .fileSizeKey
                    ])
                    let isDir = v?.isDirectory ?? false
                    let lastMod = v?.contentModificationDate

                    let size: Int64
                    if isDir {
                        size = await Task.detached(priority: .userInitiated) {
                            FileSizeCalculator.walk(directory: url).total
                        }.value
                    } else {
                        size = Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
                    }
                    guard size > 0 else { return nil }

                    return CleanableItem(
                        id: UUID(),
                        url: url,
                        size: size,
                        category: .trash,
                        safetyLevel: .review,
                        lastModified: lastMod,
                        isDirectory: isDir,
                        title: url.lastPathComponent,
                        description: label,
                        ruleID: nil
                    )
                }
            }
            var all: [CleanableItem] = []
            for await item in group { if let item { all.append(item) } }
            return all
        }
    }

    func clean(_ items: [CleanableItem], onProgress: CleanProgressHandler? = nil) async -> CleanResult {
        var removed: [CleanableItem] = []
        var failed: [CleanFailure] = []
        var bytesFreed: Int64 = 0

        for item in items {
            // WhitelistGuard still applies — sanity check before deleting.
            // Trash items are user-owned but we still don't want to delete
            // a still-running app's executable that's been moved there.
            if WhitelistGuard.isProtected(item.url) {
                failed.append(CleanFailure(item: item, reason: "Refused: protected path"))
                onProgress?(item.url)
                continue
            }

            if await Self.deleteTrashItem(item.url) {
                removed.append(item)
                bytesFreed += item.size
                Log.scanner.info("trash deleted \(item.url.path, privacy: .public)")
            } else {
                failed.append(CleanFailure(
                    item: item,
                    reason: "Couldn't remove — likely needs admin permission"
                ))
                Log.scanner.error("trash delete failed for \(item.url.path, privacy: .public)")
            }
            onProgress?(item.url)
        }

        Log.scanner.info("trash clean: removed=\(removed.count) failed=\(failed.count) bytesFreed=\(bytesFreed)")
        return CleanResult(removed: removed, failed: failed, bytesFreed: bytesFreed, bytesQuarantined: 0)
    }

    /// FileManager.removeItem chokes on items the system sandboxes (apps
    /// moved from /Applications to Trash carry SIP-like quarantine bits
    /// that block Foundation's path). Fall back to /bin/rm -rf which runs
    /// in the user's shell context and clears most stuck items.
    private static func deleteTrashItem(_ url: URL) async -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            Log.scanner.warning("FileManager removeItem failed for \(url.path, privacy: .public) — falling back to /bin/rm: \(error.localizedDescription, privacy: .public)")
        }
        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/rm")
            proc.arguments = ["-rf", url.path]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
}
