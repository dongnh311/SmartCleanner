import Foundation

actor MailAttachmentsScanner: CleanupScanner {

    let id = "mail_attachments"
    let displayName = "Mail Attachments"

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
        // Mail re-downloads attachments on demand — direct delete is safe.
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
        Log.scanner.info("mail_attachments clean: removed=\(removed.count) bytes=\(bytes)")
        return CleanResult(removed: removed, failed: failed, bytesFreed: bytes, bytesQuarantined: 0)
    }

    private nonisolated static func collect() -> [CleanableItem] {
        let home = NSHomeDirectory()
        let roots = [
            "\(home)/Library/Mail",
            "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail"
        ]

        var items: [CleanableItem] = []
        for root in roots {
            guard let versionDirs = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for version in versionDirs where version.hasPrefix("V") {
                let attachmentsBase = "\(root)/\(version)"
                items.append(contentsOf: scanAttachments(at: attachmentsBase))
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    private nonisolated static func scanAttachments(at base: String) -> [CleanableItem] {
        guard let enumerator = FileManager.default.enumerator(atPath: base) else { return [] }
        var seenAttachmentDirs = Set<String>()
        while let rel = enumerator.nextObject() as? String {
            // Look for any subdirectory literally named "Attachments"
            if rel.hasSuffix("/Attachments") || rel == "Attachments" {
                let full = "\(base)/\(rel)"
                seenAttachmentDirs.insert(full)
                enumerator.skipDescendants()
            }
        }

        var items: [CleanableItem] = []
        for dir in seenAttachmentDirs {
            let url = URL(fileURLWithPath: dir)
            guard !WhitelistGuard.isProtected(url) else { continue }
            let size = FileSizeCalculator.walk(directory: url).total
            guard size > 0 else { continue }
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            // Account label from path like .../V10/<accountID>/Attachments
            let parent = url.deletingLastPathComponent().lastPathComponent

            items.append(CleanableItem(
                id: UUID(),
                url: url,
                size: size,
                category: .mailAttachment,
                safetyLevel: .safe,
                lastModified: v?.contentModificationDate,
                isDirectory: true,
                title: "Attachments — \(parent)",
                description: dir,
                ruleID: nil
            ))
        }
        return items
    }
}
