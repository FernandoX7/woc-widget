import SwiftUI

// MARK: - Gradients
//
// The brand cyan→violet gradient (previously re-instantiated ~8×) plus the other named
// gradients. Two brand orientations exist in the original UI — keep both.

enum Gradients {
    static let brandColors = [Palette.cyan, Palette.violet]

    /// cyan→violet, leading→trailing (line strokes, badge label, SETTINGS title).
    static let brandHorizontal = LinearGradient(colors: brandColors, startPoint: .leading, endPoint: .trailing)
    /// cyan→violet, topLeading→bottomTrailing (realm title, badge dot).
    static let brandDiagonal = LinearGradient(colors: brandColors, startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Chart area fill (cyan→violet with the original fade opacities), top→bottom.
    static let chartArea = LinearGradient(
        colors: [Palette.cyan.opacity(Opacity.o34), Palette.violet.opacity(Opacity.o02)],
        startPoint: .top, endPoint: .bottom)

    /// Done button capsule stroke, leading→trailing.
    static let doneStroke = LinearGradient(
        colors: [Palette.cyan.opacity(Opacity.o55), Palette.violet.opacity(Opacity.o55)],
        startPoint: .leading, endPoint: .trailing)

    /// Popover background, top→bottom.
    static let popoverBG = LinearGradient(
        colors: [Palette.popoverBGTop, Palette.popoverBGBottom],
        startPoint: .top, endPoint: .bottom)

    /// Popover edge highlight, topLeading→bottomTrailing.
    static let popoverStroke = LinearGradient(
        colors: [.white.opacity(Opacity.o20), .clear],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Chart styling
enum ChartStyle {
    static let yPadding = 3                 // y-scale headroom below min / above max
    static let axisDesiredCount = 3
    static let hoverSymbolSize: CGFloat = 70
    static let isolatedSymbolSize: CGFloat = 24
    static let ruleDash: [CGFloat] = [3, 3]
    // Candle chart ($WOC). The wick is a thin `RuleMark` (LineWidth.w1); the body is a `BarMark`
    // sized to a fraction of its auto-inferred slot so candles stay proportional at any bar count.
    static let candleBodyRatio: CGFloat = 0.6        // body width ÷ bar slot
    static let candleHollowInnerRatio: CGFloat = 0.34 // inner cutout width ÷ bar slot
    static let candleHollowInsetFraction = 0.16       // leaves visible top/bottom caps on hollow bodies
    static let candleYInsetFraction = 0.08           // y-headroom = this × the (high−low) span
    /// When every visible candle is flat (high == low across all bars), the (high−low) span is 0
    /// and the y-domain would collapse to a degenerate zero-height scale — synthesize a span of
    /// this fraction of the price instead (only on the flat path; non-flat renders stay identical).
    static let candleFlatSpanFraction = 0.02
    static let minPlotPoints = 2                       // both charts: below this, show the placeholder
}
