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
