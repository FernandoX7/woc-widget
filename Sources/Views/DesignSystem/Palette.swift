import SwiftUI

// MARK: - Palette
//
// The single home for every color. Semantic text and chart-grid colors deliberately sit above the
// old ultra-faint values: these labels carry information, so they need to remain readable on the
// dark gradient instead of behaving like decoration. Increase Contrast gets a second, stronger
// tier through the helpers at the bottom of the type.

enum Palette {
    static let card        = Color.white.opacity(0.05)
    static let cardStroke  = Color.white.opacity(0.08)
    static let gold        = Color(red: 0.94, green: 0.76, blue: 0.40)
    static let green       = Color(red: 0.33, green: 0.86, blue: 0.49)
    static let red         = Color(red: 0.96, green: 0.42, blue: 0.42)
    static let cyan        = Color(red: 0.20, green: 0.90, blue: 0.95)
    static let violet      = Color(red: 0.60, green: 0.30, blue: 0.95)
    static let textPrimary = Color.white.opacity(0.97)
    static let textSecond  = Color.white.opacity(0.68)
    static let textTert    = Color.white.opacity(0.50)
    static let onAccent    = Color.white               // text/foreground on a saturated accent fill (price badge)

    /// Chart gridlines are intentionally separate from card borders. A border can be barely
    /// perceptible while a gridline still has to communicate scale.
    static let chartGrid = Color.white.opacity(0.13)

    // Previously inline `Color(red:…)` literals, now named.
    static let chartAnnotationBG = Color(red: 0.13, green: 0.14, blue: 0.21)   // tooltip background
    static let popoverBGTop      = Color(red: 0.05, green: 0.05, blue: 0.15)   // popover gradient top
    static let popoverBGBottom   = Color(red: 0.10, green: 0.00, blue: 0.15)   // popover gradient bottom

    // Accessibility-adaptive variants — used ONLY when the system asks for it, so the DEFAULT render
    // is untouched (guardrail 9). System `glassEffect()` adapts to these for free; hand-rolled
    // material does not, so these tokens close that gap explicitly:
    //   • `cardOpaque`/`pillOpaque` replace the translucent fills under Reduce Transparency (an
    //     opaque panel a touch lighter than the popover gradient, so cards stay legible without
    //     the desktop bleeding through).
    //   • `cardStrokeStrong` replaces the hairline `cardStroke` under Increase Contrast.
    static let cardOpaque       = Color(red: 0.14, green: 0.11, blue: 0.22)
    static let pillOpaque       = Color(red: 0.18, green: 0.15, blue: 0.26)
    static let cardStrokeStrong = Color.white.opacity(0.30)

    static func secondaryText(for contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? Color.white.opacity(0.90) : textSecond
    }

    static func tertiaryText(for contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? Color.white.opacity(0.78) : textTert
    }

    static func chartGrid(for contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? Color.white.opacity(0.34) : chartGrid
    }
}
