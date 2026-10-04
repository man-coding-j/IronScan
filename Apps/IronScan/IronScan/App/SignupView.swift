import SwiftUI

struct SignupView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localErrorMessage: String?

    var body: some View {
        ZStack {
            IronScreenBackground()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 24)

                    VStack(spacing: 16) {
                        AuthGlassTextField(
                            title: "Email",
                            text: $email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress
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
                    .padding(28)
                    .frame(maxWidth: 560)
                    .modifier(LiquidGlassCardStyle(cornerRadius: 32))
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

        authManager.createUser(email: email, password: password, age: "", gender: "")
    }
}
