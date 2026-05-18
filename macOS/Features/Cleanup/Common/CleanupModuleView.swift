import SwiftUI

@MainActor
struct CleanupModuleView<S: CleanupScanner>: View {

    let scanner: S
    let title: String
    let subtitle: String
    let symbol: String
    /// Section accent tint used for the module header + detail-popup
    /// chrome so the popup blends with the surrounding panel. Defaults
    /// to `.orange` (Cleanup section); Protection-section modules
    /// (Privacy) override with `.red`.
    var accent: Color = .orange

    @EnvironmentObject private var container: AppContainer

    @State private var items: [CleanableItem] = []
    /// Precomputed grouping of `items` — category → items, subgroup
    /// breakdown, and the sort-by-bytes category order. Rebuilt only
    /// when `items` changes (post-scan / post-clean). Without this, the
    /// list pane, detail pane, and `availableCategories` each triggered
    /// a fresh `Dictionary(grouping:)` per render.
    @State private var grouped: GroupedItems = .empty
    @State private var selectedIDs = Set<UUID>()
    @State private var phase: Phase = .idle
    @State private var lastError: String?
    @State private var lastResultMessage: String?
    @State private var selectedCategory: ItemCategory?
    @State private var sortOrder: SortField = .sizeDesc
    @State private var pendingConfirm: PendingConfirm?
    @State private var scanStartedAt: Date?
    @State private var detectedTools: [DetectedDevTool] = []
    @StateObject private var progress = CleanProgressTracker()

    enum Phase: Equatable { case idle, scanning, cleaning, scanned }

    enum SortField: String, CaseIterable, Identifiable {
        case sizeDesc, sizeAsc, modifiedDesc, modifiedAsc, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sizeDesc:     return "Size ↓"
            case .sizeAsc:      return "Size ↑"
            case .modifiedDesc: return "Modified ↓"
            case .modifiedAsc:  return "Modified ↑"
            case .name:         return "Name"
            }
        }
    }

    struct PendingConfirm: Equatable {
        let items: [CleanableItem]
        var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(
                icon: symbol,
                title: title,
                subtitle: subtitle,
                accent: accent
            ) {
                if phase == .scanned && !items.isEmpty {
                    Button {
                        scan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: phase)
        .task { restoreFromCacheIfAvailable() }
    }

    private func restoreFromCacheIfAvailable() {
        // Already have results in this view's state — keep them.
        guard items.isEmpty, phase == .idle else { return }
        guard let cached = container.cleanupResultsCache.get(scannerID: scanner.id) else { return }
        setItems(cached.items)
        scanStartedAt = cached.scannedAt
        selectedCategory = grouped.sortedCategories.first
        phase = .scanned
        let elapsed = Int(Date().timeIntervalSince(cached.scannedAt))
        lastResultMessage = "Restored \(cached.items.count) items from previous scan (\(elapsed)s ago)"
    }

    private func setItems(_ newItems: [CleanableItem]) {
        items = newItems
        grouped = GroupedItems(items: newItems)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            idleState
        case .scanning:
            scanningState
        case .scanned, .cleaning:
            scannedState
        }
    }

    private var idleState: some View {
        EmptyStateView(
            icon: symbol,
            title: "Ready to scan \(title)",
            message: lastError ?? "Press Start Scan to look for items that match the rule set."
        ) {
            Button {
                scan()
            } label: {
                Label("Start Scan", systemImage: "magnifyingglass")
                    .frame(minWidth: 160)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var scanningState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Scanning…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Cancel", action: cancelScan)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scannedState: some View {
        VStack(spacing: 0) {
            heroZone
            Divider()
            if !items.isEmpty {
                HSplitView {
                    categoryListPane
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
                        .background(Color.secondary.opacity(0.04))
                    categoryDetailPane
                        .frame(minWidth: 360)
                }
                Divider()
            } else {
                emptyResults
                    .frame(maxHeight: .infinity)
            }
            if let pendingConfirm {
                confirmBar(pendingConfirm)
                Divider()
            }
            RunningDevToolsBanner(tools: detectedTools)
            CleanProgressFooter(tracker: progress)
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroZone: some View {
        // Compact one-line hero — left-aligned size + count, right-aligned
        // status messages. Vertical real estate is precious; the old
        // centred 40pt block ate ~120px and pushed the action bar off
        // screen on shorter displays.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if items.isEmpty && phase == .scanned {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
                Text("Nothing to clean").font(.title3.weight(.semibold))
            } else {
                Text(totalScannedSize.formattedBytes)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let lastResultMessage {
                Text(lastResultMessage).font(.caption).foregroundStyle(.green)
            }
            if let lastError {
                Text(lastError).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Master / detail

    private var categoryListPane: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(grouped.sortedCategories, id: \.self) { cat in
                    CategoryRow(
                        category: cat,
                        items: grouped.byCategory[cat] ?? [],
                        selectedIDs: selectedIDs,
                        isActive: selectedCategory == cat,
                        onTap: { selectedCategory = cat },
                        onToggle: { toggleCategory(cat) }
                    )
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var categoryDetailPane: some View {
        if let cat = selectedCategory, let categoryItems = grouped.byCategory[cat], !categoryItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cat.displayName).font(.title2.weight(.semibold))
                    Text(cat.rationale)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                HStack(spacing: 8) {
                    Text("\(categoryItems.count) item\(categoryItems.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $sortOrder) {
                        ForEach(SortField.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 140)
                    Button(allSelectedInCategory(cat) ? "Deselect" : "Select all") {
                        toggleCategory(cat)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                Divider()

                List {
                    ForEach(grouped.subgroupsByCategory[cat] ?? []) { group in
                        Section(header: subgroupHeader(group)) {
                            ForEach(sorted(group.items)) { item in
                                CleanupItemRow(
                                    item: item,
                                    isOn: Binding(
                                        get: { selectedIDs.contains(item.id) },
                                        set: { newValue in
                                            if newValue { selectedIDs.insert(item.id) }
                                            else { selectedIDs.remove(item.id) }
                                        }
                                    ),
                                    onReveal: { NSWorkspace.shared.activateFileViewerSelecting([item.url]) },
                                    accent: accent
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "sidebar.left")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Select a category on the left to see details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func subgroupHeader(_ group: CategorySubgroup) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { group.items.allSatisfy { selectedIDs.contains($0.id) } },
                set: { newValue in
                    if newValue { group.items.forEach { selectedIDs.insert($0.id) } }
                    else { group.items.forEach { selectedIDs.remove($0.id) } }
                }
            )).labelsHidden()
            Text(group.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(group.totalSize.formattedBytes)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyResults: some View {
        VStack {
            Spacer()
            Text("No items match this filter")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func confirmBar(_ confirm: PendingConfirm) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Delete \(confirm.items.count) item\(confirm.items.count == 1 ? "" : "s") (\(confirm.totalSize.formattedBytes))?")
                    .font(.callout.weight(.medium))
                Text("Cache items are removed directly. Other items move to a 7-day quarantine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { pendingConfirm = nil }
                .keyboardShortcut(.cancelAction)
            Button("Delete", role: .destructive) {
                performClean(confirm.items)
                pendingConfirm = nil
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Text("\(selectedIDs.count) of \(items.count) selected • \(selectedSize.formattedBytes)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Select All") {
                selectedIDs = Set(items.map(\.id))
            }
            .disabled(items.isEmpty || phase == .cleaning)
            .keyboardShortcut("a")

            Button("Deselect All") { selectedIDs.removeAll() }
                .disabled(selectedIDs.isEmpty)
                .keyboardShortcut("d")

            if phase == .cleaning {
                ProgressView().controlSize(.small)
            }

            Button {
                requestClean()
            } label: {
                Text("Clean \(selectedSize.formattedBytes)")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedIDs.isEmpty || phase == .cleaning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Derived state

    private var totalScannedSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    private var selectedSize: Int64 {
        items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private func sorted(_ slice: [CleanableItem]) -> [CleanableItem] {
        switch sortOrder {
        case .sizeDesc:     return slice.sorted { $0.size > $1.size }
        case .sizeAsc:      return slice.sorted { $0.size < $1.size }
        case .modifiedDesc: return slice.sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
        case .modifiedAsc:  return slice.sorted { ($0.lastModified ?? .distantPast) < ($1.lastModified ?? .distantPast) }
        case .name:         return slice.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private func toggleCategory(_ category: ItemCategory) {
        let ids = (grouped.byCategory[category] ?? []).map(\.id)
        if ids.allSatisfy({ selectedIDs.contains($0) }) {
            ids.forEach { selectedIDs.remove($0) }
        } else {
            ids.forEach { selectedIDs.insert($0) }
        }
    }

    private func allSelectedInCategory(_ category: ItemCategory) -> Bool {
        let ids = (grouped.byCategory[category] ?? []).map(\.id)
        return !ids.isEmpty && ids.allSatisfy { selectedIDs.contains($0) }
    }

    // MARK: - Actions

    private func scan() {
        Task { @MainActor in
            phase = .scanning
            setItems([])
            selectedIDs = []
            lastError = nil
            lastResultMessage = nil
            scanStartedAt = Date()
            do {
                let result = try await scanner.scan()
                setItems(result)
                detectedTools = LiveDevTools.detect()
                // Auto-select the biggest category so the detail pane
                // isn't empty on first reveal.
                selectedCategory = grouped.sortedCategories.first
                phase = .scanned
                container.cleanupResultsCache.set(scannerID: scanner.id, items: result)
                let totalSize = result.reduce(Int64(0)) { $0 + $1.size }
                Log.scanner.info("\(scanner.id, privacy: .public) scan: \(result.count) items, \(totalSize) bytes")
                try? await container.db.recordScan(
                    module: scanner.id,
                    startedAt: scanStartedAt ?? Date(),
                    finishedAt: Date(),
                    itemsScanned: result.count,
                    bytesTotal: totalSize,
                    sourcePath: nil,
                    status: "scanned"
                )
            } catch {
                lastError = error.localizedDescription
                phase = .idle
                Log.scanner.error("\(scanner.id, privacy: .public) scan failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func cancelScan() {
        phase = .idle
    }

    private func requestClean() {
        let toClean = items.filter { selectedIDs.contains($0.id) }
        guard !toClean.isEmpty else { return }
        pendingConfirm = PendingConfirm(items: toClean)
    }

    private func performClean(_ toClean: [CleanableItem]) {
        Task { @MainActor in
            phase = .cleaning
            detectedTools = LiveDevTools.detect()
            let startedAt = scanStartedAt ?? Date()
            progress.start(total: toClean.count)
            let result = await scanner.clean(toClean, onProgress: progress.makeHandler())
            progress.finish()
            let removedIDs = Set(result.removed.map { $0.id })
            setItems(items.filter { !removedIDs.contains($0.id) })
            selectedIDs.removeAll()
            phase = .scanned
            container.cleanupResultsCache.update(scannerID: scanner.id, items: items)
            let protected = result.failed.filter { $0.reason.hasPrefix("Refused:") }.count
            let errors = result.failed.count - protected
            lastResultMessage = QuickCleanView.formatResult(
                freed: result.bytesFreed,
                quarantined: result.bytesQuarantined,
                removed: result.removed.count,
                protected: protected,
                errors: errors
            )
            lastError = errors > 0 ? "\(errors) item\(errors == 1 ? "" : "s") couldn't be removed (likely permission)" : nil

            do {
                try await container.db.recordScan(
                    module: scanner.id,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    itemsScanned: result.removed.count,
                    bytesTotal: result.bytesProcessed,
                    sourcePath: nil,
                    status: result.failed.isEmpty ? "completed" : "partial"
                )
            } catch {
                Log.db.error("recordScan failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Sub-components

/// Precomputed grouping for the master/detail panes. Recomputed only
/// when the items array changes — avoids re-grouping per render.
struct GroupedItems {
    let byCategory: [ItemCategory: [CleanableItem]]
    /// Categories present in the current scan, ordered by total bytes
    /// descending — biggest space-eaters at the top of the master pane.
    let sortedCategories: [ItemCategory]
    let subgroupsByCategory: [ItemCategory: [CategorySubgroup]]

    static let empty = GroupedItems(byCategory: [:], sortedCategories: [], subgroupsByCategory: [:])

    init(items: [CleanableItem]) {
        let by = Dictionary(grouping: items) { $0.category }
        let sortedByBytes = by
            .map { (cat: $0.key, bytes: $0.value.reduce(Int64(0)) { $0 + $1.size }) }
            .sorted { $0.bytes > $1.bytes }
            .map(\.cat)
        let subgroups = by.mapValues { catItems in
            Dictionary(grouping: catItems) { $0.ruleID ?? "_other" }
                .map { CategorySubgroup(id: $0.key, items: $0.value) }
                .sorted { $0.totalSize > $1.totalSize }
        }
        self.byCategory = by
        self.sortedCategories = sortedByBytes
        self.subgroupsByCategory = subgroups
    }

    private init(byCategory: [ItemCategory: [CleanableItem]],
                 sortedCategories: [ItemCategory],
                 subgroupsByCategory: [ItemCategory: [CategorySubgroup]]) {
        self.byCategory = byCategory
        self.sortedCategories = sortedCategories
        self.subgroupsByCategory = subgroupsByCategory
    }
}

/// One entry of vector geometry inside a category — a rule's worth of
/// files, identified by `ruleID`. Pretty-printed name comes from the
/// ruleID slug.
struct CategorySubgroup: Identifiable {
    let id: String
    let items: [CleanableItem]
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var title: String {
        if id == "_other" { return "Other" }
        return id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// Master-pane row: category icon, name, "X of Y selected" badge, and a
/// total-size readout. Tapping anywhere on the row activates it; the
/// checkbox toggles every item in the category at once.
struct CategoryRow: View {
    let category: ItemCategory
    let items: [CleanableItem]
    let selectedIDs: Set<UUID>
    let isActive: Bool
    let onTap: () -> Void
    let onToggle: () -> Void

    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    private var selectedCount: Int { items.filter { selectedIDs.contains($0.id) }.count }
    private var allSelected: Bool {
        !items.isEmpty && selectedCount == items.count
    }
    private var partiallySelected: Bool {
        selectedCount > 0 && selectedCount < items.count
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { allSelected },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            // Visual cue for partial selection — SwiftUI Toggle has no
            // native indeterminate state on macOS, so we tint the
            // surrounding area.
            .background(partiallySelected ? Color.accentColor.opacity(0.18) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Image(systemName: category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(selectedCount > 0
                     ? "\(selectedCount) of \(items.count) selected"
                     : "\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(totalSize.formattedBytes)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct CleanupItemRow: View {
    let item: CleanableItem
    @Binding var isOn: Bool
    let onReveal: () -> Void
    var accent: Color = .accentColor

    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isOn).labelsHidden()
            Image(systemName: item.isDirectory ? "folder.fill" : item.category.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    SafetyBadge(level: item.safetyLevel)
                }
                Text(item.url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            InfoButton { showDetail = true }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("View details") { showDetail = true }
            Button("Reveal in Finder", action: onReveal)
        }
        .sheet(isPresented: $showDetail) {
            CleanableItemDetailSheet(item: item, accent: accent) { showDetail = false }
        }
    }
}

/// Read-only popup with everything we know about a CleanableItem —
/// full path, size, category rationale, safety reason, rule provenance,
/// last-modified timestamp. Copy / Reveal actions sticky at the bottom.
struct CleanableItemDetailSheet: View {
    let item: CleanableItem
    var accent: Color = .accentColor
    let onClose: () -> Void

    var body: some View {
        DetailSheet(
            title: item.title,
            subtitle: "\(item.category.displayName) · \(item.size.formattedBytes)",
            accent: accent,
            width: 560,
            height: 480,
            onClose: onClose
        ) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        detailRow("Path", value: item.url.path, mono: true)
                        detailRow("Size", value: item.size.formattedBytes, mono: true)
                        detailRow("Type", value: item.isDirectory ? "Folder" : "File")
                        detailRow("Category", value: item.category.displayName)
                        detailRow("Safety", value: item.safetyLevel.displayName)
                        if let modified = item.lastModified {
                            detailRow("Last modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let ruleID = item.ruleID {
                            detailRow("Source rule", value: ruleID, mono: true)
                        }
                        if !item.description.isEmpty {
                            Divider().padding(.vertical, 4)
                            Text("WHY THIS IS HERE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text(item.description)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !item.category.rationale.isEmpty {
                            Divider().padding(.vertical, 4)
                            Text("CATEGORY RATIONALE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text(item.category.rationale)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("Copy path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.url.path, forType: .string)
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SafetyBadge: View {
    let level: SafetyLevel

    var body: some View {
        Text(level.displayName)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch level {
        case .safe:      return .green
        case .review:    return .orange
        case .dangerous: return .red
        }
    }
}
