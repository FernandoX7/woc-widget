import SwiftUI

// MARK: - Reusable glass surfaces
//
// The repeated "tinted glass card" and "glass pill" treatments, extracted so the radii/fills/
// strokes live in one place. The DEFAULT render is byte-identical to the originals (guardrail 9):
// `Palette.card` fill + `Palette.cardStroke` / `.thinMaterial` capsule. These are ViewModifiers (not
// bare `View` extensions) so they can read the accessibility environment and adapt — the one thing
// system Liquid Glass does for free that hand-rolled material otherwise wouldn't: opaque fills under
// Reduce Transparency, a stronger stroke under Increase Contrast.

private struct GlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let fill = reduceTransparency ? Palette.cardOpaque : Palette.card
        let stroke = contrast == .increased ? Palette.cardStrokeStrong : Palette.cardStroke
        return content
            .background(RoundedRectangle(cornerRadius: Radius.r14).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Radius.r14).strokeBorder(stroke))
    }
}

private struct GlassPillModifier<S: ShapeStyle>: ViewModifier {
    let stroke: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(reduceTransparency ? AnyShapeStyle(Palette.pillOpaque)
                                                          : AnyShapeStyle(.thinMaterial)))
            .overlay(Capsule().strokeBorder(
                stroke, lineWidth: contrast == .increased ? LineWidth.w2 : LineWidth.w1))
    }
}

extension View {
    /// Rounded tinted-glass card: `Palette.card` fill + `Palette.cardStroke` border at `Radius.r14`
    /// (opaque / higher-contrast under the matching accessibility settings).
    func glassCard() -> some View { modifier(GlassCardModifier()) }

    /// Thin-material capsule with the given border stroke (header crypto pill, status badge);
    /// opaque under Reduce Transparency.
    func glassPill<S: ShapeStyle>(stroke: S) -> some View { modifier(GlassPillModifier(stroke: stroke)) }
}

// MARK: - Reusable views

struct GlassButtonStyle<S: Shape>: ButtonStyle {
    var shape: S
    // `@State` cannot live directly in a `ButtonStyle` (no valid view lifecycle); the hover state
    // belongs to the rendered body, so it lives in this private nested `View`.
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, shape: shape)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        let shape: S
        @State private var isHovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .background(.regularMaterial, in: shape)
                .overlay(shape.fill(Color.white.opacity(isHovered || configuration.isPressed ? Opacity.o15 : 0)))
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : Motion.hover, value: isHovered)
        }
    }
}

/// A status dot with an optional gentle "live" pulse via `.symbolEffect` (render-layer, not a
/// `repeatForever` transaction). The pulse is SELF-GATED to the foregrounded popover and Reduce
/// Motion: any repeating animation that runs while a `MenuBarExtra(.window)` is CLOSED makes it
/// re-present in a loop (guardrail 1), so the dot animates only when `active` AND the scene is
/// active AND Reduce Motion is off. (The sole current call site passes `active: false`, so the
/// pulse never runs today; this gating is defense-in-depth for any future reuse.) The dot is
/// decorative — `accessibilityHidden` since the adjacent badge text already states the status.
struct StatusDot: View {
    var color: Color
    var active: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let live = active && scenePhase == .active && !reduceMotion
        return Image(systemName: "circle.fill")
            .font(Typo.dot)
            .foregroundStyle(color)
            .accessibilityHidden(true)
            .shadow(color: color.opacity(active ? Opacity.o85 : 0), radius: active ? Shadow.dotRadius : 0)
            .symbolEffect(.pulse, options: live ? .repeating : .nonRepeating, isActive: live)
    }
}

struct StatBox: View {
    let label: LocalizedStringKey
    let value: String
    var tint: Color = Palette.textPrimary
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        VStack(spacing: Space.s2) {
            Text(value)
                .font(Typo.statValue)
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(Typo.statLabel)
                .textCase(.uppercase)
                .tracking(Tracking.t06)
                .foregroundStyle(Palette.tertiaryText(for: contrast))
        }
        .frame(maxWidth: .infinity)
    }
}
