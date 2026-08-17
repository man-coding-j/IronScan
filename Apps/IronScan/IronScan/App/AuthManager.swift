import Foundation
import SwiftUI

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = true
    @Published var currentUserId: String? = "supabase-test-user-id"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    init() {
        // Firebase Auth has been purged.
        // Supabase Auth can be implemented here later if needed.
    }
    
    func signIn(email: String, password: String) {
        errorMessage = nil
        isAuthenticated = true
    }

    func signUp(email: String, password: String, age: String, gender: String) {
        errorMessage = nil
        isAuthenticated = true
    }

    func createUser(email: String, password: String, age: String, gender: String) {
        signUp(email: email, password: password, age: age, gender: gender)
    }

    func clearError() {
        errorMessage = nil
    }
    
    func signOut() {
        isAuthenticated = false
        currentUserId = nil
    }
}
