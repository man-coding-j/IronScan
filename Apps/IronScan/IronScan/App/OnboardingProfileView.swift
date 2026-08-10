import SwiftUI

struct OnboardingProfileView: View {
    let onComplete: () -> Void

    @AppStorage(DemographicStorageKeys.userAge) private var storedAge = 18
    @AppStorage(DemographicStorageKeys.userBiologicalSex) private var biologicalSexRaw = UserBiologicalSex.other.rawValue
    @AppStorage(DemographicStorageKeys.isPregnant) private var storedPregnancyStatus = false

    @State private var ageText = ""
    @State private var disclaimerAccepted = false

    private var selectedBiologicalSex: UserBiologicalSex {
        UserBiologicalSex(rawValue: biologicalSexRaw) ?? .other
    }

    private var parsedAge: Int? {
        guard let age = Int(ageText), age > 0, age < 121 else { return nil }
        return age
    }

    private var canContinue: Bool {
        disclaimerAccepted && parsedAge != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    formSection
                    disclaimerSection
                    actionSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(IronScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if ageText.isEmpty {
                    ageText = storedAge > 0 ? "\(storedAge)" : ""
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Your Screening Profile")
                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                .foregroundStyle(IronTheme.textSlate)

            Text("These demographics are stored locally and used only to calibrate IronScan's educational screening baseline.")
                .font(IronTheme.roundedFont(.body, weight: .medium))
                .foregroundStyle(IronTheme.textMuted)
        }
    }

    @ViewBuilder
    private var formSection: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                profileFields
            }
            .padding(20)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            profileFields
                .padding(20)
                .liquidGlassCard(cornerRadius: 28, interactive: true)
        }
    }

    private var profileFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Age")
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)

                TextField("Enter your age", text: $ageText)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Biological Sex")
                    .font(IronTheme.roundedFont(.headline, weight: .bold))
                    .foregroundStyle(IronTheme.textSlate)

                Picker("Biological Sex", selection: $biologicalSexRaw) {
                    ForEach(UserBiologicalSex.allCases) { sex in
                        Text(sex.rawValue).tag(sex.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            if selectedBiologicalSex == .female {
                Toggle("Currently Pregnant", isOn: $storedPregnancyStatus)
                    .font(IronTheme.roundedFont(.body, weight: .medium))
                    .tint(IronTheme.terracottaPrimary)
            }
        }
    }

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("IronScan is an educational screening tool and does not provide medical diagnoses. Always consult a licensed physician.")
                .font(IronTheme.roundedFont(.body, weight: .bold))
                .foregroundStyle(IronTheme.warning)

            Toggle("I understand and agree to the Terms & Medical Disclaimer", isOn: $disclaimerAccepted)
                .font(IronTheme.roundedFont(.body, weight: .medium))
                .tint(IronTheme.terracottaPrimary)
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 24, tint: IronTheme.criticalGlassTint, interactive: true)
    }

    @ViewBuilder
    private var actionSection: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                actionButton
            }
            .padding(16)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            actionButton
                .padding(16)
                .liquidGlassCard(cornerRadius: 26, interactive: true)
        }
    }

    private var actionButton: some View {
        Button(action: saveAndContinue) {
            IronCTAButtonLabel(title: "Save Profile & Continue")
        }
        .buttonStyle(OrganicPrimaryButtonStyle())
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.6)
    }

    private func saveAndContinue() {
        guard let parsedAge else { return }
        storedAge = parsedAge
        if selectedBiologicalSex != .female {
            storedPregnancyStatus = false
        }
        onComplete()
    }
}
