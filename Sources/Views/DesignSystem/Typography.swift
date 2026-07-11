import SwiftUI

// MARK: - Typography
//
// Every typography role used in the UI, named once. Near-identical-but-distinct specs are kept as
// separate tokens (for example, `emphasis` size-13 BOLD vs `online` size-13 MEDIUM). The base
// sizes remain the exact values the original fixed-size UI used. At the system's default Dynamic
// Type size, rendering is therefore pixel-equivalent to the previous `Font.system(size:)` tokens.
//
// Text roles scale through the public `@ScaledMetric` API. Each role is tied to the nearest
// semantic text style so large display values scale more gently than captions at accessibility
// sizes. The popover itself deliberately remains fixed; its page bodies and Settings are scrollable,
// so larger content reflows vertically without changing the MenuBarExtra window geometry.
//
// SF-symbol-only roles stay fixed. Scaling those symbols would reduce the usable plot area and
// overflow the deliberately compact 28-point controls without making any text more readable.

enum Typo {
    struct Role {
        fileprivate let size: CGFloat
        fileprivate let weight: Font.Weight
        fileprivate let design: Font.Design
        fileprivate let relativeTo: Font.TextStyle
        fileprivate let scales: Bool
        fileprivate let maximumScale: CGFloat
        fileprivate let usesMonospacedDigits: Bool

        fileprivate init(
            size: CGFloat,
            weight: Font.Weight = .regular,
            design: Font.Design = .default,
            relativeTo: Font.TextStyle,
            scales: Bool = true,
            maximumScale: CGFloat = 2.25,
            usesMonospacedDigits: Bool = false
        ) {
            self.size = size
            self.weight = weight
            self.design = design
            self.relativeTo = relativeTo
            self.scales = scales
            self.maximumScale = maximumScale
            self.usesMonospacedDigits = usesMonospacedDigits
        }

        /// Mirrors `Font.monospacedDigit()` so existing typography expressions remain composable.
        func monospacedDigit() -> Self {
            Self(
                size: size,
                weight: weight,
                design: design,
                relativeTo: relativeTo,
                scales: scales,
                maximumScale: maximumScale,
                usesMonospacedDigits: true
            )
        }

        fileprivate func font(size resolvedSize: CGFloat) -> Font {
            let font = Font.system(size: resolvedSize, weight: weight, design: design)
            return usesMonospacedDigits ? font.monospacedDigit() : font
        }

        fileprivate func resolvedSize(
            systemScaledSize: CGFloat,
            dynamicTypeSize: DynamicTypeSize
        ) -> CGFloat {
            guard scales else { return size }

            // `@ScaledMetric` currently remains at its wrapped value when a macOS host overrides
            // Dynamic Type (including accessibility preview sizes). Keep it as the first-party
            // source when it does respond, with an environment-driven fallback so macOS actually
            // enlarges text today and deterministic previews exercise the same path.
            let fallback = size * dynamicTypeSize.typographyScale
            let candidate: CGFloat
            if dynamicTypeSize == .large {
                candidate = size
            } else if dynamicTypeSize > .large {
                candidate = max(systemScaledSize, fallback)
            } else {
                candidate = min(systemScaledSize, fallback)
            }
            return min(candidate, size * maximumScale)
        }
    }

    // The dot is a decorative SF Symbol, not text. Every meaningful text role is at least 10 pt.
    static let dot = Role(size: 8, relativeTo: .caption2, scales: false)
    static let statLabel = Role(size: 10, weight: .semibold, design: .rounded,
                                relativeTo: .caption2, maximumScale: 1.9)
    static let pickerRowLabel = Role(size: 10, weight: .heavy, design: .rounded,
                                     relativeTo: .caption2, maximumScale: 1.75)
    static let axis = Role(size: 10, relativeTo: .caption2, maximumScale: 1.7,
                           usesMonospacedDigits: true)
    static let annotationTime = Role(size: 10, weight: .medium, design: .rounded,
                                     relativeTo: .caption2, maximumScale: 1.8)
    static let cryptoChange = Role(size: 10, weight: .bold, design: .rounded,
                                   relativeTo: .caption2, maximumScale: 1.9)
    static let placeholderHint = Role(size: 10, design: .rounded, relativeTo: .caption2,
                                      maximumScale: 2)
    static let sectionLabel = Role(size: 10, weight: .bold, design: .rounded,
                                   relativeTo: .caption2, maximumScale: 1.9)
    static let badgeLabel = Role(size: 10, weight: .heavy, design: .rounded,
                                 relativeTo: .caption2, maximumScale: 1.9)
    static let timestamp = Role(size: 10.5, weight: .medium, design: .rounded,
                                relativeTo: .caption, maximumScale: 2)
    static let candleAxis = Role(size: 10.5, weight: .semibold, design: .rounded,
                                 relativeTo: .caption, maximumScale: 1.7,
                                 usesMonospacedDigits: true)
    static let pill = Role(size: 11, weight: .medium, design: .rounded, relativeTo: .caption,
                           maximumScale: 1.9)
    static let candlePriceTag = Role(size: 11, weight: .bold, design: .rounded,
                                     relativeTo: .caption, maximumScale: 1.7,
                                     usesMonospacedDigits: true)
    static let titleHeavy = Role(size: 11, weight: .heavy, design: .rounded,
                                 relativeTo: .headline, maximumScale: 1.8)
    static let bodyRounded = Role(size: 11, design: .rounded, relativeTo: .body,
                                  maximumScale: 2.15)

    // Symbol-only roles intentionally do not scale; see the rationale above.
    static let refreshIcon = Role(size: 11, weight: .bold, relativeTo: .body, scales: false)
    static let iconMedium = Role(size: 12, weight: .semibold, relativeTo: .body, scales: false)
    static let chevron = Role(size: 12, weight: .bold, relativeTo: .body, scales: false)

    static let buttonLabel = Role(size: 12, weight: .semibold, design: .rounded,
                                  relativeTo: .callout, maximumScale: 1.9)
    static let thresholdValue = Role(size: 12, weight: .bold, design: .rounded,
                                     relativeTo: .callout, maximumScale: 1.9)
    static let rowLabel = Role(size: 12.5, weight: .medium, design: .rounded, relativeTo: .body,
                               maximumScale: 2)
    static let emphasis = Role(size: 13, weight: .bold, design: .rounded, relativeTo: .headline,
                               maximumScale: 1.9)
    static let online = Role(size: 13, weight: .medium, design: .rounded, relativeTo: .body,
                             maximumScale: 1.9)
    static let statValue = Role(size: 15, weight: .bold, design: .rounded, relativeTo: .title3,
                                maximumScale: 1.75)
    static let marketPrice = Role(size: 24, weight: .bold, design: .rounded, relativeTo: .title,
                                  maximumScale: 1.55)
    static let placeholderIcon = Role(size: 17, relativeTo: .body, scales: false)
    static let count = Role(size: 46, weight: .bold, design: .rounded, relativeTo: .largeTitle,
                            maximumScale: 1.45)
}

private struct TypographyRoleModifier: ViewModifier {
    let role: Typo.Role
    @ScaledMetric private var scaledSize: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(role: Typo.Role) {
        self.role = role
        _scaledSize = ScaledMetric(wrappedValue: role.size, relativeTo: role.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(role.font(size: role.resolvedSize(
            systemScaledSize: scaledSize,
            dynamicTypeSize: dynamicTypeSize
        )))
    }
}

private extension DynamicTypeSize {
    /// A macOS fallback curve for custom point-size roles. The regular sizes stay restrained; the
    /// accessibility tiers make a meaningful jump while role-specific caps protect fixed controls
    /// and chart plot area. `large` is exactly 1 so default screenshots remain pixel-identical.
    var typographyScale: CGFloat {
        switch self {
        case .xSmall: return 0.88
        case .small: return 0.93
        case .medium: return 0.97
        case .large: return 1
        case .xLarge: return 1.12
        case .xxLarge: return 1.23
        case .xxxLarge: return 1.35
        case .accessibility1: return 1.5
        case .accessibility2: return 1.68
        case .accessibility3: return 1.85
        case .accessibility4: return 2.05
        case .accessibility5: return 2.25
        @unknown default: return 1
        }
    }
}

extension View {
    /// Applies a design-system font while preserving SwiftUI Dynamic Type behavior.
    func font(_ role: Typo.Role) -> some View {
        modifier(TypographyRoleModifier(role: role))
    }
}

// `Text` declares its own Font-only overload, which otherwise shadows the generic `View` overload
// inside result builders such as Charts' `AxisValueLabel`. The exact Role overload keeps chart
// labels on the same scaled typography path without exposing a fixed Font escape hatch.
extension Text {
    func font(_ role: Typo.Role) -> some View {
        modifier(TypographyRoleModifier(role: role))
    }
}
