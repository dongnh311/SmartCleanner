import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Source of truth for the paint canvas. Owns a stack of layers (each
/// with its own bitmap + vector objects), a bounded snapshot-based
/// history of every action with labels for the history panel, and tool
/// configuration shared across layers.
@MainActor
final class PaintState: ObservableObject {

    @Published var tool: PaintTool = .pencil
    @Published var color: Color = .black
    @Published var brushSize: CGFloat = 6
    @Published var fillShapes: Bool = false
    @Published var fontSize: CGFloat = 24
    @Published var opacity: CGFloat = 1.0

    /// Bumped after every mutation so SwiftUI re-renders the canvas.
    @Published private(set) var version: Int = 0

    /// View-space zoom multiplier. The bitmap stays at native resolution;
    /// the NSView's frame is scaled by this factor and mouse coords are
    /// divided by it on the way in.
    @Published var zoom: CGFloat = 1.0
    static let zoomRange: ClosedRange<CGFloat> = 0.1...8.0

    func zoomIn() { zoom = nextZoom(above: zoom) }
    func zoomOut() { zoom = nextZoom(below: zoom) }
    func zoomToFit(viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        let z = min(viewport.width / canvasSize.width, viewport.height / canvasSize.height)
        zoom = min(max(z, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }
    func zoomToActual() { zoom = 1.0 }

    private let zoomStops: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]
    private func nextZoom(above z: CGFloat) -> CGFloat { zoomStops.first(where: { $0 > z + 0.001 }) ?? z }
    private func nextZoom(below z: CGFloat) -> CGFloat { zoomStops.reversed().first(where: { $0 < z - 0.001 }) ?? z }

    @Published private(set) var canvasSize: CGSize

    /// URL the document is associated with — set by `open()` or after a
    /// successful `saveAs()`. `save()` writes silently to this URL; if
    /// nil it falls back to `saveAs()` so a brand-new untitled doc still
    /// gets a save panel on first Cmd+S.
    private var currentURL: URL?

    // MARK: - Layers

    @Published private(set) var layers: [PaintLayer]
    @Published var activeLayerIndex: Int = 0
    @Published var selectedID: UUID?

    var activeLayer: PaintLayer { layers[activeLayerIndex] }

    /// Backward-compat accessor used by NSView mouse code and FloodFill.
    /// All raster operations target the active layer.
    var bitmap: NSBitmapImageRep { activeLayer.bitmap }

    // MARK: - History

    /// Labels parallel to `undoStack` — newest action last, displayed in
    /// the History tab. Empty when there's nothing to undo.
    @Published private(set) var historyLabels: [String] = []
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var redoLabels: [String] = []
    private let undoLimit = 30
    private let maxOpenDimension: CGFloat = 4096

    private struct Snapshot {
        struct LayerSnap {
            let id: UUID
            let revision: UInt64
            let name: String
            let isVisible: Bool
            let bitmapPNG: Data
            let objects: [PaintObject]
        }
        let layers: [LayerSnap]
        let activeLayerIndex: Int
    }

    init(size: CGSize = CGSize(width: 1024, height: 768)) {
        self.canvasSize = size
        self.layers = [PaintLayer(name: "Layer 1", size: size)]
    }

    var nsColor: NSColor { NSColor(color).withAlphaComponent(opacity) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Drawing context (targets active layer)

    func withGraphicsContext(_ block: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: activeLayer.bitmap)
        block()
        NSGraphicsContext.restoreGraphicsState()
        // No `version` bump here — this is the freehand-draw hot path
        // and the NSView already calls `needsDisplay = true` after each
        // segment. Bumping @Published version forces SwiftUI to re-eval
        // the whole PaintView body (sidebar + panel) on every mouse move.
        activeLayer.revision &+= 1
    }

    /// All vector objects across visible layers, in render order. Used
    /// for hit-testing where we don't care which layer owns the object.
    func allVisibleObjects() -> [PaintObject] {
        layers.flatMap { $0.isVisible ? $0.objects : [] }
    }

    // MARK: - History

    /// Push a labelled snapshot. The label is what the History tab will
    /// show — it should describe the action *about to happen*, since the
    /// snapshot is the state immediately before it.
    func pushUndo(_ label: String) {
        let snap = makeSnapshot()
        undoStack.append(snap)
        historyLabels.append(label)
        if undoStack.count > undoLimit {
            undoStack.removeFirst()
            historyLabels.removeFirst()
        }
        redoStack.removeAll()
        redoLabels.removeAll()
    }

    func undo() {
        guard let prev = undoStack.popLast(), let label = historyLabels.popLast() else { return }
        redoStack.append(makeSnapshot())
        redoLabels.append(label)
        apply(prev)
    }

    func redo() {
        guard let next = redoStack.popLast(), let label = redoLabels.popLast() else { return }
        undoStack.append(makeSnapshot())
        historyLabels.append(label)
        apply(next)
    }

    /// Revert to the state captured at `historyLabels[index]` (i.e. just
    /// before that action). Drops everything newer; the History tab
    /// implements "delete this entry" via this call.
    func revertToHistory(index: Int) {
        guard undoStack.indices.contains(index) else { return }
        // Move discarded entries onto the redo stack so the user can come
        // back if they change their mind.
        while undoStack.count > index + 1 {
            redoStack.append(undoStack.removeLast())
            redoLabels.append(historyLabels.removeLast())
        }
        guard let snap = undoStack.popLast(), let lbl = historyLabels.popLast() else { return }
        redoStack.append(makeSnapshot())
        redoLabels.append(lbl)
        apply(snap)
    }

    func clear() {
        pushUndo("Clear")
        for layer in layers {
            layer.objects.removeAll()
            if let data = layer.bitmap.bitmapData {
                memset(data, 0, layer.bitmap.bytesPerRow * layer.bitmap.pixelsHigh)
            }
            layer.revision &+= 1
        }
        selectedID = nil
        version &+= 1
    }

    // MARK: - Layer management

    func addLayer() {
        pushUndo("Add Layer")
        let new = PaintLayer(name: "Layer \(layers.count + 1)", size: canvasSize)
        layers.append(new)
        activeLayerIndex = layers.count - 1
        version &+= 1
    }

    func deleteLayer(id: UUID) {
        guard layers.count > 1, let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo("Delete Layer")
        layers.remove(at: idx)
        if activeLayerIndex >= layers.count { activeLayerIndex = layers.count - 1 }
        // Drop any selection that lived on the removed layer.
        if let sid = selectedID, !layers.contains(where: { $0.objects.contains(where: { $0.id == sid }) }) {
            selectedID = nil
        }
        version &+= 1
    }

    func toggleLayerVisibility(id: UUID) {
        guard let idx = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[idx].isVisible.toggle()
        version &+= 1
    }

    func setActive(layerID: UUID) {
        guard let idx = layers.firstIndex(where: { $0.id == layerID }) else { return }
        activeLayerIndex = idx
    }

    // MARK: - Vector object operations (search all layers)

    func addObject(_ obj: PaintObject) {
        pushUndo(actionLabel(forNewObject: obj))
        activeLayer.objects.append(obj)
        activeLayer.revision &+= 1
        selectedID = obj.id
        version &+= 1
    }

    private func actionLabel(forNewObject obj: PaintObject) -> String {
        switch obj.kind {
        case .text:    return "Add Text"
        case .arrow:   return "Add Arrow"
        case .line:    return "Add Line"
        case .rect:    return "Add Rectangle"
        case .ellipse: return "Add Ellipse"
        }
    }

    func selectObject(at point: CGPoint) {
        // Top-most visible layer first, then top-most object within it.
        for layer in layers.reversed() where layer.isVisible {
            if let hit = layer.objects.reversed().first(where: { $0.contains(point: point) }) {
                selectedID = hit.id
                return
            }
        }
        selectedID = nil
    }

    var selectedObject: PaintObject? {
        guard let id = selectedID else { return nil }
        for layer in layers {
            if let obj = layer.objects.first(where: { $0.id == id }) { return obj }
        }
        return nil
    }

    private func locateSelected() -> (PaintLayer, Int)? {
        guard let id = selectedID else { return nil }
        for layer in layers {
            if let idx = layer.objects.firstIndex(where: { $0.id == id }) {
                return (layer, idx)
            }
        }
        return nil
    }

    func moveSelected(by delta: CGSize) {
        guard let (layer, idx) = locateSelected() else { return }
        layer.objects[idx].translate(by: delta)
        layer.revision &+= 1
        // No `version` bump — same reason as `withGraphicsContext`. The
        // canvas redraws via `needsDisplay`; no sidebar field reflects
        // object position.
    }

    func deleteSelected() {
        guard let (layer, idx) = locateSelected() else { return }
        pushUndo("Delete Object")
        layer.objects.remove(at: idx)
        layer.revision &+= 1
        selectedID = nil
        version &+= 1
    }

    func updateSelected(_ mutate: (inout PaintObject) -> Void) {
        guard let (layer, idx) = locateSelected() else { return }
        pushUndo("Edit Object")
        mutate(&layer.objects[idx])
        layer.revision &+= 1
        version &+= 1
    }

    /// Called from `PaintCanvasNSView` during a handle drag — applies
    /// the handle update without pushing undo (the drag's mouseDown
    /// already pushed a snapshot). Keeps the `version` bump because
    /// text resize changes the font-size slider value in the sidebar.
    func applyHandleToSelected(_ handle: PaintObject.Handle, world worldPoint: CGPoint, anchor: PaintObject) {
        guard let (layer, idx) = locateSelected() else { return }
        layer.objects[idx].applyHandle(handle, world: worldPoint, anchor: anchor)
        layer.revision &+= 1
        version &+= 1
    }

    func pickColor(at point: CGPoint) {
        // Sample the active layer for now — composite sampling can come
        // later if it matters in practice.
        let bm = activeLayer.bitmap
        let x = Int(point.x.rounded()), y = Int(point.y.rounded())
        guard x >= 0, y >= 0, x < bm.pixelsWide, y < bm.pixelsHigh else { return }
        guard let picked = bm.colorAt(x: x, y: bm.pixelsHigh - 1 - y) else { return }
        color = Color(nsColor: picked)
    }

    // MARK: - Snapshot apply

    private func makeSnapshot() -> Snapshot {
        // Reuse the previous snapshot's encoded bytes for any layer whose
        // revision hasn't changed. PNG encoding a 4096² bitmap is in the
        // tens of milliseconds; without this dedup, every stroke pays
        // the cost on every untouched layer too.
        let last = undoStack.last
        let snaps: [Snapshot.LayerSnap] = layers.map { l in
            if let prev = last?.layers.first(where: { $0.id == l.id }), prev.revision == l.revision {
                return Snapshot.LayerSnap(
                    id: l.id, revision: l.revision,
                    name: l.name, isVisible: l.isVisible,
                    bitmapPNG: prev.bitmapPNG,
                    objects: l.objects
                )
            }
            return Snapshot.LayerSnap(
                id: l.id, revision: l.revision,
                name: l.name, isVisible: l.isVisible,
                bitmapPNG: l.bitmap.representation(using: .png, properties: [:]) ?? Data(),
                objects: l.objects
            )
        }
        return Snapshot(layers: snaps, activeLayerIndex: activeLayerIndex)
    }

    private func apply(_ snap: Snapshot) {
        // Preserve the original layer id + revision so subsequent
        // `makeSnapshot` calls can still dedup unchanged layers against
        // the restored state.
        let rebuilt: [PaintLayer] = snap.layers.map { ls in
            let layer = PaintLayer(id: ls.id, name: ls.name, size: canvasSize)
            layer.isVisible = ls.isVisible
            layer.objects = ls.objects
            layer.revision = ls.revision
            if let img = NSImage(data: ls.bitmapPNG) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer.bitmap)
                img.draw(in: NSRect(origin: .zero, size: canvasSize))
                NSGraphicsContext.restoreGraphicsState()
            }
            return layer
        }
        layers = rebuilt
        activeLayerIndex = min(snap.activeLayerIndex, max(0, layers.count - 1))
        selectedID = nil
        version &+= 1
    }

    // MARK: - File I/O

    func save() {
        guard let url = currentURL else { saveAs(); return }
        writeFlattened(to: url)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = currentURL?.lastPathComponent ?? "Untitled.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeFlattened(to: url)
        currentURL = url
    }

    private func writeFlattened(to url: URL) {
        let ext = url.pathExtension.lowercased()
        let type: NSBitmapImageRep.FileType = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
        guard let data = flattenedBitmap().representation(using: type, properties: [:]) else { return }
        // Atomic write — avoids a half-written file if the process dies
        // mid-encode (otherwise the user's previous save would be
        // truncated on disk).
        try? data.write(to: url, options: .atomic)
    }

    /// Composite every visible layer (bitmap + vectors) into a single
    /// fresh bitmap for export.
    private func flattenedBitmap() -> NSBitmapImageRep {
        let out = PaintLayer.makeClearedBitmap(size: canvasSize)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        for layer in layers where layer.isVisible {
            layer.bitmap.draw(in: NSRect(origin: .zero, size: canvasSize))
            for obj in layer.objects { obj.draw() }
        }
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    /// `viewport` is the visible canvas area; the freshly opened image is
    /// zoomed to fit it (matching the "Fit" command) so the whole picture is
    /// on screen by default. Pass `.zero` to keep the current zoom.
    func open(viewport: CGSize = .zero) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
        let target = clampedSize(img.size)
        resetDocument(to: target)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: activeLayer.bitmap)
        img.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        currentURL = url
        version &+= 1
        zoomToFit(viewport: viewport)
    }

    /// `background == nil` keeps the canvas transparent (checker pattern
    /// shows through); a non-nil colour is painted across Layer 1 so the
    /// document starts with a solid fill.
    func newDocument(size: CGSize, background: Color? = nil) {
        resetDocument(to: clampedSize(size))
        guard let fill = background else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: activeLayer.bitmap)
        NSColor(fill).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        NSGraphicsContext.restoreGraphicsState()
        activeLayer.revision &+= 1
        version &+= 1
    }

    private func resetDocument(to size: CGSize) {
        canvasSize = size
        layers = [PaintLayer(name: "Layer 1", size: size)]
        activeLayerIndex = 0
        selectedID = nil
        currentURL = nil
        undoStack.removeAll()
        redoStack.removeAll()
        historyLabels.removeAll()
        redoLabels.removeAll()
        version &+= 1
    }

    private func clampedSize(_ size: CGSize) -> CGSize {
        let maxDim = max(size.width, size.height)
        guard maxDim > maxOpenDimension else { return size }
        let scale = maxOpenDimension / maxDim
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
