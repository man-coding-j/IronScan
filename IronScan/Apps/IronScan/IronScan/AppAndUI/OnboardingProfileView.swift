import SwiftUI

struct OnboardingProfileView: View {
    let onComplete: () -> Void

    @EnvironmentObject private var authManager: AuthManager

    @AppStorage("userFirstName") private var userFirstName = ""
    @AppStorage("userLastName") private var userLastName = ""
    @AppStorage("userAge") private var userAge = 0
    @AppStorage("userGender") var userGender: String = ""
    @AppStorage("userBiologicalSex") private var userBiologicalSex = UserBiologicalSex.other.rawValue
    @AppStorage("userWeight") private var userWeight = ""
    @AppStorage("userWeightUnit") private var userWeightUnit = "lbs"

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var age = ""
    @State private var gender = ""
    @State private var weight = ""
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var showReminderPrompt = false

    private var parsedAge: Int? {
        let trimmedAge = age.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedAge = Int(trimmedAge), parsedAge > 0, parsedAge < 121 else { return nil }
        return parsedAge
    }

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !age.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !gender.isEmpty &&
        !weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IronScreenBackground()

                VStack(alignment: .leading, spacing: 24) {
                    header

                    Form {
                        Section("Profile Information") {
                            TextField("First Name", text: $firstName)
                            TextField("Last Name", text: $lastName)
                            TextField("Age", text: $age)
                                .keyboardType(.numberPad)
                            Picker("Gender", selection: $gender) {
                                Text("Select").tag("")
                                Text("Male").tag("Male")
                                Text("Female").tag("Female")
                                Text("Other").tag("Other")
                            }
                            TextField("Weight", text: $weight)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: 560)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    if let submissionError {
                        Text(submissionError)
                            .font(IronTheme.roundedFont(.footnote, weight: .semibold))
                            .foregroundStyle(IronTheme.warning)
                            .frame(maxWidth: 560, alignment: .leading)
                    }

                    Button {
                        Task {
                            await saveAndContinue()
                        }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSubmitting ? "Saving..." : "Submit")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(OrganicPrimaryButtonStyle())
                    .disabled(!canContinue || isSubmitting)
                    .opacity(canContinue && !isSubmitting ? 1 : 0.58)
                    .frame(maxWidth: 560)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                firstName = userFirstName
                lastName = userLastName
                age = userAge > 0 ? "\(userAge)" : ""
                gender = userGender
                weight = userWeight
            }
            .sheet(isPresented: $showReminderPrompt) {
                DailyReminderPromptSheet(
                    enableReminders: {
                        Task {
                            let granted = await NotificationManager.shared.requestNotificationPermission()
                            if granted {
                                NotificationManager.shared.scheduleDailyScanReminder()
                            }
                            completeOnboarding()
                        }
                    },
                    maybeLater: {
                        completeOnboarding()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("ironscan_icon_only_transparent")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .padding(.bottom, 6)

            Text("Complete Your Profile")
                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                .foregroundStyle(IronTheme.textPrimary)

            Text("We use this information to calibrate our AI models and provide accurate hemoglobin estimates tailored to your biology.")
                .font(IronTheme.roundedFont(.body))
                .foregroundStyle(IronTheme.textSecondary)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func saveAndContinue() async {
        guard let session = SupabaseManager.client.auth.currentSession else {
            submissionError = "Please sign in again before submitting your questionnaire."
            return
        }

        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWeight = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        let biologicalSex = gender.isEmpty ? UserBiologicalSex.other.rawValue : gender
        let weightUnit = userWeightUnit.isEmpty ? "lbs" : userWeightUnit

        guard let parsedAge else {
            submissionError = "Enter a valid age."
            return
        }

        guard let parsedWeight = Double(trimmedWeight), parsedWeight > 0 else {
            submissionError = "Enter a valid weight."
            return
        }

        isSubmitting = true
        submissionError = nil

        do {
            let payload = OnboardingProfilePayload(
                id: String(describing: session.user.id),
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                age: parsedAge,
                gender: gender,
                weight: parsedWeight,
                weightUnit: weightUnit,
                createdAt: Date()
            )

            try await SupabaseManager.client
                .from("profiles")
                .upsert(payload, onConflict: "id")
                .execute()

            userFirstName = trimmedFirstName
            userLastName = trimmedLastName
            userAge = parsedAge
            userGender = gender
            userBiologicalSex = biologicalSex
            userWeight = trimmedWeight
            userWeightUnit = weightUnit
            isSubmitting = false
            showReminderPrompt = true
        } catch {
            print("Supabase Insert Error: \(error)")
            submissionError = "We could not save your questionnaire. Please try again."
            isSubmitting = false
        }
    }

    private func completeOnboarding() {
        showReminderPrompt = false
        withAnimation(.easeInOut) {
            authManager.markOnboardingCompleted()
            onComplete()
        }
    }
}

private struct DailyReminderPromptSheet: View {
    let enableReminders: () -> Void
    let maybeLater: () -> Void

    var body: some View {
        ZStack {
            IronScreenBackground()

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stay on Track")
                        .font(IronTheme.roundedFont(.title2, weight: .bold))
                        .foregroundStyle(IronTheme.textPrimary)

                    Text("Daily reminders help maintain consistent hemoglobin calibration by keeping your scans on a reliable rhythm.")
                        .font(IronTheme.roundedFont(.body))
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    Button(action: enableReminders) {
                        Text("Enable Reminders")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OrganicPrimaryButtonStyle())

                    Button(action: maybeLater) {
                        Text("Maybe Later")
                            .font(IronTheme.roundedFont(.headline, weight: .semibold))
                            .foregroundStyle(IronTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 440, alignment: .leading)
            .liquidGlassCard(cornerRadius: 24)
            .padding(24)
        }
    }
}

private struct OnboardingProfilePayload: Encodable {
    let id: String
    let firstName: String
    let lastName: String
    let age: Int
    let gender: String
    let weight: Double
    let weightUnit: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case age
        case gender
        case weight
        case weightUnit = "weight_unit"
        case createdAt = "created_at"
    }
}
