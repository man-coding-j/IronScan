import SwiftUI

enum IronTheme {
    static let beigeBackground = Color(red: 0.96, green: 0.94, blue: 0.91)
    static let creamBackground = beigeBackground
    static let mintBackground = beigeBackground

    static let terracottaPrimary = Color(red: 0.66, green: 0.41, blue: 0.30)
    static let terracottaAccent = Color(red: 0.78, green: 0.54, blue: 0.40)
    static let sageAccent = Color(red: 0.70, green: 0.74, blue: 0.64)

    static let textPrimary = Color(red: 0.20, green: 0.17, blue: 0.15)
    static let textSecondary = Color(red: 0.48, green: 0.43, blue: 0.39)
    static let textSlate = textPrimary
    static let slateText = textPrimary
    static let textMuted = textSecondary
    static let textDark = textPrimary
    static let deepSlate = textPrimary

    static let cardFill = Color.white.opacity(0.40)
    static let cardHighlight = Color.white.opacity(0.60)
    static let shadowColor = Color.black.opacity(0.04)
    static let warning = Color(red: 0.76, green: 0.47, blue: 0.34)
    static let criticalGlassTint = Color(red: 0.82, green: 0.60, blue: 0.52).opacity(0.16)

    static let tealPrimary = terracottaPrimary
    static let tealDeep = textPrimary
    static let cardGlass = cardFill

    static func roundedFont(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

struct LiquidGlassCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 24
    var fill: Color = IronTheme.cardFill

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(.ultraThinMaterial, in: shape)
            .background(fill, in: shape)
            .overlay {
                shape.stroke(IronTheme.cardHighlight, lineWidth: 1.5)
            }
            .shadow(color: IronTheme.shadowColor, radius: 15, x: 0, y: 8)
    }
}

private struct LiquidGlassPanelModifier<PanelShape: Shape>: ViewModifier {
    let shape: PanelShape
    var fill: Color = IronTheme.cardFill

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(fill, in: shape)
            .overlay {
                shape.stroke(IronTheme.cardHighlight, lineWidth: 1.2)
            }
            .shadow(color: IronTheme.shadowColor, radius: 12, x: 0, y: 6)
    }
}

private struct OrganicTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fontDesign(.rounded)
            .foregroundStyle(IronTheme.textPrimary)
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassCardStyle(
                cornerRadius: cornerRadius,
                fill: tint ?? IronTheme.cardFill.opacity(interactive ? 0.95 : 1)
            )
        )
    }

    func liquidGlassPanel<PanelShape: Shape>(
        in shape: PanelShape,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassPanelModifier(
                shape: shape,
                fill: tint ?? IronTheme.cardFill.opacity(interactive ? 0.95 : 1)
            )
        )
    }

    func organicTypography() -> some View {
        modifier(OrganicTypographyModifier())
    }

    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        if prominent {
            buttonStyle(OrganicPrimaryButtonStyle())
        } else {
            buttonStyle(.plain)
        }
    }
}

struct OrganicPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IronTheme.roundedFont(.headline, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                IronTheme.terracottaPrimary.opacity(configuration.isPressed ? 0.88 : 0.96),
                                IronTheme.terracottaAccent.opacity(configuration.isPressed ? 0.84 : 0.92)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay {
                Capsule().stroke(Color.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: IronTheme.terracottaPrimary.opacity(0.18), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

typealias TealPrimaryButtonStyle = OrganicPrimaryButtonStyle

struct IronScreenBackground: View {
    var body: some View {
        ZStack {
            IronTheme.beigeBackground

            LinearGradient(
                colors: [
                    Color.white.opacity(0.55),
                    IronTheme.beigeBackground,
                    Color(red: 0.91, green: 0.88, blue: 0.83)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.45),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 380
            )

            IronLeafGlow(alignment: .topTrailing, rotation: -14, scale: 0.92, opacity: 0.16)
            IronLeafGlow(alignment: .bottomLeading, rotation: 18, scale: 1.08, opacity: 0.12)
        }
        .ignoresSafeArea()
    }
}

struct IronCTAButtonLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Text(title)
            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .bold))
        }
    }
}

struct GlossyTerracottaDrop: View {
    var body: some View {
        ZStack {
            LiquidDropShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.93, green: 0.76, blue: 0.66),
                            IronTheme.terracottaAccent,
                            IronTheme.terracottaPrimary
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            LiquidDropShape()
                .stroke(Color.white.opacity(0.6), lineWidth: 1.2)

            Circle()
                .fill(Color.white.opacity(0.50))
                .frame(width: 22, height: 22)
                .blur(radius: 1)
                .offset(x: 18, y: 12)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: 52)
                .rotationEffect(.degrees(18))
                .offset(x: 18, y: -18)
        }
        .shadow(color: IronTheme.terracottaPrimary.opacity(0.20), radius: 16, x: 0, y: 10)
    }
}

struct IronLeafGlow: View {
    var alignment: Alignment = .bottomTrailing
    var rotation: Double = 0
    var scale: CGFloat = 1
    var opacity: Double = 0.18

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                IronTheme.sageAccent.opacity(opacity),
                                IronTheme.sageAccent.opacity(0.01)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 94, height: 164)
                    .rotationEffect(.degrees(-32))
                    .offset(x: 18, y: 20)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                IronTheme.terracottaAccent.opacity(opacity * 0.55),
                                IronTheme.terracottaAccent.opacity(0.01)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 78, height: 140)
                    .rotationEffect(.degrees(18))
                    .offset(x: -26, y: 26)
            }
            .blur(radius: 10)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
        }
        .allowsHitTesting(false)
    }
}

private struct LiquidDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.midY),
            control1: CGPoint(x: rect.midX * 0.92, y: rect.minY + rect.height * 0.16),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.12),
            control2: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY),
            control2: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.28),
            control2: CGPoint(x: rect.midX * 1.08, y: rect.minY + rect.height * 0.16)
        )
        return path
    }
}
