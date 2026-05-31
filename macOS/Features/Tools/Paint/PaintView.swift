import SwiftUI

@MainActor
struct PaintView: View {

    @StateObject private var state = PaintState()
    @State private var viewportSize: CGSize = .zero
    @State private var showingNewSheet = false
    @AppStorage(DefaultsKeys.paintPanelVisible) private var panelVisible: Bool = true

    private let palette: [Color] = [
        .black, .white, .gray,
        .red, .orange, .yellow,
        .green, .mint, .teal,
        .blue, .indigo, .purple,
        .pink, .brown
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                canvasArea
                if panelVisible {
                    Divider()
                    PaintPanelView(state: state)
                }
            }
        }
        .sheet(isPresented: $showingNewSheet) {
            NewDocumentSheet(
                initial: state.canvasSize,
                onCreate: { size, bgColor in
                    state.newDocument(size: size, background: bgColor)
                    showingNewSheet = false
                },
                onCancel: { showingNewSheet = false }
            )
        }
    }

    private var header: some View {
        ModuleHeader(
            icon: "paintbrush.pointed",
            title: "Paint",
            subtitle: "Quick sketches and image edits — no extra app needed",
            accent: .pink
        ) {
            zoomControls
            Button { showingNewSheet = true } label: {
                Label("New…", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            Button { state.open(viewport: viewportSize) } label: {
                Label("Open…", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)
            Button { state.save() } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            Button { state.saveAs() } label: {
                Label("Save As…", systemImage: "square.and.arrow.down.on.square")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            Button { state.undo() } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!state.canUndo)
            Button { state.redo() } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!state.canRedo)
            Button(role: .destructive) { state.clear() } label: {
                Label("Clear", systemImage: "trash")
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { panelVisible.toggle() }
            } label: {
                Image(systemName: panelVisible ? "sidebar.right" : "sidebar.right")
                    .symbolVariant(panelVisible ? .fill : .none)
            }
            .keyboardShortcut("\\", modifiers: [.command, .option])
            .help(panelVisible ? "Hide Layers / History panel" : "Show Layers / History panel")
        }
        .background(toolHotkeys)
    }

    /// Tool letter shortcuts in a hidden background. Letter mapping
    /// lives on `PaintTool.shortcutKey` so adding a tool only requires
    /// one edit there.
    private var toolHotkeys: some View {
        Group {
            ForEach(PaintTool.allCases) { tool in
                hiddenShortcut(KeyEquivalent(tool.shortcutKey)) { state.tool = tool }
            }
            hiddenShortcut("=", modifiers: .command) { state.zoomIn() }
            hiddenShortcut("-", modifiers: .command) { state.zoomOut() }
            hiddenShortcut("0", modifiers: .command) { state.zoomToActual() }
        }
    }

    private func hiddenShortcut(_ key: KeyEquivalent,
                                modifiers: EventModifiers = [],
                                action: @escaping () -> Void) -> some View {
        Button("", action: action)
            .keyboardShortcut(key, modifiers: modifiers)
            .opacity(0)
            .frame(width: 0, height: 0)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { state.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom out (⌘ + scroll)")
            .disabled(state.zoom <= PaintState.zoomRange.lowerBound + 0.001)

            Menu("\(Int(state.zoom * 100))%") {
                Button("Fit") { state.zoomToFit(viewport: viewportSize) }
                Button("Actual Size (100%)") { state.zoomToActual() }
                Divider()
                ForEach([0.25, 0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { z in
                    Button("\(Int(z * 100))%") { state.zoom = CGFloat(z) }
                }
            }
            .frame(width: 64)

            Button { state.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom in (⌘ + scroll)")
            .disabled(state.zoom >= PaintState.zoomRange.upperBound - 0.001)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeading("Tools")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 2), spacing: 6) {
                ForEach(PaintTool.allCases) { tool in
                    Button { state.tool = tool } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14))
                            .frame(width: 36, height: 32)
                            .background(state.tool == tool ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08))
                            .foregroundStyle(state.tool == tool ? Color.accentColor : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                }
            }

            if state.tool != .select && state.tool != .eyedropper && state.tool != .text {
                SectionHeading("Size")
                HStack(spacing: 6) {
                    Slider(value: $state.brushSize, in: 1...60, step: 1)
                    Text("\(Int(state.brushSize))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                }
            }

            if state.tool == .text {
                SectionHeading("Font Size")
                HStack(spacing: 6) {
                    Slider(value: $state.fontSize, in: 10...96, step: 1)
                    Text("\(Int(state.fontSize))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }
            }

            if state.tool.isShape && state.tool != .line && state.tool != .arrow {
                Toggle("Fill shape", isOn: $state.fillShapes)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if state.tool != .select && state.tool != .eyedropper && state.tool != .eraser {
                SectionHeading("Opacity")
                HStack(spacing: 6) {
                    Slider(value: $state.opacity, in: 0.05...1, step: 0.05)
                    Text("\(Int(state.opacity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            SectionHeading("Color")
            HStack(spacing: 6) {
                ColorPicker("Current", selection: $state.color, supportsOpacity: false)
                    .labelsHidden()
                HexColorField(color: $state.color)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 4), count: 5), spacing: 4) {
                ForEach(palette, id: \.self) { swatch in
                    Button { state.color = swatch } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(swatch)
                            .frame(width: 20, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if state.selectedObject != nil {
                Divider().padding(.vertical, 4)
                selectedPanel
            }

            Spacer()
        }
        .padding(Spacing.md)
        .frame(width: 180)
        .background(Color.secondary.opacity(0.04))
    }

    @ViewBuilder
    private var selectedPanel: some View {
        if let obj = state.selectedObject {
            SectionHeading("Selected")

            ColorPicker("Color", selection: Binding(
                get: { Color(nsColor: obj.color) },
                set: { newColor in
                    // Preserve the object's existing alpha when the user
                    // picks a new hue — opacity has its own slider below.
                    let alpha = obj.color.alphaComponent
                    state.updateSelected { $0.color = NSColor(newColor).withAlphaComponent(alpha) }
                }
            ), supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Slider(value: Binding(
                    get: { obj.color.alphaComponent },
                    set: { newAlpha in
                        state.updateSelected { $0.color = $0.color.withAlphaComponent(newAlpha) }
                    }
                ), in: 0.05...1, step: 0.05)
                Text("\(Int(obj.color.alphaComponent * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            // Stroke width applies to every kind except text (where it's
            // a no-op — text geometry has no "line width").
            if !obj.isText {
                HStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { obj.lineWidth },
                        set: { newWidth in
                            state.updateSelected { $0.lineWidth = newWidth }
                        }
                    ), in: 1...60, step: 1)
                    Text("\(Int(obj.lineWidth))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                }
            }

            if case .text(let origin, let content, let fontSize) = obj.kind {
                HStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { fontSize },
                        set: { newSize in
                            state.updateSelected { o in
                                o.kind = .text(origin: origin, content: content, fontSize: newSize)
                            }
                        }
                    ), in: 10...96, step: 1)
                    Text("\(Int(fontSize))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }
            }

            Button(role: .destructive) { state.deleteSelected() } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                PaintCanvasView(state: state)
                    .frame(
                        width: state.canvasSize.width * state.zoom,
                        height: state.canvasSize.height * state.zoom
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
                    .padding(Spacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear { viewportSize = geo.size }
            .onChange(of: geo.size) { new in viewportSize = new }
        }
    }
}

@MainActor
private struct NewDocumentSheet: View {

    let initial: CGSize
    let onCreate: (CGSize, Color?) -> Void
    let onCancel: () -> Void

    @State private var widthText: String = ""
    @State private var heightText: String = ""
    @State private var selectedPreset: Preset? = nil
    @State private var backgroundKind: Background = .transparent
    @State private var solidColor: Color = .white

    /// 4096 is the same ceiling `clampedSize` enforces — preview here so
    /// the field shows the user before they hit Create.
    private let maxDim: Int = 4096

    enum Background: String, CaseIterable, Identifiable {
        case transparent = "Transparent"
        case solid = "Solid color"
        var id: String { rawValue }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case hd720    = "HD 720 (1280×720)"
        case hd1080   = "Full HD (1920×1080)"
        case fourK    = "4K UHD (3840×2160)"
        case square1k = "Square (1024×1024)"
        case a4Print  = "A4 @150dpi (1240×1754)"
        var id: String { rawValue }
        var size: CGSize {
            switch self {
            case .hd720:    return CGSize(width: 1280, height: 720)
            case .hd1080:   return CGSize(width: 1920, height: 1080)
            case .fourK:    return CGSize(width: 3840, height: 2160)
            case .square1k: return CGSize(width: 1024, height: 1024)
            case .a4Print:  return CGSize(width: 1240, height: 1754)
            }
        }
    }

    var parsedSize: CGSize? {
        guard let w = Int(widthText), let h = Int(heightText), w > 0, h > 0 else { return nil }
        return CGSize(width: min(w, maxDim), height: min(h, maxDim))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("New Document")
                .font(.headline)

            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width").font(.caption).foregroundStyle(.secondary)
                    TextField("1024", text: $widthText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                Text("×").foregroundStyle(.secondary).padding(.top, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height").font(.caption).foregroundStyle(.secondary)
                    TextField("768", text: $heightText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                Text("px").foregroundStyle(.secondary).padding(.top, 14)
            }

            Picker("Preset", selection: $selectedPreset) {
                Text("Custom").tag(Preset?.none)
                ForEach(Preset.allCases) { p in
                    Text(p.rawValue).tag(Preset?.some(p))
                }
            }
            .onChange(of: selectedPreset) { new in
                if let p = new {
                    widthText = String(Int(p.size.width))
                    heightText = String(Int(p.size.height))
                }
            }

            HStack(spacing: Spacing.sm) {
                Picker("Background", selection: $backgroundKind) {
                    ForEach(Background.allCases) { Text($0.rawValue).tag($0) }
                }
                if backgroundKind == .solid {
                    ColorPicker("", selection: $solidColor, supportsOpacity: false)
                        .labelsHidden()
                }
            }

            // `parsedSize` already clamps to maxDim — show the warning
            // when the *raw input* exceeds it so the user knows the
            // clamp happened.
            if (Int(widthText) ?? 0) > maxDim || (Int(heightText) ?? 0) > maxDim {
                Text("Max \(maxDim)px per side — larger values will be clamped.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard let size = parsedSize else { return }
                    onCreate(size, backgroundKind == .solid ? solidColor : nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedSize == nil)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 380)
        .background(PopupBackground())
        .onAppear {
            widthText = String(Int(initial.width))
            heightText = String(Int(initial.height))
        }
    }
}
