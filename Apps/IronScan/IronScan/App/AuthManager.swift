import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool
    @Published var isLoading = false
    @Published var errorMessage: String?

    #if canImport(FirebaseAuth)
    nonisolated(unsafe) private var authStateHandle: AuthStateDidChangeListenerHandle?
    #endif

    init() {
        #if canImport(FirebaseAuth)
        let auth = Auth.auth()
        isAuthenticated = auth.currentUser != nil
        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            self?.isAuthenticated = user != nil
        }
        #else
        isAuthenticated = false
        #endif
    }

    deinit {
        #if canImport(FirebaseAuth)
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
        #endif
    }

    func signIn(email: String, password: String) {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validate(email: normalizedEmail, password: password) else { return }

        #if canImport(FirebaseAuth)
        isLoading = true
        errorMessage = nil

        Auth.auth().signIn(withEmail: normalizedEmail, password: password) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.isLoading = false

                if let error {
                    self.isAuthenticated = false
                    self.errorMessage = error.localizedDescription
                    print("Firebase sign in error: \(error.localizedDescription)")
                    return
                }

                self.errorMessage = nil
                self.isAuthenticated = result?.user != nil
            }
        }
        #else
        isLoading = false
        errorMessage = "FirebaseAuth is not linked in this target yet."
        isAuthenticated = false
        print("Firebase sign in error: FirebaseAuth is not linked in this target yet.")
        #endif
    }

    func signUp(email: String, password: String, age: String, gender: String) {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validate(email: normalizedEmail, password: password) else { return }

        #if canImport(FirebaseAuth)
        isLoading = true
        errorMessage = nil

        Auth.auth().createUser(withEmail: normalizedEmail, password: password) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    self.isLoading = false
                    self.isAuthenticated = false
                    self.errorMessage = error.localizedDescription
                    print("Firebase sign up error: \(error.localizedDescription)")
                    return
                }

                #if canImport(FirebaseFirestore)
                if let user = result?.user {
                    do {
                        try await Firestore.firestore().collection("users").document(user.uid).setData([
                            "email": normalizedEmail,
                            "age": age,
                            "gender": gender,
                            "createdAt": FieldValue.serverTimestamp()
                        ])
                    } catch {
                        self.isLoading = false
                        self.isAuthenticated = false
                        self.errorMessage = error.localizedDescription
                        print("Firebase Firestore sign up error: \(error.localizedDescription)")
                        return
                    }
                }
                #endif

                self.isLoading = false
                self.errorMessage = nil
                self.isAuthenticated = result?.user != nil
            }
        }
        #else
        isLoading = false
        errorMessage = "FirebaseAuth is not linked in this target yet."
        isAuthenticated = false
        print("Firebase sign up error: FirebaseAuth is not linked in this target yet.")
        #endif
    }

    func signOut() {
        #if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
            isAuthenticated = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            print("Firebase sign out error: \(error.localizedDescription)")
        }
        #else
        isAuthenticated = false
        print("Firebase sign out error: FirebaseAuth is not linked in this target yet.")
        #endif
    }

    func createUser(email: String, password: String, age: String, gender: String) {
        signUp(email: email, password: password, age: age, gender: gender)
    }

    func clearError() {
        errorMessage = nil
    }

    private func validate(email: String, password: String) -> Bool {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter both your email and password."
            print("Firebase auth validation error: Missing email or password.")
            return false
        }

        guard email.contains("@"), email.contains(".") else {
            errorMessage = "Please enter a valid email address."
            print("Firebase auth validation error: Invalid email address.")
            return false
        }

        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            print("Firebase auth validation error: Password too short.")
            return false
        }

        return true
    }
}
