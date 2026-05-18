import SwiftUI
import AppKit

@MainActor
struct QuickCleanView: View {

    @EnvironmentObject private var container: AppContainer

    @State private var phase: Phase = .idle
    @State private var groups: [Group] = []
    @State private var selectedIDs: Set<Group.ID> = []
    @State private var scannedAt: Date?
    @State private var resultMessage: String?
    @State private var detectedTools: [DetectedDevTool] = []
    @State private var showRunningToolsConfirm = false
    @State private var detailGroup: Group?
    @StateObject private var progress = CleanProgressTracker()

    enum Phase: Equatable { case idle, scanning, ready, cleaning, done }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(
                icon: "bolt.circle",
                title: "Quick Clean",
                subtitle: "Caches, logs and trash — safe to delete, will regenerate",
                accent: .orange
            ) {
                if phase == .ready || phase == .done {
                    Button {
                        runScan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                }
            }
            content
        }
        .animation(.smooth(duration: 0.25), value: phase)
        .task { if phase == .idle { runScan() } }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            EmptyStateView(
                icon: "bolt.circle",
                title: "Ready to clean",
                message: "Scans User Caches, System Caches, Logs, Xcode artifacts and Trash Bins.",
                tint: .orange
            ) {
                Button { runScan() } label: {
                    Label("Start Scan", systemImage: "magnifyingglass")
                        .frame(maxWidth: 220).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .scanning:
            scanningView
        case .ready, .cleaning, .done:
            readyView
        }
    }

    private var scanningView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Scanning safe-to-delete items…")
                .font(.titleMedium).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    hero
                        .padding(.top, Spacing.xl)
                    groupList
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.lg)
            }
            RunningDevToolsBanner(tools: detectedTools)
            CleanProgressFooter(tracker: progress, tint: .orange)
            Divider()
            footer
        }
        .confirmationDialog(
            runningToolsConfirmTitle,
            isPresented: $showRunningToolsConfirm,
            titleVisibility: .visible
        ) {
            Button("Continue — skip caches for \(detectedTools.count) tool\(detectedTools.count == 1 ? "" : "s")", role: .destructive) {
                cleanNow(skipConfirm: true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(runningToolsConfirmMessage)
        }
        .sheet(item: $detailGroup) { group in
            DetailSheet(
                title: group.title,
                subtitle: "\(group.items.count) item\(group.items.count == 1 ? "" : "s") · \(group.totalBytes.formattedBytes)",
                accent: .orange,
                onClose: { detailGroup = nil }
            ) {
                List {
                    ForEach(group.items) { item in
                        detailRow(item)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func detailRow(_ item: CleanableItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13))
                Text(item.url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes)
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }

    private var runningToolsConfirmTitle: String {
        "Running: \(detectedTools.map(\.name).joined(separator: ", "))"
    }

    private var runningToolsConfirmMessage: String {
        let paths = detectedTools.flatMap(\.hints).prefix(6).joined(separator: "\n• ")
        return "These paths will be skipped to avoid crashing the IDE or killing the emulator:\n\n• \(paths)\n\nProceed with cleaning the remaining items?"
    }

    private var hero: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: phase == .done ? "checkmark.seal.fill" : "bolt.circle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(phase == .done ? .green : .orange)
                .heroIconBackdrop(color: phase == .done ? .green : .orange)
            Text(selectedTotalBytes.formattedBytes)
                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
            Text(phase == .done ? "Cleaned successfully" : "selected to clean")
                .font(.callout).foregroundStyle(.secondary)
            if let message = resultMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
                    .padding(.top, 4)
            }
            if let scannedAt {
                Text("Last scan: \(scannedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var groupList: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(groups) { group in
                groupRow(group)
            }
        }
    }

    private func groupRow(_ group: Group) -> some View {
        let isSelected = selectedIDs.contains(group.id)
        return HStack(spacing: Spacing.md) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { newValue in
                    if newValue { selectedIDs.insert(group.id) } else { selectedIDs.remove(group.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(group.items.isEmpty || phase == .cleaning)

            ZStack {
                Circle().fill(Color.orange.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: group.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.title).font(.system(size: 14, weight: .semibold))
                Text(group.items.isEmpty ? "Nothing to clean" : "\(group.items.count) items")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Text(group.totalBytes.formattedBytes)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(group.items.isEmpty ? .tertiary : .secondary)
                .contentTransition(.numericText())

            if !group.items.isEmpty {
                InfoButton { detailGroup = group }
            }
        }
        .padding(Spacing.md)
        .cardStyle()
        .opacity(group.items.isEmpty ? 0.55 : 1)
    }

    private var footer: some View {
        HStack(spacing: Spacing.md) {
            Button {
                if selectedIDs.count == groups.filter({ !$0.items.isEmpty }).count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(groups.filter { !$0.items.isEmpty }.map(\.id))
                }
            } label: {
                Text(selectedIDs.isEmpty ? "Select All" : "Deselect All")
            }
            .controlSize(.regular)
            .disabled(phase == .cleaning || groups.allSatisfy { $0.items.isEmpty })

            Spacer()

            if phase == .cleaning {
                ProgressView().controlSize(.small)
                Text("Cleaning…").foregroundStyle(.secondary).font(.callout)
            } else {
                Text("Caches and logs regenerate as apps run.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Button {
                cleanNow()
            } label: {
                Label("Clean Now — \(selectedTotalBytes.formattedBytes)", systemImage: "leaf.fill")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedIDs.isEmpty || selectedTotalBytes == 0 || phase == .cleaning)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(.bar)
    }

    // MARK: - Computed

    private var selectedTotalBytes: Int64 {
        groups.filter { selectedIDs.contains($0.id) }
              .reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    // MARK: - Actions

    private func runScan() {
        Task { @MainActor in
            phase = .scanning
            resultMessage = nil
            let startedAt = Date()
            let junk = (try? await container.systemJunkScanner.scan()) ?? []
            let trash = (try? await container.trashBinScanner.scan()) ?? []
            let safeJunk = junk.filter { $0.safetyLevel == .safe }
            let assembled = Self.assemble(systemJunk: safeJunk, trash: trash)
            self.groups = assembled
            self.selectedIDs = Set(assembled.filter { !$0.items.isEmpty }.map(\.id))
            self.scannedAt = Date()
            self.detectedTools = LiveDevTools.detect()
            self.phase = .ready
            let total = assembled.reduce(Int64(0)) { $0 + $1.totalBytes }
            let count = assembled.reduce(0) { $0 + $1.items.count }
            try? await container.db.recordScan(
                module: "QuickClean",
                startedAt: startedAt,
                finishedAt: Date(),
                itemsScanned: count,
                bytesTotal: total,
                sourcePath: nil,
                status: "scanned"
            )
        }
    }

    private func cleanNow(skipConfirm: Bool = false) {
        let selected = groups.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        // Refresh dev-tools snapshot at click-time. If anything risky is up
        // and the user hasn't confirmed yet, hand them the dialog first.
        if !skipConfirm {
            let live = LiveDevTools.detect()
            self.detectedTools = live
            if !live.isEmpty {
                showRunningToolsConfirm = true
                return
            }
        }

        let trashItems = selected.filter { $0.id == .trash }.flatMap(\.items)
        let junkItems = selected.filter { $0.id != .trash }.flatMap(\.items)

        Task { @MainActor in
            phase = .cleaning
            resultMessage = nil
            progress.start(total: junkItems.count + trashItems.count)
            let handler = progress.makeHandler()
            async let junkResult = container.systemJunkScanner.clean(junkItems, onProgress: handler)
            async let trashResult = container.trashBinScanner.clean(trashItems, onProgress: handler)
            let (jr, tr) = await (junkResult, trashResult)
            progress.finish()
            let freed = jr.bytesFreed + tr.bytesFreed
            let quarantined = jr.bytesQuarantined + tr.bytesQuarantined
            let removed = jr.removed.count + tr.removed.count
            let allFailures = jr.failed + tr.failed
            // Split "failed" into "refused for safety" vs real errors so
            // the user doesn't think every protected refusal is a problem.
            let protected = allFailures.filter { $0.reason.hasPrefix("Refused:") }.count
            let errors = allFailures.count - protected

            try? await container.db.recordScan(
                module: "QuickClean",
                startedAt: scannedAt ?? Date().addingTimeInterval(-1),
                finishedAt: Date(),
                itemsScanned: removed + allFailures.count,
                bytesTotal: freed + quarantined,
                sourcePath: nil,
                status: errors == 0 ? "completed" : "partial"
            )

            resultMessage = Self.formatResult(freed: freed, quarantined: quarantined, removed: removed, protected: protected, errors: errors)
            phase = .done

            // Auto-rescan to refresh sizes — but stay on the .done screen visually.
            let junk = (try? await container.systemJunkScanner.scan()) ?? []
            let trash = (try? await container.trashBinScanner.scan()) ?? []
            let safeJunk = junk.filter { $0.safetyLevel == .safe }
            let assembled = Self.assemble(systemJunk: safeJunk, trash: trash)
            self.groups = assembled
            self.selectedIDs = Set(assembled.filter { !$0.items.isEmpty }.map(\.id))
            self.scannedAt = Date()
            self.detectedTools = LiveDevTools.detect()
        }
    }

    // MARK: - Grouping

    /// Buckets system-junk items by category and tacks Trash Bins onto the end.
    /// Categories not represented in Quick Clean's curated set (e.g. mail, photo)
    /// fall through to "Other Safe" so the totals still tally.
    private static func assemble(systemJunk: [CleanableItem], trash: [CleanableItem]) -> [Group] {
        var byID: [Group.ID: [CleanableItem]] = [:]
        for item in systemJunk {
            let id: Group.ID
            switch item.category {
            case .userCache:                  id = .userCache
            case .systemCache:                id = .systemCache
            case .userLog:                    id = .userLog
            case .systemLog:                  id = .systemLog
            case .xcodeJunk, .devToolCache:   id = .xcode
            default:                          id = .other
            }
            byID[id, default: []].append(item)
        }
        if !trash.isEmpty {
            byID[.trash, default: []].append(contentsOf: trash)
        }

        return Group.ID.allCases.map { gid in
            Group(id: gid, items: byID[gid] ?? [])
        }
    }

    /// Splits the post-clean tally into freed / quarantined / protected /
    /// errors. "Freed" is the only number that actually drops disk usage —
    /// "Quarantined" is moved-not-deleted bytes that auto-purge in 7 days,
    /// so we surface it separately to set expectations against the
    /// Dashboard disk gauge.
    static func formatResult(freed: Int64, quarantined: Int64, removed: Int, protected: Int, errors: Int) -> String {
        var parts: [String] = ["Freed \(freed.formattedBytes)"]
        if quarantined > 0 {
            parts.append("\(quarantined.formattedBytes) quarantined (7-day auto-purge)")
        }
        parts.append("\(removed) item\(removed == 1 ? "" : "s") removed")
        if protected > 0 {
            parts.append("\(protected) skipped for safety")
        }
        if errors > 0 {
            parts.append("\(errors) error\(errors == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Group model

extension QuickCleanView {

    struct Group: Identifiable, Equatable {
        enum ID: String, CaseIterable, Hashable, Identifiable {
            case userCache, systemCache, userLog, systemLog, xcode, trash, other
            var id: String { rawValue }
        }

        let id: ID
        let items: [CleanableItem]

        var title: String {
            switch id {
            case .userCache:    return "User Cache Files"
            case .systemCache:  return "System Cache Files"
            case .userLog:      return "User Log Files"
            case .systemLog:    return "System Log Files"
            case .xcode:        return "Xcode & Dev Tool Junk"
            case .trash:        return "Trash Bins"
            case .other:        return "Other Safe Items"
            }
        }

        var symbol: String {
            switch id {
            case .userCache:    return "person.crop.circle"
            case .systemCache:  return "gearshape.2"
            case .userLog:      return "doc.text"
            case .systemLog:    return "doc.text.below.ecg"
            case .xcode:        return "hammer"
            case .trash:        return "trash"
            case .other:        return "tray"
            }
        }

        var totalBytes: Int64 {
            items.reduce(0) { $0 + $1.size }
        }
    }
}
