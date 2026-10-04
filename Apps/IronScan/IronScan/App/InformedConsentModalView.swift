import SwiftUI

struct InformedConsentModalView: View {
    let onAccept: () -> Void

    @State private var understandsInvestigationalUse = false

    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack {
                    Spacer(minLength: 36)

                    VStack(alignment: .leading, spacing: 22) {
                        header
                        section(
                            title: "Research Prototype",
                            body: "IronScan is a non-diagnostic research prototype. It estimates optical pallor patterns from tongue, conjunctival, and lip images, but it is not FDA-approved and cannot replace laboratory testing or clinical judgment."
                        )
                        section(
                            title: "Privacy & On-Device Processing",
                            body: "Image quality review, framing, and optical analysis are performed on-device whenever possible. Raw tissue images remain local to this device unless you explicitly export a report or enable a separate cloud workflow."
                        )
                        section(
                            title: "Voluntary Participation & Retention",
                            body: "Participation is voluntary. You can stop using the prototype at any time. Screening records are stored locally on-device first, and any later synchronization keeps unsynced records queued safely until connectivity returns."
                        )

                        Toggle(
                            "I understand this is an investigational screening tool",
                            isOn: $understandsInvestigationalUse
                        )
                        .font(IronTheme.roundedFont(.body, weight: .semibold))
                        .tint(IronTheme.terracottaPrimary)
                        .padding(18)
                        .modifier(LiquidGlassCardStyle(cornerRadius: 22, fill: IronTheme.criticalGlassTint))

                        Button(action: onAccept) {
                            Text("Continue to Profile Setup")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OrganicPrimaryButtonStyle())
                        .disabled(!understandsInvestigationalUse)
                        .opacity(understandsInvestigationalUse ? 1 : 0.58)
                    }
                    .padding(28)
                    .frame(maxWidth: 620)
                    .modifier(LiquidGlassCardStyle(cornerRadius: 32))
                    .padding(.horizontal, 20)

                    Spacer(minLength: 36)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(IronTheme.beigeBackground.ignoresSafeArea())
        .organicTypography()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Informed Consent", systemImage: "checklist.shield")
                .font(IronTheme.roundedFont(.title2, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)

            Text("Please review this summary before using any camera-based screening features.")
                .font(IronTheme.roundedFont(.body))
                .foregroundStyle(IronTheme.textSecondary)
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)

            Text(body)
                .font(IronTheme.roundedFont(.body))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .modifier(LiquidGlassCardStyle(cornerRadius: 24, fill: Color.white.opacity(0.26)))
    }
}
