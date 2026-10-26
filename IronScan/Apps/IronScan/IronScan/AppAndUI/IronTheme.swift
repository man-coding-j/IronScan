import SwiftUI
import UIKit

extension Color {
    static let brandTeal = Color(red: 20 / 255, green: 82 / 255, blue: 71 / 255)
    static let brandMarigold = Color(red: 250 / 255, green: 168 / 255, blue: 5 / 255)
    static let brandGlacier = Color(red: 205 / 255, green: 224 / 255, blue: 228 / 255)
    static let brandSand = Color(red: 232 / 255, green: 217 / 255, blue: 201 / 255)
}

enum IronTheme {
    static let brandTeal = Color.brandTeal
    static let brandMarigold = Color.brandMarigold
    static let brandGlacier = Color.brandGlacier
    static let brandSand = Color.brandSand
    static let beigeBackground = brandSand
    static let creamBackground = beigeBackground
    static let mintBackground = beigeBackground

    // Compatibility aliases keep existing screens on the centralized palette.
    static let terracottaPrimary = brandTeal
    static let terracottaAccent = Color(red: 29 / 255, green: 107 / 255, blue: 93 / 255)
    static let sageAccent = brandTeal
    static let textPrimary = brandTeal
    static let textSecondary = brandTeal.opacity(0.68)
    static let textSlate = textPrimary
    static let slateText = textPrimary
    static let textMuted = textSecondary
    static let textDark = textPrimary
    static let deepSlate = textPrimary

    static let primaryGradient = LinearGradient(
        colors: [brandTeal, terracottaAccent], startPoint: .leading, endPoint: .trailing
    )
    static let cardFill = brandGlacier.opacity(0.38)
    static let cardHighlight = Color.white.opacity(0.75)
    static let glassBorder = LinearGradient(
        colors: [Color.white.opacity(0.75), brandGlacier.opacity(0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let shadowColor = brandTeal.opacity(0.09)
    static let warning = brandMarigold
    static let criticalGlassTint = brandMarigold.opacity(0.16)
    static let tealPrimary = brandTeal
    static let tealDeep = brandTeal
    static let cardGlass = cardFill

    static func editorialFont(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static func roundedFont(
        _ style: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        // Keep call sites stable; only display and section headings use serif.
        switch style {
        case .largeTitle, .title, .title2, .title3, .headline:
            editorialFont(style, weight: weight)
        default:
            .system(style, design: .default, weight: weight)
        }
    }

    enum Hex {
        static let brandTeal = "#145247"
        static let brandMarigold = "#FAA805"
        static let brandGlacier = "#CDE0E4"
        static let brandSand = "#E8D9C9"
        static let creamBackground = brandSand
        static let terracottaPrimary = brandTeal
        static let slateText = brandTeal
        static let sageAccent = brandTeal
    }

    @MainActor
    static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor(brandTeal.opacity(0.92))
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(brandSand.opacity(0.75))
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(brandSand.opacity(0.75))]
            item.selected.iconColor = UIColor(brandMarigold)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(brandMarigold)]
        }
        // Style the native selection indicator without replacing or resizing tabs.
        appearance.selectionIndicatorImage = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { _ in
            let capsule = UIBezierPath(roundedRect: CGRect(x: 0.5, y: 0.5, width: 63, height: 47), cornerRadius: 23.5)
            UIColor(brandMarigold.opacity(0.22)).setFill()
            capsule.fill()
            UIColor(brandMarigold).setStroke()
            capsule.lineWidth = 1
            capsule.stroke()
        }.resizableImage(withCapInsets: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)).withRenderingMode(.alwaysOriginal)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(brandSand.opacity(0.75))
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
                shape.stroke(IronTheme.glassBorder, lineWidth: 1)
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
                shape.stroke(IronTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: IronTheme.shadowColor, radius: 12, x: 0, y: 6)
    }
}

private struct OrganicTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fontDesign(.default)
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
            .font(.system(.headline, design: .default, weight: .bold))
            .foregroundStyle(Color.brandSand)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                IronTheme.terracottaPrimary.opacity(configuration.isPressed ? 0.88 : 1),
                                IronTheme.terracottaAccent.opacity(configuration.isPressed ? 0.84 : 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(Color.brandMarigold.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: IronTheme.terracottaPrimary.opacity(0.18), radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

typealias TealPrimaryButtonStyle = OrganicPrimaryButtonStyle

/// Fixed canvas curves remain behind scrolling translucent surfaces.
struct MarigoldRibbonBackground: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                Color.brandSand
                Path { path in
                    path.move(to: CGPoint(x: -0.12 * w, y: 0.16 * h))
                    path.addCurve(to: CGPoint(x: 0.78 * w, y: 0.13 * h),
                                  control1: CGPoint(x: 0.27 * w, y: 0.23 * h),
                                  control2: CGPoint(x: 0.43 * w, y: 0.04 * h))
                    path.addCurve(to: CGPoint(x: 1.12 * w, y: 0.40 * h),
                                  control1: CGPoint(x: 0.22 * w, y: 0.34 * h),
                                  control2: CGPoint(x: 0.86 * w, y: 0.45 * h))
                }
                .stroke(Color.brandMarigold.opacity(0.8), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: 1.12 * w, y: 0.54 * h))
                    path.addCurve(to: CGPoint(x: 0.68 * w, y: 0.72 * h),
                                  control1: CGPoint(x: 0.17 * w, y: 0.34 * h),
                                  control2: CGPoint(x: 0.17 * w, y: 0.58 * h))
                    path.addCurve(to: CGPoint(x: 0.40 * w, y: 0.87 * h),
                                  control1: CGPoint(x: 1.02 * w, y: 0.80 * h),
                                  control2: CGPoint(x: 0.72 * w, y: 0.94 * h))
                    path.addCurve(to: CGPoint(x: -0.12 * w, y: 0.85 * h),
                                  control1: CGPoint(x: 0.14 * w, y: 0.85 * h),
                                  control2: CGPoint(x: 0.10 * w, y: 0.80 * h))
                }
                .stroke(Color.brandMarigold.opacity(0.8), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct IronScreenBackground: View {
    var body: some View {
        MarigoldRibbonBackground()
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
                            Color.brandGlacier,
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

struct AuthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(red: 0.15, green: 0.15, blue: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
