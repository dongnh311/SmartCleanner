import SwiftUI
import AppKit

extension NSColor {
    /// Uppercase `RRGGBB` (no leading `#`), evaluated in sRGB. Falls back to
    /// "000000" when the colour can't be expressed in an RGB space.
    var hexRGB: String {
        guard let c = usingColorSpace(.sRGB) else { return "000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    /// Parses `#RRGGBB` / `RRGGBB`, plus the 3-digit `#RGB` shorthand.
    /// Returns nil on anything malformed so callers can reject bad input.
    convenience init?(hexRGB raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A `#RRGGBB` text field kept in two-way sync with a SwiftUI `Color`.
/// Edits commit on Return or when focus leaves; invalid input is rejected
/// and the field snaps back to the last valid colour.
struct HexColorField: View {
    @Binding var color: Color
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("#")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField("RRGGBB", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { isFocused in
                    if !isFocused { apply() }
                }
        }
        .onAppear { text = NSColor(color).hexRGB }
        .onChange(of: color) { newValue in
            // Reflect external changes (palette tap, eyedropper) but never
            // stomp on what the user is in the middle of typing.
            if !focused { text = NSColor(newValue).hexRGB }
        }
    }

    private func apply() {
        if let c = NSColor(hexRGB: text) {
            color = Color(nsColor: c)
            text = c.hexRGB          // normalise: uppercase, expand shorthand
        } else {
            text = NSColor(color).hexRGB   // reject: restore last valid
        }
    }
}
