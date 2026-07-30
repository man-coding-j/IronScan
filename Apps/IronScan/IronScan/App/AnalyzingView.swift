import SwiftUI

struct AnalyzingView<Results: View>: View {
    @State private var progress = 0.0
    @State private var showsResults = false

    private let results: () -> Results

    init(@ViewBuilder results: @escaping () -> Results) {
        self.results = results
    }

    var body: some View {
        Group {
            if showsResults {
                results()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content
            }
        }
        .task {
            guard !showsResults else { return }
            withAnimation(.linear(duration: 3)) {
                progress = 1
            }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.spring(response: 0.48, dampingFraction: 0.9)) {
                showsResults = true
            }
        }
    }

    private var content: some View {
        ZStack {
            IronScreenBackground()

            VStack(spacing: 28) {
                Spacer(minLength: 40)

                HStack {
                    Spacer()
                    IronLeafGlow(alignment: .topTrailing, scale: 0.62, opacity: 0.36)
                        .frame(width: 120, height: 120)
                }

                VStack(spacing: 8) {
                    Text("Analyzing\nYour Scan...")
                        .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                        .foregroundStyle(IronTheme.textSlate)
                        .multilineTextAlignment(.center)
                }

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 220, height: 220)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.84), lineWidth: 1)
                        }

                    Circle()
                        .trim(from: 0.1, to: 0.92)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.95),
                                    IronTheme.sageAccent.opacity(0.24),
                                    IronTheme.terracottaPrimary.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round)
                        )
                        .frame(width: 194, height: 194)

                    GlossyTerracottaDrop()
                        .frame(width: 88, height: 116)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Checking color, texture, and patterns...")
                        .font(IronTheme.roundedFont(.subheadline, weight: .medium))
                        .foregroundStyle(IronTheme.textSlate)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.74))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            IronTheme.terracottaPrimary,
                                            Color(red: 1, green: 145 / 255, blue: 98 / 255)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress)
                        }
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.84), lineWidth: 1)
                        }
                    }
                    .frame(height: 16)
                }
                .padding(20)
                .liquidGlassCard(cornerRadius: 24)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }
}
