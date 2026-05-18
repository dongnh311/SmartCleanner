import Foundation

enum ScanError: Error, LocalizedError, Sendable {
    case ruleLoadFailed(String)
    case accessDenied(URL)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .ruleLoadFailed(let msg):  return "Could not load rules: \(msg)"
        case .accessDenied(let url):    return "No permission to access \(url.path)"
        case .other(let msg):           return msg
        }
    }
}

struct CleanFailure: Sendable {
    let item: CleanableItem
    let reason: String
}

struct CleanResult: Sendable {
    let removed: [CleanableItem]
    let failed: [CleanFailure]
    /// Bytes that left the disk via direct unlink (cache/log delete, trash empty).
    /// `volumeAvailableCapacity` should drop by roughly this amount once macOS
    /// reclaims the freed APFS extents.
    let bytesFreed: Int64
    /// Bytes that moved into `~/.MacCleanerQuarantine/` instead of being unlinked.
    /// Same volume → still occupies disk until the 7-day auto-purge runs (or the
    /// user empties Quarantine manually).
    let bytesQuarantined: Int64

    /// Sum that the user usually wants to see as "I cleaned this much" — disk
    /// freed plus quarantined-but-recoverable. Useful for one-line summaries.
    var bytesProcessed: Int64 { bytesFreed + bytesQuarantined }
}

protocol CleanupScanner: Sendable {
    var id: String { get }
    var displayName: String { get }
    func scan() async throws -> [CleanableItem]
    func clean(_ items: [CleanableItem], onProgress: CleanProgressHandler?) async -> CleanResult
}

extension CleanupScanner {
    func clean(_ items: [CleanableItem]) async -> CleanResult {
        await clean(items, onProgress: nil)
    }
}
