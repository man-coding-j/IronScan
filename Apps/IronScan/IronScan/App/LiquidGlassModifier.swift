import SwiftUI

struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color.white.opacity(0.65), in: shape)
            .overlay {
                shape.stroke(Color.white.opacity(0.8), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
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