import CYara
import Foundation

/// Collects matched rule names during a scan. Passed to the C callback via an
/// unretained opaque pointer.
private final class MatchBox {
    var names: [String] = []
}

/// The YARA scan callback (C convention). On every rule match it appends the
/// rule identifier to the `MatchBox` handed in as `user_data`.
private func yaraScanCallback(
    context: UnsafeMutablePointer<YR_SCAN_CONTEXT>?,
    message: Int32,
    messageData: UnsafeMutableRawPointer?,
    userData: UnsafeMutableRawPointer?
) -> Int32 {
    if message == Int32(CALLBACK_MSG_RULE_MATCHING),
       let messageData, let userData,
       let cstr = cyara_rule_identifier(messageData) {
        let box = Unmanaged<MatchBox>.fromOpaque(userData).takeUnretainedValue()
        box.names.append(String(cString: cstr))
    }
    return Int32(CALLBACK_CONTINUE)
}

/// A compiled set of YARA rules you can scan files/data against. `libyara` is
/// initialised once per process. Thread-safe to *scan* concurrently (libyara
/// allows concurrent scans of one `YR_RULES`); compile on one thread.
public final class YaraEngine: @unchecked Sendable {

    public struct CompileResult: Sendable {
        public let rulesCompiled: Int
        public let errors: Int
    }

    private static let bootstrap: Bool = {
        yr_initialize() == ERROR_SUCCESS
    }()

    private var rules: UnsafeMutablePointer<YR_RULES>?
    public private(set) var ruleCount: Int = 0

    /// Compiles the given rule sources (each may contain many rules). Returns
    /// nil only if libyara can't init or no rules compiled at all.
    public init?(ruleSources: [String]) {
        guard Self.bootstrap else { return nil }

        var compiler: UnsafeMutablePointer<YR_COMPILER>?
        guard yr_compiler_create(&compiler) == ERROR_SUCCESS, let compiler else { return nil }
        defer { yr_compiler_destroy(compiler) }

        for source in ruleSources {
            _ = source.withCString { yr_compiler_add_string(compiler, $0, nil) }
        }

        var compiled: UnsafeMutablePointer<YR_RULES>?
        guard yr_compiler_get_rules(compiler, &compiled) == ERROR_SUCCESS, let compiled else { return nil }
        self.rules = compiled
        self.ruleCount = Int(compiled.pointee.num_rules)
    }

    deinit {
        if let rules { yr_rules_destroy(rules) }
    }

    /// Rule identifiers that match the file at `path` (empty if none / error).
    public func scanFile(_ path: String) -> [String] {
        guard let rules else { return [] }
        let box = MatchBox()
        let userData = Unmanaged.passUnretained(box).toOpaque()
        _ = path.withCString { cpath in
            yr_rules_scan_file(rules, cpath, 0, yaraScanCallback, userData, 0)
        }
        return box.names
    }

    /// Rule identifiers that match the in-memory `data`.
    public func scan(_ data: Data) -> [String] {
        guard let rules else { return [] }
        let box = MatchBox()
        let userData = Unmanaged.passUnretained(box).toOpaque()
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            _ = yr_rules_scan_mem(rules, base, raw.count, 0, yaraScanCallback, userData, 0)
        }
        return box.names
    }
}
