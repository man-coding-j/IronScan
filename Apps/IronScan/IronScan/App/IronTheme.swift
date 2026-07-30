import SwiftUI

enum IronTheme {
    enum Hex {
        static let glassCream = "#F8F6F0"
        static let terracottaPrimary = "#FF6B35"
        static let sageAccent = "#8DAA82"
        static let textSlate = "#2A2830"
        static let mutedText = "#7A7885"
        static let deepSlate = "#121214"
        static let creamBackground = glassCream
        static let slateText = textSlate
    }

    static let glassCream = Color(red: 248 / 255, green: 246 / 255, blue: 240 / 255)
    static let terracottaPrimary = Color(red: 1, green: 107 / 255, blue: 53 / 255)
    static let sageAccent = Color(red: 141 / 255, green: 170 / 255, blue: 130 / 255)
    static let textSlate = Color(red: 42 / 255, green: 40 / 255, blue: 48 / 255)
    static let textMuted = Color(red: 122 / 255, green: 120 / 255, blue: 133 / 255)
    static let deepSlate = Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255)
    static let creamBackground = glassCream
    static let slateText = textSlate
    static let cardGlass = Color.white.opacity(0.65)
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
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(buttonBackground(pressed: configuration.isPressed), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .shadow(
                color: IronTheme.terracottaPrimary.opacity(0.28),
                radius: 18,
                y: 10
            )
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private func buttonBackground(pressed: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                IronTheme.terracottaPrimary.opacity(pressed ? 0.9 : 1),
                Color(red: 1, green: 126 / 255, blue: 76 / 255).opacity(pressed ? 0.84 : 0.96)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

typealias TealPrimaryButtonStyle = OrganicPrimaryButtonStyle

struct IronScreenBackground: View {
    var body: some View {
        ZStack {
            IronTheme.creamBackground

            RadialGradient(
                colors: [
                    Color.white.opacity(0.92),
                    IronTheme.creamBackground.opacity(0.4)
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )

            LinearGradient(
                colors: [
                    IronTheme.sageAccent.opacity(0.08),
                    .clear,
                    IronTheme.terracottaPrimary.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            IronLeafGlow(alignment: .bottomTrailing)
            IronLeafGlow(alignment: .topTrailing, rotation: -18, scale: 0.82, opacity: 0.22)
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
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
            }
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
                            Color(red: 1, green: 180 / 255, blue: 150 / 255).opacity(0.9),
                            IronTheme.terracottaPrimary,
                            Color(red: 1, green: 146 / 255, blue: 98 / 255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            LiquidDropShape()
                .stroke(Color.white.opacity(0.65), lineWidth: 1.2)

            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 24, height: 24)
                .blur(radius: 1)
                .offset(x: 18, y: 12)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 26, height: 56)
                .rotationEffect(.degrees(18))
                .offset(x: 18, y: -20)
                .blur(radius: 0.6)
        }
        .shadow(color: IronTheme.terracottaPrimary.opacity(0.24), radius: 20, y: 12)
    }
}

struct IronLeafGlow: View {
    var alignment: Alignment = .bottomTrailing
    var rotation: Double = 0
    var scale: CGFloat = 1
    var opacity: Double = 0.28

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
                    .frame(width: 96, height: 170)
                    .rotationEffect(.degrees(-34))
                    .offset(x: 18, y: 20)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                IronTheme.sageAccent.opacity(opacity * 0.9),
                                IronTheme.sageAccent.opacity(0.01)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 80, height: 148)
                    .rotationEffect(.degrees(18))
                    .offset(x: -28, y: 28)
            }
            .blur(radius: 6)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: alignment
            )
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
