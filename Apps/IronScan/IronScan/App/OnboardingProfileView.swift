import SwiftUI

struct OnboardingProfileView: View {
    let onComplete: () -> Void

    @AppStorage("userAge") private var storedAge = 18
    @AppStorage("userBiologicalSex") private var biologicalSexRaw = UserBiologicalSex.other.rawValue
    @AppStorage("isPregnant") private var storedPregnancyStatus = false

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
            ZStack {
                IronScreenBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack {
                        Spacer(minLength: 48)

                        VStack(alignment: .leading, spacing: 24) {
                            header
                            fieldsSection
                            disclaimerSection
                            primaryAction
                        }
                        .padding(28)
                        .frame(maxWidth: 560)
                        .modifier(LiquidGlassCardStyle(cornerRadius: 32))
                        .padding(.horizontal, 20)

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
            }
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
            Text("Welcome to IronScan")
                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)

            Text("Set up your local screening profile for a calmer, more personalized prototype experience.")
                .font(IronTheme.roundedFont(.body))
                .foregroundStyle(IronTheme.textSecondary)
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profile Details")
                .font(IronTheme.roundedFont(.headline, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Age")
                    .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)

                TextField("Enter your age", text: $ageText)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .modifier(LiquidGlassCardStyle(cornerRadius: 20, fill: Color.white.opacity(0.28)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Biological Sex")
                    .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)

                Picker("Biological Sex", selection: $biologicalSexRaw) {
                    ForEach(UserBiologicalSex.allCases, id: \.rawValue) { sex in
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
        VStack(alignment: .leading, spacing: 12) {
            Text("IronScan is an educational screening tool and does not provide medical diagnoses. Always consult a licensed physician.")
                .font(IronTheme.roundedFont(.body, weight: .medium))
                .foregroundStyle(IronTheme.textSecondary)

            Toggle("I understand and agree to continue", isOn: $disclaimerAccepted)
                .font(IronTheme.roundedFont(.body, weight: .medium))
                .tint(IronTheme.terracottaPrimary)
        }
        .padding(20)
        .modifier(LiquidGlassCardStyle(cornerRadius: 24, fill: IronTheme.criticalGlassTint))
    }

    private var primaryAction: some View {
        Button(action: saveAndContinue) {
            Text("Continue")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(OrganicPrimaryButtonStyle())
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.58)
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
