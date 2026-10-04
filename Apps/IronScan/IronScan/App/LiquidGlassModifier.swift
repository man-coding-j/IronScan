import SwiftUI

struct LiquidBounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidBounceButtonStyle {
    static var liquidBounce: LiquidBounceButtonStyle { LiquidBounceButtonStyle() }
}
