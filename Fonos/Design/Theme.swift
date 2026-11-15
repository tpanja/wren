import SwiftUI
import UIKit

/// Fonos design tokens. Dark slate is the primary appearance; every token
/// also carries a light variant so the app holds up when the user picks Light.
enum Theme {

    // MARK: Grounds

    /// App background. Near-black slate in dark, cool paper in light.
    static let ground = Color(light: 0xF2F3F5, dark: 0x0F1316)
    /// Card surface, one step up from the ground.
    static let card = Color(light: 0xFFFFFF, dark: 0x1A2025)
    /// Raised element inside a card (segmented tracks, inset wells, chips).
    static let well = Color(light: 0xE9ECEF, dark: 0x242B31)
    /// Hairline separators and ring tracks.
    static let hairline = Color(light: 0xD5DAE0, dark: 0x2E363D)

    // MARK: Text

    static let ink = Color(light: 0x0F1316, dark: 0xF1EFEA)
    static let inkSecondary = Color(light: 0x4F5A63, dark: 0xA3ACB4)
    static let inkTertiary = Color(light: 0x6B7680, dark: 0x7D8790)

    // MARK: Streams (sensor colors, used only for the sensors)

    /// Microphone.
    static let mic = Color(light: 0xB87700, dark: 0xF2B33D)
    /// Left accelerometer.
    static let left = Color(light: 0x0A8A7A, dark: 0x3CC8B4)
    /// Right accelerometer.
    static let right = Color(light: 0x5B48C9, dark: 0x8E7CF0)

    // MARK: Ring metrics

    static let tune = Color(light: 0x1F6FB2, dark: 0x5AA9E6)
    static let steady = Color(light: 0xB0456A, dark: 0xE77FA3)
    static let rangeHue = Color(light: 0x5C7A1E, dark: 0xA6CE5C)

    // MARK: States (never borrowed from metric or stream hues)

    static let good = Color(light: 0x1E8E4E, dark: 0x4CD787)
    static let caution = Color(light: 0xA36100, dark: 0xF5A524)
    static let recording = Color(light: 0xC0342B, dark: 0xFF6B5E)

    /// Primary action (the Sing button).
    static let action = Color(light: 0x0A8A7A, dark: 0x3CC8B4)
    static let onAction = Color(light: 0xFFFFFF, dark: 0x06201C)

    // MARK: Geometry

    static let cardRadius: CGFloat = 18
    static let gutter: CGFloat = 16
    static let stack: CGFloat = 12
}

// MARK: - Type (see Typography.swift)

extension View {
    /// Small tracked uppercase title used on cards, after the WHOOP references.
    func cardTitle(_ color: Color = Theme.ink) -> some View {
        self
            .font(.metric(.footnote, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.1)
            .foregroundStyle(color)
    }
}

// MARK: - Helpers

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
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
}
