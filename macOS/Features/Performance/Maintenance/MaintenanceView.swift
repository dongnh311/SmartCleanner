import SwiftUI
import AppKit

@MainActor
struct MaintenanceView: View {

    @State private var copiedID: String?
    @State private var runningIDs = Set<String>()
    @State private var results: [String: MaintenanceRunResult] = [:]

    private var grouped: [(MaintenanceCommand.Category, [MaintenanceCommand])] {
        let dict = Dictionary(grouping: MaintenanceCommand.all, by: { $0.category })
        return MaintenanceCommand.Category.allCases.compactMap { cat in
            dict[cat].map { (cat, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(grouped, id: \.0) { (cat, items) in
                        section(category: cat, items: items)
                    }
                    helperBanner
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        ModuleHeader(
            icon: "wrench.and.screwdriver",
            title: "Maintenance",
            subtitle: "Run system scripts in-app — admin items prompt for your macOS password",
            accent: .teal
        )
    }

    private func section(category: MaintenanceCommand.Category, items: [MaintenanceCommand]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.displayName.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(items) { cmd in
                    commandCard(cmd)
                }
            }
        }
    }

    private func commandCard(_ cmd: MaintenanceCommand) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(cmd.title).font(.system(size: 13, weight: .medium))
                if cmd.requiresAdmin {
                    Text("ADMIN")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                Spacer()
                Button("Copy") {
                    copy(cmd)
                }
                .controlSize(.small)
                Button("Open in Terminal") {
                    openInTerminal(cmd.command)
                }
                .controlSize(.small)
                if runningIDs.contains(cmd.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run") { runCommand(cmd) }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(cmd.summary).font(.caption).foregroundStyle(.secondary)
            Text(cmd.command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if copiedID == cmd.id {
                Text("Copied to clipboard").font(.caption2).foregroundStyle(.green)
            }
            if let result = results[cmd.id] {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                        .font(.caption)
                    Text(resultText(result))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .cardStyle(radius: 8, withShadow: false)
    }

    private var helperBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.blue)
            Text("Admin commands ask for your macOS password and run with administrator privileges via the system prompt. Nothing leaves your Mac. Prefer the terminal? Use Copy or Open in Terminal instead.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func runCommand(_ cmd: MaintenanceCommand) {
        runningIDs.insert(cmd.id)
        results[cmd.id] = nil
        Task { @MainActor in
            let result = await MaintenanceRunner.run(cmd)
            results[cmd.id] = result
            runningIDs.remove(cmd.id)
            Log.app.info("Maintenance '\(cmd.id, privacy: .public)' \(result.success ? "ok" : "failed", privacy: .public)")
        }
    }

    private func resultText(_ result: MaintenanceRunResult) -> String {
        if result.success {
            return result.output.isEmpty ? "Done." : "Done. \(result.output)"
        }
        return result.output.isEmpty ? "Failed." : result.output
    }

    private func copy(_ cmd: MaintenanceCommand) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(cmd.command, forType: .string)
        copiedID = cmd.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedID == cmd.id { copiedID = nil }
        }
    }

    private func openInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(escaped)\"\nactivate application \"Terminal\""
        guard let appleScript = NSAppleScript(source: script) else { return }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            Log.app.error("Open in Terminal failed: \(String(describing: error), privacy: .public)")
        }
    }
}
