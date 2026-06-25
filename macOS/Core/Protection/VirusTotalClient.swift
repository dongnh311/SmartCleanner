import Foundation

/// OPT-IN VirusTotal file-reputation lookup. Given a SHA-256 it asks
/// VirusTotal how many of its ~70 engines flagged that file. Only the
/// **hash** ever leaves the machine — never the file itself — and only
/// after the user pastes an API key and flips the switch in Settings.
///
/// Free-tier keys allow ~4 requests/min, 500/day, so lookups are
/// serialised with a minimum interval and results are cached for the
/// process lifetime.
actor VirusTotalClient {

    struct Verdict: Sendable, Hashable {
        let sha256: String
        let malicious: Int
        let suspicious: Int
        let total: Int
        var permalink: String { "https://www.virustotal.com/gui/file/\(sha256)" }
    }

    enum LookupError: Error, Sendable {
        case disabled, noKey, notFound, rateLimited, http(Int), network
    }

    // MARK: - Settings (UserDefaults-backed, no network on read)

    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKeys.virusTotalEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKeys.virusTotalEnabled) }
    }

    nonisolated static var apiKey: String {
        get { UserDefaults.standard.string(forKey: DefaultsKeys.virusTotalAPIKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKeys.virusTotalAPIKey) }
    }

    /// `malicious` count at/above which we treat a file as a confirmed
    /// threat (auto-quarantine). Below it but >0 is surfaced as REVIEW.
    static let quarantineThreshold = 3

    private static let minInterval: TimeInterval = 16   // ~4 req/min

    private var cache: [String: Verdict] = [:]
    private var lastRequestAt = Date.distantPast

    // MARK: - Lookup

    /// Caller is responsible for gating on `isEnabled` — kept out of here so
    /// the Settings "Test key" button can validate before the feature is on.
    func lookup(sha256: String) async -> Result<Verdict, LookupError> {
        let key = Self.apiKey
        guard !key.isEmpty else { return .failure(.noKey) }
        if let hit = cache[sha256] { return .success(hit) }

        // Serialise to respect the free-tier rate limit.
        let since = Date().timeIntervalSince(lastRequestAt)
        if since < Self.minInterval {
            try? await Task.sleep(nanoseconds: UInt64((Self.minInterval - since) * 1_000_000_000))
        }
        lastRequestAt = Date()

        guard let url = URL(string: "https://www.virustotal.com/api/v3/files/\(sha256)") else {
            return .failure(.network)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(key, forHTTPHeaderField: "x-apikey")

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure(.network) }
            switch http.statusCode {
            case 200: break
            case 404: return .failure(.notFound)        // VT has never seen this file
            case 401, 403: return .failure(.noKey)
            case 429: return .failure(.rateLimited)
            default: return .failure(.http(http.statusCode))
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataObj = json["data"] as? [String: Any],
                  let attrs = dataObj["attributes"] as? [String: Any],
                  let stats = attrs["last_analysis_stats"] as? [String: Any] else {
                return .failure(.network)
            }
            let mal = stats["malicious"] as? Int ?? 0
            let susp = stats["suspicious"] as? Int ?? 0
            let total = stats.values.compactMap { $0 as? Int }.reduce(0, +)
            let verdict = Verdict(sha256: sha256, malicious: mal, suspicious: susp, total: total)
            cache[sha256] = verdict
            return .success(verdict)
        } catch {
            return .failure(.network)
        }
    }

    /// One-off key validation used by the Settings "Test" button. Looks up
    /// the harmless EICAR hash; any non-auth response means the key works.
    func validateKey() async -> Bool {
        let eicar = "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f"
        switch await lookup(sha256: eicar) {
        case .success: return true
        case .failure(.notFound), .failure(.rateLimited): return true
        case .failure: return false
        }
    }
}
