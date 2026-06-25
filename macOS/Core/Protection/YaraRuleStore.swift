import Foundation
import Yara

/// Loads bundled + user YARA rule files and keeps a compiled engine per file
/// (so one broken user rule set can't disable the rest). YARA matches are a
/// REVIEW signal — the bundled rules are deliberately broad — surfaced in
/// scans, never auto-quarantined.
///
/// `@unchecked Sendable`: `engines` is swapped under `lock`; libyara allows
/// concurrent scans of a compiled rule set.
final class YaraRuleStore: @unchecked Sendable {

    static let shared = YaraRuleStore()

    private let lock = NSLock()
    private var engines: [YaraEngine] = []
    private(set) var ruleCount = 0

    /// YARA mmaps + scans the whole file, so skip very large ones.
    static let maxScanBytes: Int64 = 32 * 1024 * 1024

    private init() { reload() }

    func reload() {
        var built: [YaraEngine] = []
        var count = 0
        for source in Self.loadRuleSources() {
            if let engine = YaraEngine(ruleSources: [source]), engine.ruleCount > 0 {
                built.append(engine)
                count += engine.ruleCount
            }
        }
        lock.lock()
        engines = built
        ruleCount = count
        lock.unlock()
        Log.scanner.info("YARA loaded \(count, privacy: .public) rules from \(built.count, privacy: .public) files")
    }

    var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return !engines.isEmpty
    }

    /// Names of rules matching the file (deduped across rule files), or [].
    func scanFile(_ path: String) -> [String] {
        // Rule files trivially match their own pattern strings — don't scan them.
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "yar" || ext == "yara" { return [] }
        lock.lock(); let es = engines; lock.unlock()
        guard !es.isEmpty else { return [] }
        if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64,
           size > Self.maxScanBytes || size == 0 { return [] }
        var names: Set<String> = []
        for engine in es { names.formUnion(engine.scanFile(path)) }
        return names.sorted()
    }

    // MARK: - Loading

    /// Where users can drop extra `.yar` / `.yara` files.
    static func userRulesDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("MacCleaner/YaraRules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func loadRuleSources() -> [String] {
        var out: [String] = []
        for url in bundledRuleURLs() + userRuleURLs() {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                out.append(text)
            }
        }
        return out
    }

    private static func bundledRuleURLs() -> [URL] {
        var urls: [URL] = []
        for sub in ["YaraRules", "Resources/YaraRules"] {
            if let found = Bundle.main.urls(forResourcesWithExtension: "yar", subdirectory: sub) {
                urls.append(contentsOf: found)
            }
        }
        if urls.isEmpty, let found = Bundle.main.urls(forResourcesWithExtension: "yar", subdirectory: nil) {
            urls.append(contentsOf: found)
        }
        return urls
    }

    private static func userRuleURLs() -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: userRulesDir(), includingPropertiesForKeys: nil) else { return [] }
        return files.filter { ["yar", "yara"].contains($0.pathExtension.lowercased()) }
    }
}
