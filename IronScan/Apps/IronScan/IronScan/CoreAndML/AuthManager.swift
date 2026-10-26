import Supabase
import Foundation
import SwiftUI

enum PasswordlessContactMethod: String, CaseIterable, Identifiable {
    case email
    case phone

    var id: Self { self }

    var title: String {
        switch self {
        case .email:
            return "Email"
        case .phone:
            return "Phone"
        }
    }
}

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var currentUserId: String?
    @Published var showLogin: Bool
    @Published var hasCompletedOnboarding: Bool = false
    @Published var isCheckingOnboarding: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let defaults: UserDefaults
    private var authStateListenerTask: Task<Void, Never>?
    private static let authStateKey = "auth.isAuthenticated"
    private static let authUserIdKey = "auth.currentUserId"
    static let callbackScheme = "com.namanjain.IronScan"
    static let callbackURL = URL(string: "\(callbackScheme)://auth-callback")
        ?? URL(fileURLWithPath: "/auth-callback")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if TutorialCapture.isEnabled {
            isAuthenticated = false
            currentUserId = nil
            showLogin = false
            return
        }
        let existingSession = SupabaseManager.client.auth.currentSession
        self.isAuthenticated = existingSession != nil
        self.currentUserId = existingSession.map(Self.userIdentifier(for:)) ?? defaults.string(forKey: Self.authUserIdKey)
        self.showLogin = existingSession == nil
        observeAuthState()
    }

    deinit {
        authStateListenerTask?.cancel()
    }

    func signIn(email: String, password: String) {
        clearError()
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedEmail.contains("@"), password.count >= 6 else {
            errorMessage = "Enter a valid email and a password with at least 6 characters."
            return
        }

        isLoading = true

        Task {
            do {
                _ = try await SupabaseManager.client.auth.signIn(
                    email: cleanedEmail,
                    password: password
                )
                await applyCurrentSession(fallbackUserID: cleanedEmail.lowercased())
            } catch {
                errorMessage = friendlyMessage(for: error)
                isLoading = false
            }
        }
    }

    func signUp(email: String, password: String, age: String = "", gender: String = "") {
        clearError()
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedEmail.contains("@"), password.count >= 6 else {
            errorMessage = "Create an account with a valid email and a password with at least 6 characters."
            return
        }

        isLoading = true
        defaults.set(false, forKey: "hasCompletedOnboarding")

        Task {
            do {
                _ = try await SupabaseManager.client.auth.signUp(
                    email: cleanedEmail,
                    password: password,
                    redirectTo: Self.callbackURL
                )
                if SupabaseManager.client.auth.currentSession != nil {
                    await applyCurrentSession(fallbackUserID: cleanedEmail.lowercased())
                    statusMessage = "Account created successfully."
                } else {
                    showLogin = true
                    isLoading = false
                    statusMessage = "Account created. Check your email to confirm sign-in."
                }
            } catch {
                errorMessage = friendlyMessage(for: error)
                isLoading = false
            }
        }
    }

    func createUser(email: String, password: String, age: String, gender: String) {
        signUp(email: email, password: password, age: age, gender: gender)
    }

    func clearError() {
        errorMessage = nil
        statusMessage = nil
    }

    func signOut() {
        clearError()
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                try await SupabaseManager.client.auth.signOut()
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            applySignedOutState()
        }
    }

    func signInWithGoogle() async {
        clearError()
        isLoading = true

        do {
            _ = try await SupabaseManager.client.auth.signInWithOAuth(
                provider: Provider.google,
                redirectTo: Self.callbackURL
            )
            if SupabaseManager.client.auth.currentSession != nil {
                await applyCurrentSession()
            } else {
                statusMessage = "Continue in the Google sign-in sheet to finish authentication."
                isLoading = false
            }
        } catch {
            errorMessage = friendlyMessage(for: error)
            isLoading = false
        }
    }

    func requestOTP(for identifier: String, method: PasswordlessContactMethod) async -> Bool {
        clearError()
        let cleanedIdentifier = normalizedIdentifier(identifier, method: method)
        guard isValid(identifier: cleanedIdentifier, for: method) else {
            errorMessage = method == .email
                ? "Enter a valid email address to receive a code or magic link."
                : "Enter a valid phone number, including country code, to receive a code."
            return false
        }

        isLoading = true

        do {
            switch method {
            case .email:
                try await SupabaseManager.client.auth.signInWithOTP(
                    email: cleanedIdentifier,
                    redirectTo: Self.callbackURL
                )
                statusMessage = "Check your email for a sign-in code or magic link."
            case .phone:
                try await SupabaseManager.client.auth.signInWithOTP(phone: cleanedIdentifier)
                statusMessage = "We sent a one-time code to your phone."
            }
            isLoading = false
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            isLoading = false
            return false
        }
    }

    func verifyOTP(identifier: String, token: String, method: PasswordlessContactMethod) async -> Bool {
        clearError()
        let cleanedIdentifier = normalizedIdentifier(identifier, method: method)
        let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValid(identifier: cleanedIdentifier, for: method) else {
            errorMessage = method == .email
                ? "Enter the same email address that received the code."
                : "Enter the same phone number that received the code."
            return false
        }
        guard !cleanedToken.isEmpty else {
            errorMessage = "Enter the verification code to continue."
            return false
        }

        isLoading = true

        do {
            switch method {
            case .email:
                _ = try await SupabaseManager.client.auth.verifyOTP(
                    email: cleanedIdentifier,
                    token: cleanedToken,
                    type: EmailOTPType.email
                )
            case .phone:
                _ = try await SupabaseManager.client.auth.verifyOTP(
                    phone: cleanedIdentifier,
                    token: cleanedToken,
                    type: MobileOTPType.sms
                )
            }
            await applyCurrentSession(fallbackUserID: cleanedIdentifier.lowercased())
            statusMessage = "Verification successful."
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            isLoading = false
            return false
        }
    }

    func verifyOTP(identifier: String, code: String) async -> Bool {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let method: PasswordlessContactMethod = trimmedIdentifier.contains("@") ? .email : .phone
        return await verifyOTP(identifier: trimmedIdentifier, token: code, method: method)
    }

    func handleIncomingURL(_ url: URL) async {
        guard url.scheme?.caseInsensitiveCompare(Self.callbackScheme) == .orderedSame else { return }

        do {
            _ = try await SupabaseManager.client.auth.session(from: url)
            await applyCurrentSession()
            statusMessage = "Sign-in completed successfully."
        } catch {
            errorMessage = friendlyMessage(for: error)
            isLoading = false
        }
    }

    private func observeAuthState() {
        authStateListenerTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in SupabaseManager.client.auth.authStateChanges {
                await self.applyAuthStateChange(event: event, session: session)
            }
        }
    }

    private func applyAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated, .passwordRecovery, .mfaChallengeVerified:
            if let session {
                await applyAuthenticated(session)
            } else {
                applySignedOutState()
            }
        case .signedOut, .userDeleted:
            applySignedOutState()
        }
    }

    private func applyCurrentSession(fallbackUserID: String? = nil) async {
        if let session = SupabaseManager.client.auth.currentSession {
            await applyAuthenticated(session)
        } else if let fallbackUserID {
            currentUserId = fallbackUserID
            isAuthenticated = true
            showLogin = false
            isLoading = false
            hasCompletedOnboarding = false
            defaults.set(true, forKey: Self.authStateKey)
            defaults.set(fallbackUserID, forKey: Self.authUserIdKey)
        } else {
            isLoading = false
        }
    }

    private func applyAuthenticated(_ session: Session) async {
        currentUserId = Self.userIdentifier(for: session)
        isAuthenticated = true
        showLogin = false
        defaults.set(true, forKey: Self.authStateKey)
        defaults.set(currentUserId, forKey: Self.authUserIdKey)
        await refreshOnboardingStatus(for: session)
        isLoading = false
    }

    private func applySignedOutState() {
        currentUserId = nil
        isAuthenticated = false
        showLogin = true
        hasCompletedOnboarding = false
        isCheckingOnboarding = false
        isLoading = false
        defaults.removeObject(forKey: Self.authUserIdKey)
        defaults.set(false, forKey: Self.authStateKey)
    }

    func refreshOnboardingStatus() async {
        guard let session = SupabaseManager.client.auth.currentSession else {
            hasCompletedOnboarding = false
            return
        }
        await refreshOnboardingStatus(for: session)
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: DemographicStorageKeys.hasCompletedOnboarding)
    }

    private func refreshOnboardingStatus(for session: Session) async {
        isCheckingOnboarding = true
        defer { isCheckingOnboarding = false }

        do {
            let profileRows: [OnboardingProfileStatus] = try await SupabaseManager.client
                .from("profiles")
                .select("id")
                .eq("id", value: String(describing: session.user.id))
                .limit(1)
                .execute()
                .value

            hasCompletedOnboarding = !profileRows.isEmpty
            defaults.set(hasCompletedOnboarding, forKey: DemographicStorageKeys.hasCompletedOnboarding)
        } catch {
            hasCompletedOnboarding = false
            defaults.set(false, forKey: DemographicStorageKeys.hasCompletedOnboarding)
        }
    }

    private func normalizedIdentifier(_ identifier: String, method: PasswordlessContactMethod) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        switch method {
        case .email:
            return trimmed.lowercased()
        case .phone:
            return trimmed.replacingOccurrences(of: " ", with: "")
        }
    }

    private func isValid(identifier: String, for method: PasswordlessContactMethod) -> Bool {
        switch method {
        case .email:
            return identifier.contains("@") && identifier.contains(".")
        case .phone:
            let digits = identifier.filter(\.isNumber)
            return digits.count >= 8
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Authentication failed. Please try again." : message
    }

    private static func userIdentifier(for session: Session) -> String {
        session.user.email
            ?? session.user.phone
            ?? String(describing: session.user.id)
    }
}

private struct OnboardingProfileStatus: Decodable {
    let id: String
}
