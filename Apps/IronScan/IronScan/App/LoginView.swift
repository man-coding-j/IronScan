import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var showsSignup = false

    var body: some View {
        NavigationStack {
            ZStack {
                IronTheme.creamBackground.ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.7),
                        IronTheme.terracottaPrimary.opacity(0.08),
                        IronTheme.sageAccent.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 40)

                        VStack(spacing: 14) {
                            Image(systemName: "drop.circle.fill")
                                .font(.system(size: 72, weight: .semibold))
                                .foregroundStyle(IronTheme.terracottaPrimary)

                            Text("Welcome back")
                                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))

                            Text("Sign in to continue your IronScan journey.")
                                .font(IronTheme.roundedFont(.body))
                                .foregroundStyle(IronTheme.slateText.opacity(0.72))
                                .multilineTextAlignment(.center)
                        }
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
                                contentType: .password
                            )

                            if let errorMessage = authManager.errorMessage {
                                Text(errorMessage)
                                    .font(IronTheme.roundedFont(.footnote, weight: .semibold))
                                    .foregroundStyle(IronTheme.warning)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            Button {
                                authManager.signIn(email: email, password: password)
                            } label: {
                                HStack {
                                    if authManager.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(authManager.isLoading ? "Signing In..." : "Sign In")
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
                        .animation(.easeInOut(duration: 0.24), value: authManager.errorMessage)

                        Button {
                            authManager.clearError()
                            showsSignup = true
                        } label: {
                            Text("Don't have an account? Sign Up")
                                .font(IronTheme.roundedFont(.subheadline, weight: .semibold))
                                .foregroundStyle(IronTheme.terracottaPrimary)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsSignup) {
                SignupView()
            }
        }
        .tint(IronTheme.terracottaPrimary)
        .organicTypography()
    }
}

struct AuthGlassTextField: View {
    let title: String
    @Binding var text: String
    let contentType: UITextContentType?

    var body: some View {
        TextField(title, text: $text)
            .textContentType(contentType)
            .keyboardType(contentType == .emailAddress ? .emailAddress : .default)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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
}

struct AuthGlassSecureField: View {
    let title: String
    @Binding var text: String
    let contentType: UITextContentType?

    var body: some View {
        SecureField(title, text: $text)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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
}

struct AuthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IronTheme.roundedFont(.headline, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                IronTheme.terracottaPrimary.opacity(configuration.isPressed ? 0.84 : 1),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .shadow(
                color: IronTheme.terracottaPrimary.opacity(0.24),
                radius: 16,
                y: 10
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
