import Foundation
import AppKit

private struct SmokeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func smokeLog(_ message: String) {
    Log.app.notice("[smoke] \(message, privacy: .public)")
    if let data = "[smoke] \(message)\n".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

enum SmokeTest {

    /// Triggered by env var MACCLEANER_SMOKE_TEST=1. Runs every async surface once,
    /// prints results to stderr, exits with 0 on success and 1 on any failure.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["MACCLEANER_SMOKE_TEST"] == "1"
    }

    @MainActor
    static func run(container: AppContainer) async {
        var failures: [String] = []

        func report(_ name: String, _ block: () async throws -> String) async {
            let start = Date()
            do {
                let summary = try await block()
                let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
                smokeLog("PASS \(name) \(elapsed) — \(summary)")
            } catch {
                smokeLog("FAIL \(name) — \(error.localizedDescription)")
                failures.append(name)
            }
        }

        smokeLog("Starting MacCleaner smoke test")

        await report("RuleEngine.load") {
            try await container.ruleEngine.loadSystemJunkRules()
            let count = await container.ruleEngine.systemJunkRules.count
            return "\(count) rules"
        }

        await report("PermissionsService.refreshAll") {
            let s = await container.permissions.refreshAll()
            return s.map { "\($0.key.title)=\($0.value)" }.joined(separator: ", ")
        }

        await report("FileSizeCalculator.recursiveSize") {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
            let size = await container.sizeCalculator.recursiveSize(at: url)
            return "\(size.formattedBytes)"
        }

        await report("SystemJunkScanner.scan") {
            let items = try await container.systemJunkScanner.scan()
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            return "\(items.count) items, \(total.formattedBytes)"
        }

        await report("TrashBinScanner.scan") {
            let items = try await container.trashBinScanner.scan()
            return "\(items.count) items"
        }

        await report("HierarchicalScanner.listChildren(/)") {
            let urls = await container.hierarchicalScanner.listChildren(of: URL(fileURLWithPath: "/"))
            return "\(urls.count) top-level entries"
        }

        await report("LargeFilesScanner") {
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
            let filter = LargeFilesScanner.Filter(minBytes: 100 * 1024 * 1024, olderThanDays: nil, maxResults: 50)
            let nodes = try await container.largeFilesScanner.scan(at: url, filter: filter)
            return "\(nodes.count) large files"
        }

        await report("AppScanner.scan") {
            let apps = await container.appScanner.scan()
            return "\(apps.count) apps"
        }

        await report("LeftoverDetector.detect (Safari)") {
            let apps = await container.appScanner.scan()
            guard let safari = apps.first(where: { $0.bundleID == "com.apple.Safari" }) ?? apps.first else {
                return "no apps to probe"
            }
            let leftovers = await container.leftoverDetector.detect(for: safari)
            return "\(safari.name): \(leftovers.count) leftovers"
        }

        await report("HomebrewUpdater.outdatedCasks") {
            let casks = (try? await container.homebrewUpdater.outdatedCasks()) ?? []
            return "\(casks.count) outdated casks"
        }

        await report("ProcessMonitor.snapshot") {
            let procs = await container.processMonitor.snapshot()
            return "\(procs.count) processes"
        }

        await report("LoginItemsService.enumerate") {
            let items = await container.loginItems.enumerate()
            return "\(items.count) launch items"
        }

        await report("MemoryService.snapshot") {
            let mem = await container.memoryService.snapshot()
            return "total=\(mem.total.formattedBytes), used=\(mem.used.formattedBytes), pressure=\(String(format: "%.1f", mem.pressurePercent))%"
        }

        await report("BatteryService.snapshot") {
            let b = await container.batteryService.snapshot()
            return b.isPresent ? "\(b.percentage)% cycles=\(b.cycleCount.map(String.init) ?? "—")" : "no battery"
        }

        await report("MalwareScanner.scan") {
            let threats = await container.malwareScanner.scan()
            return "\(threats.count) persistence items, \(threats.filter { $0.severity == .danger }.count) danger"
        }

        await report("RealtimeProtection.engine") {
            let svc = container.realtimeProtection
            // EICAR — the industry-standard *harmless* AV test string. Its
            // digest must be on the bundled blocklist or the file-hash path
            // is broken.
            let eicar = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
            let hash = MalwareHashStore.sha256Hex(of: Data(eicar.utf8))
            guard svc.signatureCount > 0 else { throw SmokeError(message: "blocklist empty") }
            guard svc.isOnBlocklist(hash) else { throw SmokeError(message: "EICAR signature missing from blocklist") }
            return "\(svc.signatureCount) signatures, EICAR matched, watcher=\(svc.isRunning ? "on" : "off")"
        }

        await report("PrivacyCleaner.scan") {
            let items = try await container.privacyCleaner.scan()
            return "\(items.count) browser items"
        }

        await report("MailAttachmentsScanner.scan") {
            let items = try await container.mailAttachmentsScanner.scan()
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            return "\(items.count) attachment dirs, \(total.formattedBytes)"
        }

        await report("PhotoJunkScanner.scan") {
            let items = try await container.photoJunkScanner.scan()
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            return "\(items.count) photo cache dirs, \(total.formattedBytes)"
        }

        await report("PermissionsReader.readEntries") {
            do {
                let rows = try await container.permissionsReader.readEntries()
                return "\(rows.count) TCC entries"
            } catch PermissionsReader.ReadError.accessDenied {
                return "FDA missing (expected without grant)"
            }
        }

        await report("SystemMetrics.sampleCPU") {
            _ = await container.systemMetrics.sampleCPU()
            try? await Task.sleep(nanoseconds: 600_000_000)
            let s = await container.systemMetrics.sampleCPU()
            return String(format: "%.1f%%", s.usagePercent)
        }

        await report("SmartCareOrchestrator.run") {
            let report = await container.smartCareOrchestrator.run()
            return "\(report.totalIssueCount) issues, \(report.totalCleanableBytes.formattedBytes) cleanable"
        }

        let exitStatus: Int32
        if failures.isEmpty {
            smokeLog("OK — all checks passed")
            exitStatus = 0
        } else {
            smokeLog("FAILURES (\(failures.count)): \(failures.joined(separator: ", "))")
            exitStatus = 1
        }
        exit(exitStatus)
    }
}
