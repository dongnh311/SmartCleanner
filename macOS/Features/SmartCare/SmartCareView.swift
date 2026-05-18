import SwiftUI

@MainActor
struct SmartCareView: View {

    @EnvironmentObject private var container: AppContainer

    @State private var report: SmartCareReport?
    @State private var phase: Phase = .idle
    /// Set during the auto-rescan after a Clean so the pillar view stays
    /// visible (just shows an inline "Refreshing…" chip) instead of
    /// blanking out to a full-screen spinner. The first scan still
    /// uses `phase = .scanning` so the blank-with-spinner empty state
    /// covers the "no report yet" case.
    @State private var isRefreshing = false
    @State private var lastError: String?
    @State private var cleanedMessage: String?
    @State private var lastRunLog: CleanupLog?
    @State private var showingLog = false

    /// Which pillar's detail sheet is currently presented. Nil = no sheet.
    @State private var activeSheet: PillarKind?

    /// Per-pillar selection — populated from the report on scan, edited
    /// in the detail sheets, consumed when the Run button fires.
    @State private var cleanupSelection: Set<UUID> = []
    @State private var trashSelection: Set<UUID> = []
    @State private var malwareSelection: Set<URL> = []
    @State private var speedSelection: Set<Int32> = []
    @State private var bgAppsSelection: Set<Int32> = []

    @StateObject private var progress = CleanProgressTracker()

    enum Phase: Equatable { case idle, scanning, ready, cleaning }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                runFloatingButton
            }
            CleanProgressFooter(tracker: progress)
        }
        .animation(.smooth(duration: 0.25), value: phase)
        .sheet(item: $activeSheet) { kind in
            detailSheet(for: kind)
        }
        .sheet(isPresented: $showingLog) {
            if let log = lastRunLog { CleanupLogSheet(log: log) { showingLog = false } }
        }
        .task(id: container.smartCareAutoRunToken) {
            guard container.smartCareAutoRunToken != nil, phase != .scanning else { return }
            container.smartCareAutoRunToken = nil
            await runScanAsync()
        }
    }

    // MARK: - Header

    private var header: some View {
        ModuleHeader(
            icon: "sparkles",
            title: "Smart Care",
            subtitle: "Cleanup · Protection · Speed — all in one pass",
            accent: .accentColor
        ) {
            if isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Refreshing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if phase == .ready, let report {
                Text(report.scannedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if phase == .ready {
                Button { runScan() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .disabled(isRefreshing)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:                idleContent
        case .scanning:            scanningContent
        case .ready, .cleaning:    readyContent
        }
    }

    private var idleContent: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .heroIconBackdrop(color: .accentColor)
            Text("Run Smart Care to scan your Mac")
                .font(.system(size: 22, weight: .semibold))
            Text("Inspects junk + trash, malware persistence, and high-memory apps in parallel.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
        }
    }

    private var scanningContent: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Running all scans…")
                .font(.titleMedium).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var readyContent: some View {
        guard let report else { return AnyView(EmptyView()) }
        return AnyView(
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    headline(report)
                    pillars(report)
                    if cleanedMessage != nil || lastRunLog != nil {
                        HStack(spacing: 8) {
                            if let cleanedMessage {
                                Label(cleanedMessage, systemImage: "checkmark.circle.fill")
                                    .font(.callout)
                                    .foregroundStyle(.green)
                            }
                            if lastRunLog != nil {
                                Button("Show log") { showingLog = true }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                            }
                        }
                    }
                    if let lastError {
                        Label(lastError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.xl)
                .padding(.bottom, 80)  // clear the floating Run button
            }
        )
    }

    private func headline(_ report: SmartCareReport) -> some View {
        VStack(spacing: 6) {
            Text(headlineText(for: report))
                .font(.system(size: 26, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Cleanup removes junk, Protection neutralises threats, Speed quits heavy apps. Review each, then hit Run.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
        }
    }

    private func headlineText(for report: SmartCareReport) -> String {
        if report.hasDanger { return "Some items need your attention." }
        if report.totalCleanableBytes > 0 || report.totalIssueCount > 0 {
            return "Alright, here's what I've found."
        }
        return "Your Mac is in great shape."
    }

    // MARK: - Pillars

    private func pillars(_ report: SmartCareReport) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            PillarCard(model: cleanupPillar(report)) { activeSheet = .cleanup }
            PillarCard(model: protectionPillar(report)) { activeSheet = .protection }
            PillarCard(model: speedPillar(report)) { activeSheet = .speed }
        }
    }

    private func cleanupPillar(_ report: SmartCareReport) -> PillarModel {
        let totalBytes = report.cleanupItems.reduce(Int64(0)) { $0 + $1.size }
            + report.trashItems.reduce(Int64(0)) { $0 + $1.size }
        let hasItems = !report.cleanupItems.isEmpty || !report.trashItems.isEmpty
        return PillarModel(
            kind: .cleanup,
            gradient: PillarGradient.cleanup,
            icon: "internaldrive.fill",
            title: "Cleanup",
            subtitle: "Removes unneeded junk",
            primaryValue: hasItems ? totalBytes.formattedBytes : "0 KB",
            primaryColor: hasItems ? Color.cyan : Color.green,
            showsCheckmark: !hasItems,
            hasIssue: hasItems,
            detailsLabel: hasItems ? "Review Details…" : nil
        )
    }

    private func protectionPillar(_ report: SmartCareReport) -> PillarModel {
        let summary: (value: String, color: Color, hasIssue: Bool) = {
            if report.malwareItems.contains(where: { $0.severity == .danger }) {
                return ("Issues", .red, true)
            }
            if report.malwareItems.contains(where: { $0.severity == .warn }) {
                return ("Review", .orange, true)
            }
            if report.thirdPartyBackgroundCount > 0 {
                return ("\(report.thirdPartyBackgroundCount) hidden", .blue, true)
            }
            return ("OK", .green, false)
        }()
        return PillarModel(
            kind: .protection,
            gradient: PillarGradient.protection,
            icon: "shield.lefthalf.filled",
            title: "Protection",
            subtitle: "Threats + hidden background apps",
            primaryValue: summary.value,
            primaryColor: summary.color,
            primarySuffix: report.thirdPartyBackgroundCount > 0 && report.malwareItems.isEmpty
                ? "menu-bar / daemon apps"
                : nil,
            showsCheckmark: !summary.hasIssue,
            hasIssue: summary.hasIssue,
            detailsLabel: summary.hasIssue ? "Review Details…" : nil
        )
    }

    private func speedPillar(_ report: SmartCareReport) -> PillarModel {
        let hogs = report.ramHogs
        let totalBytes = hogs.reduce(Int64(0)) { $0 + $1.memoryBytes }
        return PillarModel(
            kind: .speed,
            gradient: PillarGradient.speed,
            icon: "speedometer",
            title: "Speed",
            subtitle: "Quit memory-hungry apps",
            primaryValue: hogs.isEmpty ? "OK" : totalBytes.formattedBytes,
            primaryColor: hogs.isEmpty ? Color.green : Color.pink,
            primarySuffix: hogs.isEmpty ? nil : "in \(hogs.count) app\(hogs.count == 1 ? "" : "s")",
            showsCheckmark: hogs.isEmpty,
            hasIssue: !hogs.isEmpty,
            detailsLabel: hogs.isEmpty ? nil : "Review Details…"
        )
    }

    // MARK: - Detail sheets

    @ViewBuilder
    private func detailSheet(for kind: PillarKind) -> some View {
        switch kind {
        case .cleanup:
            CleanupDetailSheet(
                junkItems: report?.cleanupItems ?? [],
                trashItems: report?.trashItems ?? [],
                junkSelection: $cleanupSelection,
                trashSelection: $trashSelection,
                onDone: { activeSheet = nil }
            )
        case .protection:
            ProtectionDetailSheet(
                items: report?.malwareItems ?? [],
                selection: $malwareSelection,
                backgroundApps: report?.backgroundApps ?? [],
                bgAppsSelection: $bgAppsSelection,
                onDone: { activeSheet = nil }
            )
        case .speed:
            SpeedDetailSheet(
                processes: report?.ramHogs ?? [],
                selection: $speedSelection,
                onDone: { activeSheet = nil }
            )
        }
    }

    // MARK: - Floating run button

    @ViewBuilder
    private var runFloatingButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    if phase == .ready { runActions() } else { runScan() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: PillarGradient.cleanup,
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 76, height: 76)
                            .shadow(color: PillarGradient.cleanup[0].opacity(0.4), radius: 16, y: 4)
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                            .frame(width: 76, height: 76)
                        if phase == .scanning || phase == .cleaning {
                            ProgressView().controlSize(.large).tint(.white)
                        } else {
                            Text(phase == .ready ? "Clean" : "Scan")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(phase == .scanning || phase == .cleaning)
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
            .padding(.bottom, Spacing.lg)
        }
    }

    // MARK: - Actions

    private func runScan() {
        Task { @MainActor in await runScanAsync() }
    }

    /// `quiet: true` means the rescan is happening *after* a Clean and the
    /// post-clean result should remain visible — keep the pillar view in
    /// `.ready`, just flip `isRefreshing` so a small inline indicator
    /// surfaces. Without that, the post-clean rescan blanks the whole
    /// content area to a "Running all scans…" spinner and the user loses
    /// the freed/quarantined summary they were reading.
    private func runScanAsync(quiet: Bool = false) async {
        if quiet {
            isRefreshing = true
        } else {
            phase = .scanning
        }
        // Preserve `cleanedMessage` + `lastRunLog` so the "Show log" link
        // stays available across the auto-rescan that follows a Clean.
        lastError = nil
        let startedAt = Date()
        let r = await container.smartCareOrchestrator.run()
        report = r
        cleanupSelection = Set(r.cleanupItems.filter { $0.safetyLevel == .safe }.map(\.id))
        trashSelection = Set(r.trashItems.map(\.id))
        // Never auto-select Protection or Speed — quarantining a launch
        // agent or quitting a running app moves user state. Require a
        // deliberate tick in the Review Details sheet first.
        malwareSelection = []
        speedSelection = []
        bgAppsSelection = []
        if quiet {
            isRefreshing = false
        } else {
            phase = .ready
        }
        try? await container.db.recordScan(
            module: "SmartCare",
            startedAt: startedAt,
            finishedAt: Date(),
            itemsScanned: r.totalIssueCount,
            bytesTotal: r.totalCleanableBytes,
            sourcePath: nil,
            status: "scanned"
        )
    }

    private func runActions() {
        guard let report else { return }
        phase = .cleaning
        cleanedMessage = nil
        lastError = nil
        Task { @MainActor in
            let selectedJunk = report.cleanupItems.filter { cleanupSelection.contains($0.id) }
            let selectedTrash = report.trashItems.filter { trashSelection.contains($0.id) }
            let selectedThreats = report.malwareItems.filter { malwareSelection.contains($0.id) }
            let selectedSpeedPIDs = report.ramHogs.filter { speedSelection.contains($0.pid) }.map(\.pid)
            let selectedBgPIDs = report.backgroundApps.filter { bgAppsSelection.contains($0.pid) }.map(\.pid)
            // De-dup in case the same pid appears in both pillars (unlikely
            // since Speed filters by RAM ≥ 500 MB and bg apps are usually
            // much smaller, but cheap to guard).
            let selectedPIDs = Array(Set(selectedSpeedPIDs + selectedBgPIDs))

            let totalTasks = selectedJunk.count + selectedTrash.count + selectedThreats.count + selectedPIDs.count
            progress.start(total: totalTasks)
            let handler = progress.makeHandler()

            async let cleanupResult = container.smartCareOrchestrator.cleanSelected(
                junk: selectedJunk, trash: selectedTrash, onProgress: handler
            )
            async let threatsQuarantined = container.smartCareOrchestrator.quarantineThreats(
                selectedThreats, onProgress: handler
            )
            async let processesQuit = container.smartCareOrchestrator.quitProcesses(selectedPIDs)

            let (clean, threats, quits) = await (cleanupResult, threatsQuarantined, processesQuit)
            progress.finish()

            lastRunLog = CleanupLog(
                clean: clean,
                threatsQuarantined: threats,
                appsQuit: quits,
                runAt: Date()
            )

            var parts: [String] = []
            // Always show "Freed X" once a clean has run (even at 0 KB) so
            // the user can compare against the Dashboard disk gauge — and
            // see at a glance which slice was real disk recovery vs the
            // moved-but-still-on-disk quarantine slice.
            let didRun = clean.removed.count + clean.failed.count > 0 || threats > 0 || quits > 0
            if didRun {
                parts.append("Freed \(clean.bytesFreed.formattedBytes)")
            }
            if clean.bytesQuarantined > 0 {
                parts.append("\(clean.bytesQuarantined.formattedBytes) quarantined (7-day auto-purge)")
            }
            if threats > 0 {
                parts.append("\(threats) threat\(threats == 1 ? "" : "s") quarantined")
            }
            if quits > 0 {
                parts.append("\(quits) app\(quits == 1 ? "" : "s") quit")
            }
            cleanedMessage = parts.isEmpty
                ? "Nothing selected — pick items in each pillar's Review Details first"
                : parts.joined(separator: " · ")

            try? await container.db.recordScan(
                module: "SmartCare.run",
                startedAt: Date().addingTimeInterval(-1),
                finishedAt: Date(),
                itemsScanned: clean.removed.count + threats + quits,
                bytesTotal: clean.bytesProcessed,
                sourcePath: nil,
                status: clean.failed.isEmpty ? "completed" : "partial"
            )

            await runScanAsync(quiet: true)
        }
    }
}

@MainActor
private func toggleBinding<ID: Hashable>(for id: ID, in set: Binding<Set<ID>>) -> Binding<Bool> {
    Binding(
        get: { set.wrappedValue.contains(id) },
        set: { isOn in
            if isOn { set.wrappedValue.insert(id) }
            else { set.wrappedValue.remove(id) }
        }
    )
}

// MARK: - Pillar card

enum PillarKind: String, Identifiable, Hashable {
    case cleanup, protection, speed
    var id: String { rawValue }
}

private struct PillarModel {
    let kind: PillarKind
    let gradient: [Color]
    let icon: String
    let title: String
    let subtitle: String
    let primaryValue: String
    let primaryColor: Color
    var primarySuffix: String? = nil
    let showsCheckmark: Bool
    let hasIssue: Bool
    let detailsLabel: String?
}

private struct PillarCard: View {
    let model: PillarModel
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            artwork
            HStack(spacing: 4) {
                if model.showsCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.cyan)
                        .font(.system(size: 14))
                } else if model.hasIssue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                }
                Text(model.title)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(model.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(model.primaryValue)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(model.primaryColor)
                .contentTransition(.numericText())
            if let suffix = model.primarySuffix {
                Text(suffix)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let label = model.detailsLabel {
                Button(action: onReview) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 22)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(
                    colors: model.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 110, height: 110)
                .shadow(color: model.gradient.last!.opacity(0.35), radius: 12, y: 6)
            Image(systemName: model.icon)
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }
}

// MARK: - Detail sheets

private struct CleanupDetailSheet: View {
    let junkItems: [CleanableItem]
    let trashItems: [CleanableItem]
    @Binding var junkSelection: Set<UUID>
    @Binding var trashSelection: Set<UUID>
    let onDone: () -> Void

    private static let maxJunkRows = 200

    private var junkBytes: Int64 { junkItems.filter { junkSelection.contains($0.id) }.reduce(0) { $0 + $1.size } }
    private var trashBytes: Int64 { trashItems.filter { trashSelection.contains($0.id) }.reduce(0) { $0 + $1.size } }

    var body: some View {
        DetailSheetChrome(
            title: "Cleanup Details",
            subtitle: "Junk and trash will be removed when you run Smart Care. Uncheck anything you want to keep.",
            selectedSummary: "Selected: \((junkBytes + trashBytes).formattedBytes)",
            onDone: onDone
        ) {
            List {
                Section(header: sectionHeader("System Junk", count: junkItems.count, total: junkItems.reduce(0) { $0 + $1.size })) {
                    ForEach(junkItems.prefix(Self.maxJunkRows)) { item in
                        CleanupItemRow(
                            item: item,
                            isOn: toggleBinding(for: item.id, in: $junkSelection)
                        ) {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                    }
                    if junkItems.count > Self.maxJunkRows {
                        Text("+ \(junkItems.count - Self.maxJunkRows) more — open System Junk for the full list")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !trashItems.isEmpty {
                    Section(header: sectionHeader("Trash Bins", count: trashItems.count, total: trashItems.reduce(0) { $0 + $1.size })) {
                        ForEach(trashItems) { item in
                            CleanupItemRow(
                                item: item,
                                isOn: toggleBinding(for: item.id, in: $trashSelection)
                            ) {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
        }
    }
}

private struct ProtectionDetailSheet: View {
    let items: [ThreatItem]
    @Binding var selection: Set<URL>
    let backgroundApps: [BackgroundApp]
    @Binding var bgAppsSelection: Set<Int32>
    let onDone: () -> Void

    private var summary: String {
        let threats = selection.count
        let bg = bgAppsSelection.count
        if threats == 0 && bg == 0 { return "Nothing selected" }
        var parts: [String] = []
        if threats > 0 { parts.append("\(threats) threat\(threats == 1 ? "" : "s") → quarantine") }
        if bg > 0 { parts.append("\(bg) app\(bg == 1 ? "" : "s") → quit") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        DetailSheetChrome(
            title: "Protection Details",
            subtitle: "Persistence threats are quarantined; selected background apps get SIGTERM. Review both — Apple system processes are listed for visibility but rarely safe to quit.",
            selectedSummary: summary,
            onDone: onDone
        ) {
            List {
                if !items.isEmpty {
                    Section(header: sectionHeader("Persistence threats", count: items.count, total: 0)) {
                        ForEach(items) { (item: ThreatItem) in
                            threatRow(item)
                        }
                    }
                }
                if !backgroundApps.isEmpty {
                    Section(header: bgHeader) {
                        ForEach(backgroundApps) { (app: BackgroundApp) in
                            backgroundRow(app)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
        }
    }

    private var bgHeader: some View {
        HStack {
            Text("Background apps").font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(backgroundApps.count) running")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func threatRow(_ item: ThreatItem) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: toggleBinding(for: item.url, in: $selection)).labelsHidden()
            Image(systemName: item.severity.symbol)
                .foregroundStyle(item.severity.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                Text(item.url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.severity.label)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(item.severity.color.opacity(0.18))
                .foregroundStyle(item.severity.color)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }

    private func backgroundRow(_ app: BackgroundApp) -> some View {
        let tint: Color = app.isAppleProcess ? .secondary : .blue
        let badge = app.isAppleProcess ? "APPLE" : "3RD-PARTY"
        return HStack(spacing: 8) {
            Toggle("", isOn: toggleBinding(for: app.pid, in: $bgAppsSelection)).labelsHidden()
            Image(systemName: app.isAppleProcess ? "applelogo" : "app.dashed")
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                Text(app.bundleID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if app.memoryBytes > 0 {
                Text(app.memoryBytes.formattedBytes)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(badge)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(tint.opacity(0.18))
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

private struct SpeedDetailSheet: View {
    let processes: [ProcessSnapshot]
    @Binding var selection: Set<Int32>
    let onDone: () -> Void

    private var selectedBytes: Int64 {
        processes.filter { selection.contains($0.pid) }.reduce(0) { $0 + $1.memoryBytes }
    }

    var body: some View {
        DetailSheetChrome(
            title: "Speed Details",
            subtitle: "Apps holding ≥ 500 MB. Quit anything you don't actively need to reclaim RAM — only your selections will be terminated.",
            selectedSummary: "Will free ≈ \(selectedBytes.formattedBytes)",
            onDone: onDone
        ) {
            List {
                ForEach(processes) { proc in
                    HStack(spacing: 8) {
                        Toggle("", isOn: toggleBinding(for: proc.pid, in: $selection)).labelsHidden()
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.pink)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proc.name)
                                .font(.system(size: 13, weight: .medium))
                            Text("pid \(proc.pid) · \(String(format: "%.0f", proc.cpuPercent))% CPU")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(proc.memoryBytes.formattedBytes)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.pink)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Sheet chrome

private struct DetailSheetChrome<Content: View>: View {
    let title: String
    let subtitle: String
    let selectedSummary: String
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)
            Divider()
            content()
                .frame(maxHeight: .infinity)
            Divider()
            HStack {
                Text(selectedSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(Spacing.md)
        }
        .frame(width: 720, height: 540)
        .background(PopupBackground())
    }
}

@MainActor
@ViewBuilder
private func sectionHeader(_ title: String, count: Int, total: Int64) -> some View {
    HStack {
        Text(title).font(.system(size: 12, weight: .semibold))
        Spacer()
        Text("\(count) items · \(total.formattedBytes)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Cleanup log (CMM-style transparency)

struct CleanupLog {
    /// Cap per-section row arrays — a 10K-file clean otherwise retains
    /// ~1MB of `String` paths until next Clean, and the SwiftUI List
    /// builds 10K row identities on open. The Cleanup module shows the
    /// full list if the user wants every entry.
    static let maxSampleSize = 200

    let cleanedBytes: Int64
    let quarantinedBytes: Int64
    let cleanedSample: [String]
    let cleanedCount: Int
    let protectedSample: [String]
    let protectedCount: Int
    let erroredSample: [(String, String)]
    let erroredCount: Int
    let threatsQuarantined: Int
    let appsQuit: Int
    let runAt: Date

    init(clean: CleanResult, threatsQuarantined: Int, appsQuit: Int, runAt: Date) {
        var protected: [String] = []
        var errored: [(String, String)] = []
        for failure in clean.failed {
            if failure.reason.hasPrefix("Refused:") {
                protected.append(failure.item.url.path)
            } else {
                errored.append((failure.item.url.path, failure.reason))
            }
        }
        self.cleanedBytes = clean.bytesFreed
        self.quarantinedBytes = clean.bytesQuarantined
        self.cleanedCount = clean.removed.count
        self.cleanedSample = clean.removed.prefix(Self.maxSampleSize).map(\.url.path)
        self.protectedCount = protected.count
        self.protectedSample = Array(protected.prefix(Self.maxSampleSize))
        self.erroredCount = errored.count
        self.erroredSample = Array(errored.prefix(Self.maxSampleSize))
        self.threatsQuarantined = threatsQuarantined
        self.appsQuit = appsQuit
        self.runAt = runAt
    }
}

@MainActor
private struct CleanupLogSheet: View {
    let log: CleanupLog
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cleanup Log")
                    .font(.title2.weight(.semibold))
                Text("Per-file breakdown of what Smart Care did at \(log.runAt.formatted(date: .omitted, time: .standard)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)
            Divider()

            List {
                summarySection
                if log.cleanedCount > 0 {
                    Section(header: header("Removed", count: log.cleanedCount, tint: .green)) {
                        ForEach(log.cleanedSample, id: \.self) { path in
                            row(path: path, symbol: "checkmark.circle.fill", tint: .green)
                        }
                        truncationHint(shown: log.cleanedSample.count, total: log.cleanedCount)
                    }
                }
                if log.protectedCount > 0 {
                    Section(header: header("Skipped for safety", count: log.protectedCount, tint: .blue)) {
                        ForEach(log.protectedSample, id: \.self) { path in
                            row(path: path, symbol: "shield.lefthalf.filled", tint: .blue)
                        }
                        truncationHint(shown: log.protectedSample.count, total: log.protectedCount)
                    }
                }
                if log.erroredCount > 0 {
                    Section(header: header("Errors", count: log.erroredCount, tint: .orange)) {
                        ForEach(log.erroredSample, id: \.0) { (path, reason) in
                            VStack(alignment: .leading, spacing: 2) {
                                row(path: path, symbol: "exclamationmark.triangle.fill", tint: .orange)
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .padding(.leading, 26)
                            }
                        }
                        truncationHint(shown: log.erroredSample.count, total: log.erroredCount)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(Spacing.md)
        }
        .frame(width: 720, height: 540)
        .background(PopupBackground())
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            summaryRow("Cleanup",
                       value: log.cleanedBytes.formattedBytes + (log.quarantinedBytes > 0 ? " + \(log.quarantinedBytes.formattedBytes) Q" : ""),
                       hint: "\(log.cleanedCount) removed · \(log.protectedCount) protected · \(log.erroredCount) errors" + (log.quarantinedBytes > 0 ? " · Q = quarantined (7-day auto-purge)" : ""),
                       symbol: "trash.circle.fill", tint: (log.cleanedBytes + log.quarantinedBytes) > 0 ? .green : .secondary)
            summaryRow("Protection", value: log.threatsQuarantined > 0 ? "\(log.threatsQuarantined) threats" : "—",
                       hint: log.threatsQuarantined > 0 ? "Moved to 7-day quarantine" : "Nothing quarantined",
                       symbol: "shield.lefthalf.filled", tint: log.threatsQuarantined > 0 ? .red : .secondary)
            summaryRow("Speed", value: log.appsQuit > 0 ? "\(log.appsQuit) apps" : "—",
                       hint: log.appsQuit > 0 ? "Sent SIGTERM" : "No apps quit",
                       symbol: "speedometer", tint: log.appsQuit > 0 ? .pink : .secondary)
        } header: {
            Text("Summary")
        }
    }

    @ViewBuilder
    private func truncationHint(shown: Int, total: Int) -> some View {
        if total > shown {
            Text("+ \(total - shown) more — open the relevant module for the full list")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        }
    }

    private func header(_ title: String, count: Int, tint: Color) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private func row(path: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    private func summaryRow(_ title: String, value: String, hint: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 18))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 2)
    }
}
