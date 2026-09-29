import SwiftUI

/// Visual tokens from docs/DESIGN.md section 7. The panel is always dark.
enum Theme {
    static let background = Color(hex: 0x262624)
    static let raised = Color(hex: 0x30302E)
    static let toast = Color(hex: 0x3A3936)
    static let text = Color(hex: 0xFAF9F5)
    static let secondary = Color(hex: 0xC2C0B6)
    static let muted = Color(hex: 0x9C9A92)
    static let faint = Color(hex: 0x87867F)

    static let track = Color(hex: 0xFAF9F5).opacity(0.10)
    static let barFill = Color(hex: 0xFAF9F5)
    static let hairline = Color(hex: 0xFAF9F5).opacity(0.16)

    static let apple = Color(hex: 0xD97757)
    static let appleEmpty = Color(hex: 0xD97757).opacity(0.14)
    static let stem = Color(hex: 0x8A5A3A)
    static let leaf = Color(hex: 0x8FB07A)

    static let accent = Color(hex: 0xF0B38F)
    static let gold = Color(hex: 0xF2CD7E)

    static let panelWidth: CGFloat = 360
    /// The tallest the panel can get (Settings, or a row open with everything shown).
    static let panelHeight: CGFloat = 700
    /// Transparent room around the panel inside its window, for the shadow.
    static let windowMargin: CGFloat = 12
    static let cornerRadius: CGFloat = 12

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
