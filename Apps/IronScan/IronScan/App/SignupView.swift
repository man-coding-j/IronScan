import SwiftUI

struct SignupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var age: String = ""
    @State private var gender: String = "Select"
    @State private var localErrorMessage: String?

    var body: some View {
        ZStack {
            IronTheme.creamBackground.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.7),
                    IronTheme.sageAccent.opacity(0.1),
                    IronTheme.terracottaPrimary.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 68, weight: .semibold))
                            .foregroundStyle(IronTheme.terracottaPrimary)

                        Text("Create your account")
                            .font(IronTheme.roundedFont(.largeTitle, weight: .bold))

                        Text("Set up secure email and password access for IronScan.")
                            .font(IronTheme.roundedFont(.body))
                            .foregroundStyle(IronTheme.slateText.opacity(0.72))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 24)

                    VStack(spacing: 16) {
                        AuthGlassTextField(
                            title: "Email",
                            text: $email,
                            contentType: .emailAddress
                        )

                        AuthGlassSecureField(
                            title: "Password",
                            text: $password,
                            contentType: .newPassword
                        )

                        AuthGlassSecureField(
                            title: "Confirm Password",
                            text: $confirmPassword,
                            contentType: .newPassword
                        )

                        AuthGlassTextField(
                            title: "Age",
                            text: $age,
                            contentType: nil
                        )
                        .keyboardType(.numberPad)

                        AuthGlassPickerField(
                            title: "Gender",
                            selection: $gender,
                            options: ["Male", "Female", "Other", "Prefer not to say"]
                        )

                        if let message = localErrorMessage ?? authManager.errorMessage {
                            Text(message)
                                .font(IronTheme.roundedFont(.footnote, weight: .semibold))
                                .foregroundStyle(IronTheme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            submit()
                        } label: {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(authManager.isLoading ? "Creating Account..." : "Create Account")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(AuthPrimaryButtonStyle())
                        .disabled(authManager.isLoading)
                        .opacity(authManager.isLoading ? 0.8 : 1)
                    }
                    .padding(24)
                    .liquidGlassCard(cornerRadius: 30)
                    .padding(.horizontal, 24)

                    Button {
                        dismiss()
                    } label: {
                        Text("Already have an account? Sign In")
                            .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                            .foregroundStyle(IronTheme.terracottaPrimary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(IronTheme.terracottaPrimary)
        .organicTypography()
    }

    private func submit() {
        authManager.clearError()
        localErrorMessage = nil

        guard password == confirmPassword else {
            localErrorMessage = "Passwords do not match."
            return
        }

        authManager.createUser(email: email, password: password, age: age, gender: gender)
    }
}

private struct AuthGlassPickerField: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection = option
                }
            }
        } label: {
            HStack {
                Text(selection == "Select" ? title : selection)
                    .foregroundStyle(selection == "Select" ? IronTheme.textMuted : IronTheme.textSlate)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(IronTheme.textMuted)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 0.8)
            }
            .font(IronTheme.roundedFont(.body))
        }
        .buttonStyle(.plain)
    }
}
