import SwiftUI
import UIKit

struct AuthView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var passwordlessContactMethod: PasswordlessContactMethod = .email
    @State private var passwordlessIdentifier = ""
    @State private var showOTPField = false
    @State private var otpCode = ""

    private var isSignupMode: Bool {
        !authManager.showLogin
    }

    private var cardTitle: String {
        isSignupMode ? "Create your IronScan account" : "Welcome back to IronScan"
    }

    private var cardSubtitle: String {
        isSignupMode
            ? "Use a one-time code or Google to join the research prototype."
            : "Use a one-time code or Google to continue into the research prototype."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IronScreenBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        Spacer(minLength: 36)

                        Image("ironscan_icon_only_transparent")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .accessibilityHidden(true)

                        VStack(spacing: 8) {
                            Text("Welcome to IronScan")
                                .font(IronTheme.roundedFont(.largeTitle, weight: .bold))
                                .foregroundStyle(IronTheme.textPrimary)

                            Text("A lightweight sign-in built for the non-clinical research prototype.")
                                .font(IronTheme.roundedFont(.subheadline))
                                .foregroundStyle(IronTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 18) {
                            Picker("Authentication Mode", selection: Binding(
                                get: { isSignupMode },
                                set: { newValue in
                                    if newValue != isSignupMode {
                                        toggleMode()
                                    }
                                }
                            )) {
                                Text("Log In").tag(false)
                                Text("Sign Up").tag(true)
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading, spacing: 8) {
                                Text(cardTitle)
                                    .font(IronTheme.roundedFont(.title2, weight: .bold))
                                    .foregroundStyle(IronTheme.textPrimary)

                                Text(cardSubtitle)
                                    .font(IronTheme.roundedFont(.subheadline))
                                    .foregroundStyle(IronTheme.textSecondary)
                            }

                            Picker("Contact Method", selection: $passwordlessContactMethod) {
                                ForEach(PasswordlessContactMethod.allCases) { method in
                                    Text(method.title).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)

                            AuthGlassTextField(
                                title: passwordlessContactMethod == .email ? "Email Address" : "Phone Number",
                                text: $passwordlessIdentifier,
                                contentType: passwordlessContactMethod == .email ? .emailAddress : .telephoneNumber,
                                keyboardType: passwordlessContactMethod == .email ? .emailAddress : .phonePad
                            )

                            if showOTPField {
                                AuthGlassTextField(
                                    title: "6-digit code",
                                    text: $otpCode,
                                    contentType: .oneTimeCode,
                                    keyboardType: .numberPad
                                )

                                Button {
                                    Task {
                                        let didVerify = await authManager.verifyOTP(
                                            identifier: passwordlessIdentifier,
                                            code: otpCode
                                        )
                                        if didVerify {
                                            otpCode = ""
                                            showOTPField = false
                                        }
                                    }
                                } label: {
                                    Text(authManager.isLoading ? "Verifying..." : "Verify Code")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(OrganicPrimaryButtonStyle())
                                .disabled(authManager.isLoading)
                            } else {
                                Button {
                                    Task {
                                        let didSend = await authManager.requestOTP(
                                            for: passwordlessIdentifier,
                                            method: passwordlessContactMethod
                                        )
                                        if didSend {
                                            showOTPField = true
                                        }
                                    }
                                } label: {
                                    Text(authManager.isLoading ? "Sending..." : "Send Code")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(OrganicPrimaryButtonStyle())
                                .disabled(authManager.isLoading)
                            }

                            if let statusMessage = authManager.statusMessage {
                                Text(statusMessage)
                                    .font(IronTheme.roundedFont(.footnote, weight: .semibold))
                                    .foregroundStyle(IronTheme.sageAccent)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if let errorMessage = authManager.errorMessage {
                                Text(errorMessage)
                                    .font(IronTheme.roundedFont(.footnote, weight: .semibold))
                                    .foregroundStyle(IronTheme.warning)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            HStack {
                                Rectangle()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(height: 1)
                                Text("Or continue with...")
                                    .font(IronTheme.roundedFont(.caption, weight: .bold))
                                    .foregroundStyle(IronTheme.textSecondary)
                                Rectangle()
                                    .fill(Color.white.opacity(0.28))
                                    .frame(height: 1)
                            }

                            HStack {
                                Spacer()
                                Button {
                                    Task {
                                        await authManager.signInWithGoogle()
                                    }
                                } label: {
                                    Text("G")
                                        .font(IronTheme.roundedFont(.title3, weight: .bold))
                                        .foregroundStyle(IronTheme.textPrimary)
                                        .frame(width: 52, height: 52)
                                        .background(.ultraThinMaterial, in: Circle())
                                        .overlay {
                                            Circle()
                                                .stroke(Color.white.opacity(0.8), lineWidth: 0.8)
                                        }
                                }
                                .accessibilityLabel(authManager.isLoading ? "Connecting to Google" : "Continue with Google")
                                .disabled(authManager.isLoading)
                                Spacer()
                            }
                        }
                        .padding(28)
                        .frame(maxWidth: 560)
                        .modifier(LiquidGlassCardStyle(cornerRadius: 32))
                        .padding(.horizontal, 20)

                        Text(isSignupMode ? "Signing up with a code will create your account after verification." : "Use the same email or phone number that received your code.")
                            .font(IronTheme.roundedFont(.footnote))
                            .foregroundStyle(IronTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .frame(maxWidth: 560)

                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(IronTheme.beigeBackground.ignoresSafeArea())
        }
        .tint(IronTheme.terracottaPrimary)
        .organicTypography()
        .onChange(of: passwordlessContactMethod) { _, _ in
            otpCode = ""
            showOTPField = false
            authManager.clearError()
        }
        .onChange(of: passwordlessIdentifier) { _, _ in
            if showOTPField {
                otpCode = ""
                showOTPField = false
            }
        }
    }

    private func toggleMode() {
        authManager.clearError()
        authManager.showLogin.toggle()
        otpCode = ""
        showOTPField = false
    }
}

struct LoginView: View {
    var body: some View {
        AuthView()
    }
}

struct AuthGlassTextField: View {
    let title: String
    @Binding var text: String
    let contentType: UITextContentType?
    let keyboardType: UIKeyboardType

    var body: some View {
        TextField(title, text: $text)
            .textContentType(contentType)
            .keyboardType(keyboardType)
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
