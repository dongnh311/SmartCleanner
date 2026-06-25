import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gear") }
            MenuBarSettings()
                .tabItem { Label("Menu Bar", systemImage: "menubar.dock.rectangle") }
            AlertsSettings()
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
            QuarantineSettings()
                .tabItem { Label("Quarantine", systemImage: "tray.full") }
            ProtectionSettings(realtime: container.realtimeProtection)
                .tabItem { Label("Protection", systemImage: "lock.shield") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 420)
    }
}

private struct AlertsSettings: View {

    @ObservedObject private var engine = AlertEngine.shared
    @State private var masterEnabled: Bool = AlertEngine.shared.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Enable system alerts", isOn: $masterEnabled)
                    .onChange(of: masterEnabled) { newValue in
                        engine.isEnabled = newValue
                        if newValue {
                            Task { await engine.requestAuthorizationIfNeeded() }
                        }
                    }
                if masterEnabled && !engine.hasNotificationAuthorization {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications permission needed")
                                .font(.system(size: 12, weight: .medium))
                            Text("Open System Settings → Notifications → MacCleaner to allow alerts.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } header: {
                Text("Master switch")
            } footer: {
                Text("Each rule has its own cooldown so you won't get spammed if a metric stays elevated.")
                    .font(.caption2)
            }

            Section {
                ForEach(AlertCatalog.builtins) { rule in
                    Toggle(isOn: Binding(
                        get: { engine.isRuleEnabled(rule.id) },
                        set: { engine.setRule(rule.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rule.title).font(.system(size: 13))
                            Text(rule.detail).font(.caption2).foregroundStyle(.secondary)
                            if let last = engine.lastFiredAt[rule.id] {
                                Text("Last fired: \(last.formatted(.relative(presentation: .named)))")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(!masterEnabled)
                }
            } header: {
                Text("Built-in rules")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct MenuBarSettings: View {

    @ObservedObject private var config = MenuBarConfig.shared

    var body: some View {
        Form {
            Section {
                Picker("Display", selection: $config.displayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Picker("Separator", selection: $config.separator) {
                    ForEach(MenuBarSeparator.allCases) { sep in
                        Text(sep.displayName).tag(sep)
                    }
                }
                .pickerStyle(.menu)
                Picker("Label style", selection: $config.labelStyle) {
                    ForEach(MenuBarLabelStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                Text("Hidden removes the menu-bar item entirely. Open the main window or relaunch the app to bring it back.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Menu bar visibility")
            }

            Section {
                Text("Pick which metrics show next to the icon. Drag to reorder.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(MenuBarMetric.allCases) { metric in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { config.isEnabled(metric) },
                            set: { _ in config.toggle(metric) }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(metric.displayName).font(.system(size: 13))
                                Text(metric.hint).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if config.isEnabled(metric) {
                            Button {
                                config.move(metric, by: -1)
                            } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .help("Move left")
                            Button {
                                config.move(metric, by: +1)
                            } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .help("Move right")
                        }
                    }
                }
            } header: {
                Text("Menu bar metrics")
            }

            Section {
                if config.enabledMetrics.isEmpty {
                    Text("No metrics enabled — only the ✦ glyph will show.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(config.enabledMetrics.map(\.labelPrefix).joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Order preview")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct GeneralSettings: View {
    @AppStorage("appearance.preference") private var appearance: String = "system"
    @AppStorage("startup.runSmartCare") private var runSmartCareOnLaunch: Bool = false
    @AppStorage("language.preference") private var language: String = "system"
    @State private var launchAtLogin = false
    @State private var launchNeedsApproval = false

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("Match System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Open MacCleaner at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                        // Re-sync from the OS — it may reject the change or
                        // park it in "requires approval".
                        launchAtLogin = LaunchAtLogin.isEnabled
                        launchNeedsApproval = LaunchAtLogin.needsApproval
                    }
                if launchNeedsApproval {
                    Text("Approve MacCleaner under System Settings › General › Login Items to finish enabling this.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Toggle("Run Smart Care at launch", isOn: $runSmartCareOnLaunch)
            } header: {
                Text("Appearance & startup")
            }

            Section {
                Picker("Language", selection: $language) {
                    Text("Match System").tag("system")
                    Text("English").tag("en")
                    Text("Tiếng Việt").tag("vi")
                }
                .onChange(of: language) { newValue in
                    applyLanguage(newValue)
                }
                Text("Restart MacCleaner for the change to apply across every screen.")
                    .font(.caption2).foregroundStyle(.secondary)
            } header: {
                Text("Language")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            launchNeedsApproval = LaunchAtLogin.needsApproval
        }
    }

    /// AppleLanguages drives every Foundation/SwiftUI localization lookup.
    /// Setting it persists across launches; "system" clears the override
    /// so macOS falls back to the user's system preference order.
    private func applyLanguage(_ tag: String) {
        if tag == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([tag], forKey: "AppleLanguages")
        }
    }
}

private struct QuarantineSettings: View {
    @EnvironmentObject private var container: AppContainer

    @State private var sessions: [(URL, Date, Int64)] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quarantine")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Reveal Folder") {
                    let url = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".MacCleanerQuarantine")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Refresh") { Task { await reload() } }
            }
            Text("Items move to ~/.MacCleanerQuarantine/<timestamp>/ and are auto-purged after \(QuarantineService.retentionDays) days.")
                .font(.caption).foregroundStyle(.secondary)

            if sessions.isEmpty {
                Text(loading ? "Loading…" : "No quarantine sessions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(sessions.enumerated()), id: \.offset) { (_, row) in
                        HStack {
                            Text(row.0.lastPathComponent)
                                .font(.system(size: 12, design: .monospaced))
                            Spacer()
                            Text(row.1.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(row.2.formattedBytes)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                    }
                }
                .listStyle(.bordered)
                .frame(maxHeight: .infinity)
            }
        }
        .padding()
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".MacCleanerQuarantine")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            sessions = []
            return
        }
        let prepared: [(URL, Date, Int64)] = await withTaskGroup(of: (URL, Date, Int64).self) { group in
            for url in entries {
                group.addTask {
                    let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    let date = v?.contentModificationDate ?? .distantPast
                    let size = await Task.detached(priority: .background) {
                        FileSizeCalculator.walk(directory: url).total
                    }.value
                    return (url, date, size)
                }
            }
            var rows: [(URL, Date, Int64)] = []
            for await row in group { rows.append(row) }
            return rows
        }
        sessions = prepared.sorted { $0.1 > $1.1 }
    }
}

private struct RealtimeEnginesSettings: View {

    @ObservedObject var realtime: RealtimeProtectionService

    @State private var vtEnabled = VirusTotalClient.isEnabled
    @State private var vtKey = VirusTotalClient.apiKey
    @State private var feedURL = MalwareFeedUpdater.feedURL
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Section {
            Toggle("VirusTotal lookups for downloads", isOn: $vtEnabled)
                .onChange(of: vtEnabled) { newValue in VirusTotalClient.isEnabled = newValue }
            SecureField("VirusTotal API key", text: $vtKey)
                .onChange(of: vtKey) { newValue in VirusTotalClient.apiKey = newValue }
            HStack {
                Button("Test key") { Task { await testKey() } }
                    .disabled(busy || vtKey.isEmpty)
                Spacer()
                Link("Get a free key", destination: URL(string: "https://www.virustotal.com/gui/join-us")!)
                    .font(.caption)
            }
            Text("Sends only a file's SHA-256 (never the file) to VirusTotal, and only for internet-downloaded files. A free key allows ~4 lookups/min.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            TextField("Blocklist feed URL (one SHA-256 per line)", text: $feedURL)
                .onChange(of: feedURL) { newValue in MalwareFeedUpdater.feedURL = newValue }
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Update now") { Task { await update() } }
                    .disabled(busy || feedURL.isEmpty)
                Spacer()
                Text("\(realtime.signatureCount) signatures")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let last = MalwareFeedUpdater.lastUpdated {
                Text("Feed updated \(last.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Realtime detection engines")
        }
    }

    private func testKey() async {
        busy = true; status = "Testing…"
        let ok = await realtime.validateVirusTotalKey()
        status = ok ? "✓ VirusTotal key works." : "✗ Key rejected — check it and try again."
        busy = false
    }

    private func update() async {
        busy = true; status = "Downloading feed…"
        switch await realtime.updateFeed() {
        case .success(let s): status = "✓ Added \(s.added) new hashes (\(s.total) total)."
        case .failure(let e): status = "✗ Update failed: \(Self.describe(e))."
        }
        busy = false
    }

    private static func describe(_ e: MalwareFeedUpdater.UpdateError) -> String {
        switch e {
        case .noURL: return "no URL set"
        case .badURL: return "invalid URL"
        case .http(let c): return "HTTP \(c)"
        case .empty: return "no hashes found"
        case .network: return "network error"
        }
    }
}

private struct ProtectionSettings: View {

    @ObservedObject private var config = ProtectionConfig.shared
    let realtime: RealtimeProtectionService

    var body: some View {
        Form {
            RealtimeEnginesSettings(realtime: realtime)

            Section {
                Text("These dev tools are always protected while running — caches and tied paths are skipped automatically so a Clean can't crash the IDE or kill an emulator. Hardcoded for safety; can't be disabled.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(LiveDevTools.builtIns) { tool in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: tool.symbol)
                            .foregroundStyle(.green)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.name).font(.system(size: 13, weight: .medium))
                            Text(tool.hints.joined(separator: ", "))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text("Always on")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
            } header: {
                Text("Built-in protections")
            }

            Section {
                Text("Pick apps whose ~/Library data should never be cleaned. Same effect as the built-in Android Studio / Xcode rules, but you choose the apps.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if config.customApps.isEmpty {
                    Text("No apps added yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(config.customApps) { app in
                        HStack(spacing: 8) {
                            Image(systemName: "app.badge.shield.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.system(size: 13))
                                Text(app.bundleID)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                config.removeApp(app.bundleID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop protecting this app")
                        }
                    }
                }

                HStack {
                    Button("Add app…") { pickApp() }
                    Spacer()
                }
            } header: {
                Text("Protected apps")
            }

            Section {
                Text("Folders / files listed here are skipped by every cleanup module — useful for documents, vault folders, or any custom dir outside the standard app locations.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if config.customPaths.isEmpty {
                    Text("No custom paths yet — built-in protections are always on.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(config.customPaths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.green)
                            Text(path)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                config.removePath(path)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop protecting this path")
                        }
                    }
                }

                HStack {
                    Button("Add folder…") { pickFolder() }
                    Button("Add file…") { pickFile() }
                    Spacer()
                }
            } header: {
                Text("Protected paths")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an app whose caches and preferences should never be touched."
        if panel.runModal() == .OK, let url = panel.url {
            config.addApp(at: url)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            config.addPath(url.path)
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url {
            config.addPath(url.path)
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Text("MacCleaner")
                .font(.title.weight(.semibold))
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") • build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Personal macOS cleaner — feature-parity with CMM 5")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
