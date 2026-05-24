import SwiftUI

struct ScrollDenoiserView: View {

    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ScrollDenoiserContent(controller: container.scrollDenoiser)
    }
}

private struct ScrollDenoiserContent: View {

    @ObservedObject var controller: ScrollDenoiserController

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(
                icon: "cursorarrow.click.2",
                title: "Scroll Denoiser",
                subtitle: "Filters reverse-tick noise from cheap mouse wheels",
                accent: .pink
            ) {
                statusBadge
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    enableCard
                    if let error = controller.lastError {
                        errorBanner(error)
                    }
                    settingsCard
                    statsCard
                    explainerCard
                }
                .padding(Spacing.lg)
            }
        }
        .refreshTask(every: 0.5) {
            controller.refreshStats()
        }
    }

    private var statusBadge: some View {
        Group {
            if !controller.isEnabled {
                StatusBadge(text: "OFF", color: .secondary)
            } else if controller.isRunning {
                StatusBadge(text: "RUNNING", color: .green)
            } else {
                StatusBadge(text: "PERMISSION", color: .orange)
            }
        }
    }

    private var enableCard: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable filter")
                    .font(.system(size: 14, weight: .medium))
                Text("Drops obvious reverse-direction ticks while you spin the wheel fast in one direction.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $controller.isEnabled).labelsHidden()
        }
        .padding(Spacing.md)
        .cardStyle(radius: Radius.lg, withShadow: false)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Settings") {
                PermissionsService.openSettings(for: .accessibility)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(Spacing.md)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeading("Tuning")

            tunableRow(
                title: "Slow-scroll lock",
                description: "Lock window when wheel is moving slowly. Lower = legitimate reverses pass quicker.",
                value: settingBinding(
                    get: \.minLockMs,
                    set: { $0.minLockMs = $1 }
                ),
                range: 0...100,
                step: 5,
                unit: "ms"
            )

            tunableRow(
                title: "Fast-scroll lock",
                description: "Lock window when wheel is moving fast (encoder most prone to aliasing). Higher = stronger filtering.",
                value: settingBinding(
                    get: \.maxLockMs,
                    set: { $0.maxLockMs = $1 }
                ),
                range: 30...300,
                step: 10,
                unit: "ms"
            )

            tunableRow(
                title: "Fast-scroll threshold",
                description: "Ticks per measurement window above which the wheel is treated as 'fast'.",
                value: settingBinding(
                    get: \.fastThreshold,
                    set: { $0.fastThreshold = $1 }
                ),
                range: 1...15,
                step: 1,
                unit: "ticks"
            )

            HStack {
                Spacer()
                Button("Reset to defaults") {
                    controller.settings = .default
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(Spacing.md)
        .cardStyle(radius: Radius.lg, withShadow: false)
    }

    /// Slider bindings must do a full struct write-back instead of mutating a
    /// nested field directly. `controller.settings.minLockMs = X` *should*
    /// fire the `@Published` setter + `didSet`, but Swift's modify-access path
    /// through a property wrapper can skip the user-defined `didSet`, leaving
    /// `filter.update(settings:)` unrun — the "have to click Reset to apply"
    /// bug. Building a fresh struct and assigning it whole guarantees the
    /// setter (and didSet) fires.
    private func settingBinding(
        get keyPath: KeyPath<DirectionLockSettings, Int>,
        set mutator: @escaping (inout DirectionLockSettings, Int) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { Double(controller.settings[keyPath: keyPath]) },
            set: { newValue in
                var updated = controller.settings
                mutator(&updated, Int(newValue))
                controller.settings = updated
            }
        )
    }

    private func tunableRow(
        title: String,
        description: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeading("Stats")
            HStack(spacing: Spacing.lg) {
                statBox(label: "Total ticks", value: "\(controller.totalTicks)")
                statBox(label: "Dropped", value: "\(controller.droppedTicks)")
                statBox(label: "Drop rate", value: dropRateText)
            }
            HStack {
                Spacer()
                Button("Reset stats") {
                    controller.resetCounters()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(Spacing.md)
        .cardStyle(radius: Radius.lg, withShadow: false)
    }

    private func statBox(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 18, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dropRateText: String {
        let total = controller.totalTicks
        guard total > 0 else { return "—" }
        let pct = Double(controller.droppedTicks) / Double(total) * 100
        return String(format: "%.1f%%", pct)
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading("How it works")
            Text("Cheap optical/mechanical wheel encoders can't keep up at high rotational speed and emit interleaved reverse ticks. The filter locks the dominant direction for a short window, drops the obvious noise, and releases on idle. Trackpad gestures and any continuous scroll are passed through untouched.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("If a single quick reverse flick gets eaten, lower the fast-scroll lock. If noise still gets through, raise it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .cardStyle(radius: Radius.lg, withShadow: false)
    }
}
