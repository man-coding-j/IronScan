import SwiftUI

enum OnboardingConsent {
    static let storageKey = "ironscan.onboarding.educational-consent.v2"
    static let title = "Before You Begin"
    static let summary = "IronScan is an educational research prototype developed for the Conrad Challenge."
    static let detail = "It evaluates optical color patterns from eye, nail, and tongue images. It is not FDA-cleared, does not measure iron or hemoglobin, and cannot establish a clinical diagnosis. Confirm with a laboratory test."
}

struct OnboardingConsentView: View {
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "camera.metering.multispot")
                .font(.system(size: 58, weight: .medium))
                .foregroundStyle(IronTheme.tealPrimary)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(OnboardingConsent.title)
                    .font(.largeTitle.bold())
                Text(OnboardingConsent.summary)
                    .font(.title3.weight(.semibold))
                Text(OnboardingConsent.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 14) {
                Label("Three on-device image checks", systemImage: "1.circle")
                Label("Images remain local", systemImage: "lock.shield")
                Label("Laboratory confirmation is required", systemImage: "testtube.2")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .liquidGlassCard(cornerRadius: 20)

            Spacer()
            Button("I Agree and Understand", action: onAccept)
                .buttonStyle(TealPrimaryButtonStyle())
            Text("By continuing, you acknowledge these research limitations.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .foregroundStyle(IronTheme.textDark)
        .background(IronTheme.mintBackground.ignoresSafeArea())
    }
}
