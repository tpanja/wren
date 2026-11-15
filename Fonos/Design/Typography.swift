import CoreText
import SwiftUI
import UIKit

/// Two bundled faces, both SIL Open Font License (see Resources/Fonts):
/// - Atkinson Hyperlegible Next, by the Braille Institute, for all reading
///   text. Built for low-vision legibility: distinct letterforms (Il1, O0)
///   matter when the patient reads back their own translated words.
/// - Sora, a wide geometric face, for numerals, titles, and tracked caps,
///   echoing the WHOOP references.
/// Every style scales with Dynamic Type through `relativeTo:`.
enum FonosType {
    static let text = "Atkinson Hyperlegible Next"
    static let display = "Sora"

    /// Registers the bundled fonts once at launch (no Info.plist edits needed).
    static func register() {
        for name in ["AtkinsonHyperlegibleNext", "Sora"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Default point size of each text style at the Large content size (HIG).
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }

    /// UIKit font with an explicit weight on the variable `wght` axis,
    /// scaled for Dynamic Type. Used for bars and segmented controls.
    static func uiFont(_ family: String, size: CGFloat, weight: CGFloat, style: UIFont.TextStyle) -> UIFont {
        let wghtTag = 0x7767_6874 // 'wght'
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtTag: weight],
        ])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }

    /// Navigation titles, tab labels, and segmented controls in the brand faces.
    static func applyAppearance() {
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: uiFont(display, size: 32, weight: 700, style: .largeTitle)]
        nav.titleTextAttributes = [.font: uiFont(display, size: 17, weight: 600, style: .headline)]
        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: uiFont(text, size: 11, weight: 600, style: .caption2)], for: .normal)
        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([.font: uiFont(text, size: 14, weight: 500, style: .subheadline)], for: .normal)
        seg.setTitleTextAttributes([.font: uiFont(text, size: 14, weight: 700, style: .subheadline)], for: .selected)
        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: uiFont(text, size: 17, weight: 600, style: .body)], for: .normal)
    }
}

extension Font {
    /// Reading and interface text: Atkinson Hyperlegible Next.
    static func ui(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let w = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(FonosType.text, size: FonosType.size(style), relativeTo: style).weight(w)
    }

    /// Numerals and display: Sora.
    static func metric(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .custom(FonosType.display, size: FonosType.size(style), relativeTo: style).weight(weight)
    }
}
