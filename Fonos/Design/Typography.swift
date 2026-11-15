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

    /// PostScript names of each variable font's default instance.
    static let textBase = "AtkinsonHyperlegibleNext-Regular"
    static let displayBase = "Sora-Regular"

    /// UIKit font with an explicit weight on the variable `wght` axis,
    /// scaled for Dynamic Type. Used for bars and segmented controls.
    static func uiFont(_ base: String, size: CGFloat, weight: CGFloat, style: UIFont.TextStyle, maxSize: CGFloat? = nil) -> UIFont {
        guard let regular = UIFont(name: base, size: size) else {
            return UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size))
        }
        let wghtTag = 0x7767_6874 // 'wght'
        let descriptor = regular.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtTag: weight],
        ])
        let font = UIFont(descriptor: descriptor, size: size)
        if let maxSize { return UIFontMetrics(forTextStyle: style).scaledFont(for: font, maximumPointSize: maxSize) }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    /// Navigation titles, tab labels, and segmented controls in the brand faces.
    static func applyAppearance() {
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: uiFont(displayBase, size: 32, weight: 700, style: .largeTitle)]
        nav.titleTextAttributes = [.font: uiFont(displayBase, size: 17, weight: 600, style: .headline)]
        UITabBarItem.appearance().setTitleTextAttributes(
            [.font: uiFont(textBase, size: 11, weight: 600, style: .caption2)], for: .normal)
        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([.font: uiFont(textBase, size: 14, weight: 500, style: .subheadline, maxSize: 20)], for: .normal)
        seg.setTitleTextAttributes([.font: uiFont(textBase, size: 14, weight: 700, style: .subheadline, maxSize: 20)], for: .selected)
        UIBarButtonItem.appearance().setTitleTextAttributes(
            [.font: uiFont(textBase, size: 17, weight: 600, style: .body)], for: .normal)
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
