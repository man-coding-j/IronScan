import SwiftUI

struct OnboardingFlowView: View {
    private enum Step: Int, CaseIterable {
        case hero
        case howItWorks
        case scanTips
    }

    let onComplete: () -> Void

    @State private var step: Step = .hero

    var body: some View {
        NavigationStack {
            ZStack {
                IronScreenBackground()

                VStack(spacing: 0) {
                    currentStepView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.3), value: step)
            }
            .toolbar(.hidden, for: .navigationBar)
            .organicTypography()
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .hero:
            HeroStartView {
                advance(to: .howItWorks)
            }
            .transition(onboardingStepTransition)
        case .howItWorks:
            OnboardingStep1View(
                onBack: { advance(to: .hero) },
                onNext: { advance(to: .scanTips) }
            )
            .transition(onboardingStepTransition)
        case .scanTips:
            OnboardingStep2View(
                onBack: { advance(to: .howItWorks) },
                onStartScan: onComplete
            )
            .transition(onboardingStepTransition)
        }
    }

    private func advance(to step: Step) {
        withAnimation(.snappy(duration: 0.36)) {
            self.step = step
        }
    }
}

struct HeroStartView: View {
    let onGetStarted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 12)

            heroMark
            titleBlock

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.54))
                    .frame(width: 252, height: 252)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    }

                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 10)
                    .frame(width: 224, height: 224)

                GlossyTerracottaDrop()
                    .frame(width: 124, height: 164)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            VStack(alignment: .leading, spacing: 16) {
                Text("Check your iron levels in under 2 minutes.")
                    .font(IronTheme.roundedFont(.title3, weight: .medium))
                    .foregroundStyle(IronTheme.textSlate)

                Button(action: onGetStarted) {
                    IronCTAButtonLabel(title: "Get Started")
                }
                .buttonStyle(OrganicPrimaryButtonStyle())
            }
            .padding(20)
            .liquidGlassCard(cornerRadius: 28)

            Spacer(minLength: 0)
        }
    }

    private var heroMark: some View {
        Image(systemName: "drop.fill")
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(IronTheme.terracottaPrimary)
            .padding(.top, 12)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IronScan")
                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)

            Text("Smart. Simple. Non-Invasive.\nAnemia Screening for Everyone.")
                .font(IronTheme.roundedFont(.title3))
                .foregroundStyle(IronTheme.textMuted)
                .lineSpacing(4)
        }
    }
}

struct OnboardingStep1View: View {
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHeader(title: "How It Works", onBack: onBack)

            VStack(spacing: 14) {
                HowItWorksCard(
                    icon: "camera.fill",
                    tint: IronTheme.terracottaPrimary,
                    title: "1. Take a Photo",
                    description: "We'll guide you to scan the tongue, eyes, and nail beds to assess anemia risk."
                )
                HowItWorksCard(
                    icon: "sparkles",
                    tint: IronTheme.sageAccent,
                    title: "2. AI Analysis",
                    description: "Our AI analyzes color, texture, and patterns instantly."
                )
                HowItWorksCard(
                    icon: "chart.bar.fill",
                    tint: IronTheme.terracottaPrimary,
                    title: "3. Get Results",
                    description: "Receive your iron deficiency risk score and tips."
                )
            }

            Spacer(minLength: 0)

            Button(action: onNext) {
                IronCTAButtonLabel(title: "Next")
            }
            .buttonStyle(OrganicPrimaryButtonStyle())
        }
    }
}

struct OnboardingStep2View: View {
    let onBack: () -> Void
    let onStartScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingHeader(title: "Let's Scan\nYour Tongue", onBack: onBack)

            Text("Follow these simple steps:")
                .font(IronTheme.roundedFont(.subheadline, weight: .medium))
                .foregroundStyle(IronTheme.textMuted)

            VStack(spacing: 14) {
                InstructionCard(icon: "sun.max.fill", title: "Find good lighting")
                InstructionCard(icon: "mouth.fill", title: "Open your mouth and stick out your tongue")
                InstructionCard(icon: "iphone", title: "Keep your tongue inside the frame")
            }

            Spacer(minLength: 0)

            Button(action: onStartScan) {
                IronCTAButtonLabel(title: "Start Scan")
            }
            .buttonStyle(OrganicPrimaryButtonStyle())
        }
    }
}

private struct HowItWorksCard: View {
    let icon: String
    let tint: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.74))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)

                Text(description)
                    .font(IronTheme.roundedFont(.subheadline))
                    .foregroundStyle(IronTheme.textMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
    }
}

private struct InstructionCard: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.76))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(icon == "sun.max.fill" ? IronTheme.sageAccent : IronTheme.textSlate)
            }

            Text(title)
                .font(IronTheme.roundedFont(.body, weight: .medium))
                .foregroundStyle(IronTheme.textSlate)

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
    }
}

private var onboardingStepTransition: AnyTransition {
    AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
}

@MainActor private func onboardingHeader(title: String, onBack: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 18) {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.66), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)

        Text(title)
            .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
            .foregroundStyle(IronTheme.textSlate)
            .lineLimit(2)
    }
    .padding(.top, 12)
}
