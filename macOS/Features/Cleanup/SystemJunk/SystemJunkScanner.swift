import Foundation

actor SystemJunkScanner: CleanupScanner {

    let id = "system_junk"
    let displayName = "System Junk"

    private let ruleEngine: RuleEngine
    private let quarantine: QuarantineService

    init(ruleEngine: RuleEngine, quarantine: QuarantineService) {
        self.ruleEngine = ruleEngine
        self.quarantine = quarantine
    }

    func scan() async throws -> [CleanableItem] {
        let allRules = await ruleEngine.systemJunkRules
        let runnable = allRules.filter { !$0.requiresAdmin }
        Log.scanner.info("system_junk scan: \(runnable.count) of \(allRules.count) rules runnable without admin")

        return await withTaskGroup(of: [CleanableItem].self) { group in
            for rule in runnable {
                let engine = self.ruleEngine
                group.addTask {
                    await engine.scanRule(rule)
                }
            }
            var collected: [CleanableItem] = []
            for await items in group { collected.append(contentsOf: items) }
            return collected
        }
    }

    func clean(_ items: [CleanableItem], onProgress: CleanProgressHandler? = nil) async -> CleanResult {
        var directDeleteItems: [CleanableItem] = []
        var quarantineItems: [CleanableItem] = []

        for item in items {
            if item.safetyLevel == .safe && Self.allowsDirectDelete(category: item.category) {
                directDeleteItems.append(item)
            } else {
                quarantineItems.append(item)
            }
        }

        var removed: [CleanableItem] = []
        var failed: [CleanFailure] = []
        var bytesFreed: Int64 = 0
        var bytesQuarantined: Int64 = 0

        if !directDeleteItems.isEmpty {
            let urls = directDeleteItems.map { $0.url }
            let result = await quarantine.directDelete(urls, onProgress: onProgress)
            let succeededSet = Set(result.succeeded.map { $0.path })
            let failedMap: [String: String] = Dictionary(uniqueKeysWithValues: result.failed.map { ($0.0.path, $0.1) })
            for item in directDeleteItems {
                if succeededSet.contains(item.url.path) {
                    removed.append(item)
                    bytesFreed += item.size
                } else if let reason = failedMap[item.url.path] {
                    failed.append(CleanFailure(item: item, reason: reason))
                }
            }
        }

        if !quarantineItems.isEmpty {
            let urls = quarantineItems.map { $0.url }
            let result = await quarantine.quarantine(urls, onProgress: onProgress)
            let succeededSet = Set(result.succeeded.keys.map { $0.path })
            let failedMap: [String: String] = Dictionary(uniqueKeysWithValues: result.failed.map { ($0.0.path, $0.1) })
            for item in quarantineItems {
                if succeededSet.contains(item.url.path) {
                    removed.append(item)
                    // Quarantine = move within the same APFS volume; no disk
                    // recovered until the 7-day purge or a manual empty.
                    bytesQuarantined += item.size
                } else if let reason = failedMap[item.url.path] {
                    failed.append(CleanFailure(item: item, reason: reason))
                }
            }
        }

        Log.scanner.info("system_junk clean: removed=\(removed.count) failed=\(failed.count) bytesFreed=\(bytesFreed) bytesQuarantined=\(bytesQuarantined)")
        return CleanResult(removed: removed, failed: failed, bytesFreed: bytesFreed, bytesQuarantined: bytesQuarantined)
    }

    private static func allowsDirectDelete(category: ItemCategory) -> Bool {
        switch category {
        case .userCache, .systemCache, .userLog, .systemLog, .photoCache, .devToolCache:
            return true
        case .xcodeJunk, .downloadedFile, .trash, .mailAttachment, .other:
            return false
        }
    }
}
