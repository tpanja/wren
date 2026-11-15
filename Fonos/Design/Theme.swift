import SwiftUI
import UIKit

/// Fonos design tokens. Warm porcelain light is the primary appearance: white
/// surfaces lifted off a warm ground by a hairline edge and a soft, warm-tinted
/// shadow. Every token also carries a dark variant for users who pick Dark.
enum Theme {

    // MARK: Grounds

    /// App background. Warm porcelain in light, near-black slate in dark.
    static let ground = Color(light: 0xF5F3EF, dark: 0x0F1316)
    /// Top of the background wash; the ground brightens toward the top edge.
    static let groundHigh = Color(light: 0xFBFAF8, dark: 0x11161A)
    /// Card surface.
    static let card = Color(light: 0xFFFFFF, dark: 0x1A2025)
    /// Inset element inside a card or on the ground (tracks, wells, chips).
    static let well = Color(light: 0xEFECE6, dark: 0x242B31)
    /// The raised thumb of a segmented control, sitting in a well.
    static let thumb = Color(light: 0xFFFFFF, dark: 0x343C44)
    /// Hairline separators and chart rules.
    static let hairline = Color(light: 0xE4DFD7, dark: 0x2E363D)
    /// The 1 pt edge around every surface, so white reads against porcelain.
    static let edge = Color(light: 0xEAE6DF, dark: 0x232A30)
    /// Warm shadow tint, used at low opacity. Clear in dark, where surfaces
    /// separate by tone instead.
    static let shadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .clear : UIColor(hex: 0x3B2F1E)
    })

    // MARK: Text

    static let inkUI = UIColor.dynamic(light: 0x16191D, dark: 0xF1EFEA)
    static let ink = Color(uiColor: inkUI)
    static let inkSecondary = Color(light: 0x4C535A, dark: 0xA3ACB4)
    static let inkTertiary = Color(light: 0x676D74, dark: 0x7D8790)

    // MARK: Streams (fixed meaning app-wide)

    /// Contact microphone.
    static let mic = Color(light: 0xB0740A, dark: 0xF2B33D)
    /// Left piezo (patient's left side of the larynx). Fonos jade.
    static let left = Color(light: 0x0C7F70, dark: 0x3CC8B4)
    /// Right piezo.
    static let right = Color(light: 0x5A49C8, dark: 0x8E7CF0)

    // MARK: Metrics

    static let clarity = left
    static let strength = mic
    static let pace = Color(light: 0x1F6AAB, dark: 0x5AA9E6)
    static let symmetry = right
    static let steadiness = Color(light: 0xAD4368, dark: 0xE77FA3)
    static let pauses = Color(light: 0x5A781D, dark: 0xA6CE5C)

    // MARK: State

    static let good = Color(light: 0x1C8A4B, dark: 0x4CD787)
    static let caution = Color(light: 0xA05F00, dark: 0xF5A524)
    static let alert = Color(light: 0xC4372E, dark: 0xFF6B5E)

    /// Primary action (the Speak button). Fonos jade.
    static let action = left
    static let onAction = Color(light: 0xFFFFFF, dark: 0x06201C)

    // MARK: Geometry

    static let cardRadius: CGFloat = 22
    static let tileRadius: CGFloat = 18
    static let gutter: CGFloat = 16
    static let stack: CGFloat = 14
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
