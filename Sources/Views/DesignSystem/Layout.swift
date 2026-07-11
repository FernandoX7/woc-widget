import SwiftUI

// MARK: - Layout tokens
//
// Numeric ladders for spacing/padding, corner radii, line widths, tracking, shadows, opacities,
// fixed frame sizes, and motion. Value-suffixed names map 1:1 to the original literals
// (guardrail 9). The popover sizes are FIXED constants — never measured/animated (guardrail 3).

/// Spacing and padding (they share the same CGFloat ladder in this UI).
enum Space {
    static let s0: CGFloat = 0
    static let s1: CGFloat = 1
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s5: CGFloat = 5
    static let s6: CGFloat = 6
    static let s7: CGFloat = 7
    static let s8: CGFloat = 8
    static let s9: CGFloat = 9
    static let s10: CGFloat = 10
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
}

enum Radius {
    static let r7: CGFloat = 7
    static let r8: CGFloat = 8
    static let r14: CGFloat = 14
}

enum LineWidth {
    static let w075: CGFloat = 0.75
    static let w1: CGFloat = 1
    static let w2: CGFloat = 2
    static let w6: CGFloat = 6
}

enum Tracking {
    static let t06: CGFloat = 0.6
    static let t08: CGFloat = 0.8
    static let t16: CGFloat = 1.6
    static let t18: CGFloat = 1.8
}

/// Opacity scalars used by `.opacity(_:)` / `Color.opacity(_:)` at call sites. (0 and 1 are
/// left inline as "none"/"full".)
enum Opacity {
    static let o02 = 0.02
    static let o04 = 0.04
    static let o08 = 0.08
    static let o12 = 0.12
    static let o13 = 0.13
    static let o15 = 0.15
    static let o20 = 0.2
    static let o25 = 0.25
    static let o30 = 0.3
    static let o34 = 0.34
    static let o35 = 0.35
    static let o40 = 0.4
    static let o45 = 0.45
    static let o55 = 0.55
    static let o80 = 0.8
    static let o85 = 0.85
    static let o90 = 0.9
    static let o92 = 0.92
}

enum Shadow {
    static let dotRadius: CGFloat = 3.5         // StatusDot glow
    static let badgeDotRadius: CGFloat = 4      // header badge dot glow
    static let annotationRadius: CGFloat = 5    // chart tooltip
    static let annotationOffsetY: CGFloat = 2
}

/// Fixed frame dimensions. Popover sizes are guardrail-3 constants.
enum Size {
    static let popoverDashboardWidth: CGFloat = 440
    static let popoverHeight: CGFloat = 660

    static let chartHeight: CGFloat = 104
    static let dividerWidth: CGFloat = 1
    static let dividerHeight: CGFloat = 22
    static let pickerLabelWidth: CGFloat = 48
    static let accessibilityPickerLabelWidth: CGFloat = 72
    static let progressSide: CGFloat = 12
    static let progressScale: CGFloat = 0.7
    static let iconButtonSide: CGFloat = 28
    static let leaderboardRankWidth: CGFloat = 22
    static let settingsControlWidth: CGFloat = 104
    static let onlineBaselineOffset: CGFloat = -4   // "online" label baseline nudge
}

/// Chart line glow.
enum Blur {
    static let glow: CGFloat = 6
}

/// Value-driven animation curves (never `repeatForever`/always-on — guardrail 1).
enum Motion {
    static let hover: Animation = .easeOut(duration: 0.15)
    static let settings: Animation = .smooth(duration: 0.3)
    static let count: Animation = .snappy
}
