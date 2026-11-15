import SwiftUI
import UIKit

/// Wren design tokens. The light palette comes from the Wren band itself:
/// the white shell, the grey-green liner, the black strap, the grey backdrop,
/// and the green, blue, and red sensor wires (web-safe values). Surfaces use
/// light tints of the backdrop grey. Dark mode draws from the same band: the
/// strap's black for surfaces, the shell's white for text, and the wire and
/// liner colors at their measured (lighter) values.
///
/// Accent colors on white sit near 3:1, which is fine for fills, rings, and
/// traces but not for small text, so each accent has a deeper `…Ink` shade of
/// the same hue for labels and links.
enum Theme {

    // MARK: Grounds

    /// App background. A light tint of the backdrop grey in light, slate in dark.
    static let ground = Color(light: 0xF2F2F2, dark: 0x0A0A0C)
    /// Card surface: the band's white shell.
    static let card = Color(light: 0xFFFFFF, dark: 0x18181B)
    /// Inset element inside a card or on the ground (tracks, wells, chips).
    static let well = Color(light: 0xEBEBEB, dark: 0x232326)
    /// The raised thumb of a segmented control, sitting in a well.
    static let thumb = Color(light: 0xFFFFFF, dark: 0x2E2E33)
    /// Hairline separators and chart rules (backdrop grey #CCCCCC, softened).
    static let hairline = Color(light: 0xD6D6D6, dark: 0x2C2C30)
    /// The 1 pt edge around every surface, so white reads against the ground.
    static let edge = Color(light: 0xE3E3E3, dark: 0x222226)
    /// Shadow tint (the strap's black), used at low opacity. Clear in dark,
    /// where surfaces separate by tone instead.
    static let shadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .clear : UIColor(hex: 0x000000)
    })

    // MARK: Text

    /// The strap's black.
    static let inkUI = UIColor.dynamic(light: 0x000000, dark: 0xF4F4F4)
    static let ink = Color(uiColor: inkUI)
    static let inkSecondary = Color(light: 0x4D4D4D, dark: 0xA6A6A6)
    static let inkTertiary = Color(light: 0x666666, dark: 0x8C8C8C)

    // MARK: Streams (fixed meaning app-wide)

    /// Contact microphone: the band's grey-green liner.
    /// unslop-ignore: sampled from the band, not the "tasteful default" sage.
    static let mic = Color(light: 0x999966, dark: 0x949F89)
    static let micInk = Color(light: 0x666633, dark: 0x949F89)
    /// Left piezo (patient's left side of the larynx): the green wire.
    static let left = Color(light: 0x339999, dark: 0x25BBB5)
    static let leftInk = Color(light: 0x006666, dark: 0x25BBB5)
    /// Right piezo: the blue wire.
    static let right = Color(light: 0x6699CC, dark: 0x78A7E1)
    static let rightInk = Color(light: 0x336699, dark: 0x78A7E1)

    // MARK: Metrics

    static let clarity = left
    static let strength = mic
    /// Pace: the strap's black, softened.
    static let pace = Color(light: 0x333333, dark: 0xCCCCCC)
    static let symmetry = right
    /// Steadiness: the red wire.
    static let steadiness = Color(light: 0xFF6666, dark: 0xFF686A)
    static let steadinessInk = Color(light: 0xCC3333, dark: 0xFF686A)
    /// Pauses: the grey-green clip.
    static let pauses = Color(light: 0x999999, dark: 0x999999)
    static let pausesInk = Color(light: 0x666666, dark: 0x999999)

    // MARK: State

    static let good = Color(light: 0x339999, dark: 0x25BBB5)
    static let goodInk = Color(light: 0x006666, dark: 0x25BBB5)
    static let caution = Color(light: 0x999966, dark: 0x949F89)
    static let cautionInk = Color(light: 0x666633, dark: 0x949F89)
    /// Listening: the red wire.
    static let alert = Color(light: 0xFF6666, dark: 0xFF686A)
    /// The red at a shade that carries white text.
    static let alertInk = Color(light: 0xCC3333, dark: 0xCC3333)

    /// Primary action (the Speak button): the green wire.
    static let action = left
    /// Links, toggles, and selected tabs, where the action color is text-sized.
    static let actionInk = leftInk
    static let onAction = Color(light: 0xFFFFFF, dark: 0x0A0A0C)

    // MARK: Geometry

    // One small radius scale, applied by role (not one big radius everywhere).
    /// Cards and grouped surfaces.
    static let cardRadius: CGFloat = 16
    /// Buttons, tiles, wells, inputs, banners.
    static let controlRadius: CGFloat = 12
    static let tileRadius: CGFloat = controlRadius
    /// Small labels and chips.
    static let chipRadius: CGFloat = 6

    // Spacing runs on a 4 pt scale: 4, 8, 12, 16, 20, 24, 32.
    static let gutter: CGFloat = 16
    static let stack: CGFloat = 12
}

// MARK: - Type (see Typography.swift)

extension View {
    /// Small tracked uppercase title used on cards and sections.
    func cardTitle(_ color: Color = Theme.inkSecondary) -> some View {
        self
            .font(.metric(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

// MARK: - Helpers

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: .dynamic(light: light, dark: dark))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}
