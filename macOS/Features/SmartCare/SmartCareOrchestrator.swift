import Foundation

struct SmartCareReport: Sendable {
    let cleanupItems: [CleanableItem]
    let trashItems: [CleanableItem]
    let malwareItems: [ThreatItem]
    let ramHogs: [ProcessSnapshot]
    /// Background apps (LSUIElement / LSBackgroundOnly) surfaced under
    /// the Protection pillar so the user can audit "what's running that
    /// I don't see in the Dock" — covers menu-bar utilities and hidden
    /// daemons that might be exfiltrating data.
    let backgroundApps: [BackgroundApp]
    let scannedAt: Date

    var totalCleanableBytes: Int64 {
        cleanupItems.reduce(Int64(0)) { $0 + $1.size }
            + trashItems.reduce(Int64(0)) { $0 + $1.size }
    }
    var totalIssueCount: Int {
        cleanupItems.count + trashItems.count + malwareItems.count + ramHogs.count
    }
    var hasDanger: Bool {
        malwareItems.contains { $0.severity == .danger }
    }
    /// Non-Apple background apps the user should glance at. Apple
    /// processes are listed for completeness but excluded from the count
    /// so the pillar badge doesn't claim "issues" over cfprefsd.
    var thirdPartyBackgroundCount: Int {
        backgroundApps.filter { !$0.isAppleProcess }.count
    }
}

actor SmartCareOrchestrator {

    private let systemJunk: SystemJunkScanner
    private let trash: TrashBinScanner
    private let malware: MalwareScanner
    private let processes: ProcessMonitor

    /// RAM threshold for the Speed pillar: surface apps holding at least
    /// 500 MB. Below this it's not worth recommending a quit — the user
    /// would barely notice the freed memory.
    private static let ramHogThreshold: Int64 = 500 * 1024 * 1024

    init(systemJunk: SystemJunkScanner,
         trash: TrashBinScanner,
         malware: MalwareScanner,
         processes: ProcessMonitor) {
        self.systemJunk = systemJunk
        self.trash = trash
        self.malware = malware
        self.processes = processes
    }

    func run() async -> SmartCareReport {
        async let junkTask = (try? systemJunk.scan()) ?? []
        async let trashTask = (try? trash.scan()) ?? []
        async let malwareTask = malware.scan()
        async let processesTask = processes.snapshot()

        // Cleanup pillar mirrors Quick Clean exactly — safe items only.
        // Review-level items live under System Junk in the sidebar; the
        // user opens that module to handle them manually.
        let junk = (await junkTask).filter { $0.safetyLevel == .safe }
        let trashItems = await trashTask
        let malwareItems = await malwareTask
        let processList = await processesTask

        let myPID = getpid()
        let ramHogs = processList
            .filter { $0.memoryBytes >= Self.ramHogThreshold && $0.pid != myPID }
            .sorted { $0.memoryBytes > $1.memoryBytes }
            .prefix(10)
            .map { $0 }

        // Background app scan needs NSWorkspace on MainActor. Reuse the
        // process snapshot we already have for RSS lookup so we don't
        // fork ps a second time.
        // ps can emit duplicate pids during process transitions; `unique…`
        // would crash here.
        let rssByPID = Dictionary(processList.map { ($0.pid, $0.memoryBytes) },
                                  uniquingKeysWith: { first, _ in first })
        let backgroundApps = await MainActor.run { BackgroundAppScanner.scan(rssByPID: rssByPID) }

        let report = SmartCareReport(
            cleanupItems: junk,
            trashItems: trashItems,
            malwareItems: malwareItems,
            ramHogs: ramHogs,
            backgroundApps: backgroundApps,
            scannedAt: Date()
        )
        Log.scanner.info("SmartCare report: \(report.totalIssueCount) issues, \(report.totalCleanableBytes.formattedBytes) cleanable, \(ramHogs.count) ram hogs, \(report.thirdPartyBackgroundCount) third-party bg apps")
        return report
    }

    func cleanSelected(junk: [CleanableItem], trash: [CleanableItem],
                       onProgress: CleanProgressHandler? = nil) async -> CleanResult {
        async let junkResult = systemJunk.clean(junk, onProgress: onProgress)
        async let trashResult = self.trash.clean(trash, onProgress: onProgress)
        let (j, t) = await (junkResult, trashResult)
        return CleanResult(
            removed: j.removed + t.removed,
            failed: j.failed + t.failed,
            bytesFreed: j.bytesFreed + t.bytesFreed,
            bytesQuarantined: j.bytesQuarantined + t.bytesQuarantined
        )
    }

    func quarantineThreats(_ items: [ThreatItem],
                           onProgress: CleanProgressHandler? = nil) async -> Int {
        await malware.quarantineThreats(items, onProgress: onProgress)
    }

    /// Sends SIGTERM to each PID (force = false). Returns how many actually
    /// exited. We don't escalate to SIGKILL — graceful quit lets the app
    /// flush state; if it ignores SIGTERM the user can quit manually.
    func quitProcesses(_ pids: [Int32]) async -> Int {
        var quit = 0
        for pid in pids {
            if await processes.kill(pid: pid, force: false) { quit += 1 }
        }
        return quit
    }
}
