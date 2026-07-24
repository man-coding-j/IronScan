import SwiftUI

enum IronTheme {
    enum Hex {
        static let creamBackground = "#F5EBE1"
        static let terracottaPrimary = "#E68A61"
        static let slateText = "#3D3B4A"
        static let sageAccent = "#8DAA82"
    }

    static let creamBackground = Color(red: 245 / 255, green: 235 / 255, blue: 225 / 255)
    static let terracottaPrimary = Color(red: 230 / 255, green: 138 / 255, blue: 97 / 255)
    static let slateText = Color(red: 61 / 255, green: 59 / 255, blue: 74 / 255)
    static let sageAccent = Color(red: 141 / 255, green: 170 / 255, blue: 130 / 255)
    static let cardGlass = Color.white.opacity(0.48)
    static let warning = Color(red: 205 / 255, green: 116 / 255, blue: 70 / 255)

    static let mintBackground = creamBackground
    static let tealPrimary = terracottaPrimary
    static let tealDeep = slateText
    static let textDark = slateText

    static func roundedFont(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

private struct OrganicGlassEffectModifier<EffectShape: Shape>: ViewModifier {
    let shape: EffectShape
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                content.glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? IronTheme.cardGlass).opacity(0.58), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.76), lineWidth: 0.6)
                }
        }
    }
}

private struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .organicGlassEffect(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(
                color: IronTheme.slateText.opacity(0.08),
                radius: 18,
                x: 0,
                y: 9
            )
    }
}

private struct OrganicTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fontDesign(.rounded)
            .foregroundStyle(IronTheme.slateText)
    }
}

extension View {
    func organicGlassEffect<EffectShape: Shape>(
        in shape: EffectShape,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            OrganicGlassEffectModifier(
                shape: shape,
                tint: tint,
                interactive: interactive
            )
        )
    }

    func liquidGlassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }

    func organicTypography() -> some View {
        modifier(OrganicTypographyModifier())
    }
}

struct OrganicPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IronTheme.roundedFont(.headline, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                IronTheme.terracottaPrimary.opacity(configuration.isPressed ? 0.72 : 0.9),
                in: Capsule()
            )
            .organicGlassEffect(
                in: Capsule(),
                tint: IronTheme.terracottaPrimary,
                interactive: true
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .shadow(
                color: IronTheme.terracottaPrimary.opacity(0.24),
                radius: 14,
                y: 8
            )
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

typealias TealPrimaryButtonStyle = OrganicPrimaryButtonStyle
