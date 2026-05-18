import Foundation
import AppKit

actor PrivacyCleaner: CleanupScanner {

    let id = "privacy"
    let displayName = "Privacy"

    private let quarantine: QuarantineService

    init(quarantine: QuarantineService) {
        self.quarantine = quarantine
    }

    func scan() async throws -> [CleanableItem] {
        await Task.detached(priority: .userInitiated) {
            Self.collect()
        }.value
    }

    func clean(_ items: [CleanableItem], onProgress: CleanProgressHandler? = nil) async -> CleanResult {
        let runningBundles = await Self.runningBrowserBundleIDs()
        var blockedItems: [CleanableItem] = []
        var safeItems: [CleanableItem] = []
        for item in items {
            if let bundle = Self.bundleID(forBrowserDescribed: item.description),
               runningBundles.contains(bundle) {
                blockedItems.append(item)
            } else {
                safeItems.append(item)
            }
        }

        var removed: [CleanableItem] = []
        var failed: [CleanFailure] = []
        var bytesQuarantined: Int64 = 0

        for blocked in blockedItems {
            failed.append(CleanFailure(item: blocked, reason: "Quit the browser before cleaning."))
            onProgress?(blocked.url)
        }

        if !safeItems.isEmpty {
            let urls = safeItems.map { $0.url }
            let result = await quarantine.quarantine(urls, onProgress: onProgress)
            let succeededSet = Set(result.succeeded.keys.map { $0.path })
            let failedMap: [String: String] = Dictionary(uniqueKeysWithValues: result.failed.map { ($0.0.path, $0.1) })
            for item in safeItems {
                if succeededSet.contains(item.url.path) {
                    removed.append(item)
                    // Browser data is moved into quarantine so the user can
                    // restore if they over-cleaned; disk only frees on purge.
                    bytesQuarantined += item.size
                } else if let reason = failedMap[item.url.path] {
                    failed.append(CleanFailure(item: item, reason: reason))
                }
            }
        }

        Log.scanner.info("privacy clean: removed=\(removed.count) blocked=\(blockedItems.count) failed=\(failed.count) bytesQuarantined=\(bytesQuarantined)")
        return CleanResult(removed: removed, failed: failed, bytesFreed: 0, bytesQuarantined: bytesQuarantined)
    }

    // MARK: - Helpers

    private nonisolated static func collect() -> [CleanableItem] {
        var items: [CleanableItem] = []

        for loc in BrowserCatalog.locations() {
            guard FileManager.default.fileExists(atPath: loc.path) else { continue }
            let url = URL(fileURLWithPath: loc.path)
            guard !WhitelistGuard.isProtected(url) else { continue }

            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: loc.path, isDirectory: &isDir)
            let size: Int64
            if isDir.boolValue {
                size = FileSizeCalculator.walk(directory: url).total
            } else {
                let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
                size = Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
            }
            guard size > 0 else { continue }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

            items.append(CleanableItem(
                id: UUID(),
                url: url,
                size: size,
                category: loc.category,
                safetyLevel: .review,
                lastModified: mod,
                isDirectory: isDir.boolValue,
                title: "\(loc.browser) — \(loc.label)",
                description: loc.browser,
                ruleID: loc.bundleID
            ))
        }

        // Recent items (.sfl2)
        let recents = "\(NSHomeDirectory())/Library/Application Support/com.apple.sharedfilelist"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: recents) {
            for filename in entries where filename.hasSuffix(".sfl2") || filename.hasSuffix(".sfl3") {
                let url = URL(fileURLWithPath: "\(recents)/\(filename)")
                let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey])
                let size = Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
                guard size > 0 else { continue }
                items.append(CleanableItem(
                    id: UUID(),
                    url: url,
                    size: size,
                    category: .other,
                    safetyLevel: .review,
                    lastModified: v?.contentModificationDate,
                    isDirectory: false,
                    title: "Recent items — \(filename)",
                    description: "macOS recent files",
                    ruleID: nil
                ))
            }
        }

        return items.sorted { $0.size > $1.size }
    }

    private nonisolated static func bundleID(forBrowserDescribed description: String) -> String? {
        BrowserCatalog.locations().first { $0.browser == description }?.bundleID
    }

    @MainActor
    private static func runningBrowserBundleIDs() -> Set<String> {
        let bundles = Set(BrowserCatalog.locations().map { $0.bundleID })
        var running = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, bundles.contains(id) {
                running.insert(id)
            }
        }
        return running
    }
}
