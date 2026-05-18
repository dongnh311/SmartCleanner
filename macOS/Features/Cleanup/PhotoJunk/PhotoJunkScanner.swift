import Foundation

actor PhotoJunkScanner: CleanupScanner {

    let id = "photo_junk"
    let displayName = "Photo Junk"

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
        let urls = items.map { $0.url }
        let result = await quarantine.directDelete(urls, onProgress: onProgress)
        let succeededSet = Set(result.succeeded.map { $0.path })
        let failedMap = Dictionary(uniqueKeysWithValues: result.failed.map { ($0.0.path, $0.1) })

        var removed: [CleanableItem] = []
        var failed: [CleanFailure] = []
        var bytes: Int64 = 0
        for item in items {
            if succeededSet.contains(item.url.path) {
                removed.append(item)
                bytes += item.size
            } else if let reason = failedMap[item.url.path] {
                failed.append(CleanFailure(item: item, reason: reason))
            }
        }
        Log.scanner.info("photo_junk clean: removed=\(removed.count) bytes=\(bytes)")
        return CleanResult(removed: removed, failed: failed, bytesFreed: bytes, bytesQuarantined: 0)
    }

    private nonisolated static func collect() -> [CleanableItem] {
        let home = NSHomeDirectory()
        let pictures = "\(home)/Pictures"

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: pictures) else { return [] }

        var items: [CleanableItem] = []
        for entry in entries where entry.hasSuffix(".photoslibrary") {
            let library = "\(pictures)/\(entry)"
            items.append(contentsOf: probe(library: library, libraryName: entry))
        }
        return items.sorted { $0.size > $1.size }
    }

    private nonisolated static let cacheSubpaths: [(String, String)] = [
        ("resources/cache", "Cache database"),
        ("resources/derivatives/masters", "Derivative thumbnails"),
        ("private/com.apple.Photos/Mutations", "Pending edits"),
        ("resources/streaming", "Streaming previews"),
        ("internal", "Internal scratch"),
        ("Caches", "Caches")
    ]

    private nonisolated static func probe(library: String, libraryName: String) -> [CleanableItem] {
        var out: [CleanableItem] = []
        for (sub, label) in cacheSubpaths {
            let path = "\(library)/\(sub)"
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            guard !WhitelistGuard.isProtected(url) else { continue }
            let size = FileSizeCalculator.walk(directory: url).total
            guard size > 0 else { continue }
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            out.append(CleanableItem(
                id: UUID(),
                url: url,
                size: size,
                category: .photoCache,
                safetyLevel: .review,
                lastModified: v?.contentModificationDate,
                isDirectory: true,
                title: "\(label) — \(libraryName)",
                description: path,
                ruleID: nil
            ))
        }
        return out
    }
}
