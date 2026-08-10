import SwiftUI

struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    var tint: Color? = nil
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedTint = tint ?? Color.white.opacity(interactive ? 0.18 : 0.12)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    interactive
                    ? .regular.tint(resolvedTint).interactive()
                    : .regular.tint(resolvedTint),
                    in: shape
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color.white.opacity(0.65), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.8), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }
        }
    }


struct LiquidGlassPanelModifier<PanelShape: Shape>: ViewModifier {
    let shape: PanelShape
    var tint: Color? = nil
    var interactive: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        let resolvedTint = tint ?? Color.white.opacity(interactive ? 0.14 : 0.1)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    interactive
                    ? .regular.tint(resolvedTint).interactive()
                    : .regular.tint(resolvedTint),
                    in: shape
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color.white.opacity(0.65), in: shape)
                .overlay {
                    shape.stroke(Color.white.opacity(0.8), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
            }
        }
    }


extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive
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
                tint: tint,
                interactive: interactive
            )
        )
    }

    @ViewBuilder
    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}


// MARK: - Premium Button Micro-Interactions
struct LiquidBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The button physically squishes down to 92% of its size when pressed
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            // A bouncy spring animation makes it feel like physical glass
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            // Fires a physical haptic tap inside the device when touched (iOS 17+)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidBounceButtonStyle {
    static var liquidBounce: LiquidBounceButtonStyle { LiquidBounceButtonStyle() }
}
