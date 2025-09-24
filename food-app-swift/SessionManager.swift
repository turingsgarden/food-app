import Foundation
import SwiftUI

class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var isLoggedIn = false
    @Published var userID = ""
    @Published var userName = ""
    @Published var token: String? = nil
    @Published var shouldNavigateToLogin = false
    @Published var isNewRegistration = false  // Track if user just registered
    
    private init() {
        checkLoginStatus()
    }
    
    func login(id: String, name: String, token: String, isNewUser: Bool = false) {
        isLoggedIn = true
        userID = id
        userName = name
        self.token = token
        self.isNewRegistration = isNewUser  // Set registration flag
        
        // Persist to UserDefaults
        UserDefaults.standard.set(id, forKey: "user_id")
        UserDefaults.standard.set(name, forKey: "user_name")
        UserDefaults.standard.set(token, forKey: "auth_token")
        UserDefaults.standard.set(true, forKey: "is_logged_in")
        UserDefaults.standard.set(isNewUser, forKey: "is_new_registration")  // Persist flag
        
        print("✅ User logged in: \(name) with ID: \(id)")
        print("🔐 Token stored successfully")
        print("🆕 Is new registration: \(isNewUser)")  // Log registration status
    }
    
    func checkLoginStatus() {
        if let id = UserDefaults.standard.string(forKey: "user_id"),
           let name = UserDefaults.standard.string(forKey: "user_name"),
           let token = UserDefaults.standard.string(forKey: "auth_token"),
           UserDefaults.standard.bool(forKey: "is_logged_in") {
            self.userID = id
            self.userName = name
            self.token = token
            self.isLoggedIn = true
            
            // Check registration flag from UserDefaults
            self.isNewRegistration = UserDefaults.standard.bool(forKey: "is_new_registration")
            
            print("✅ Session restored for user: \(name)")
            print("🆕 Previous registration flag: \(isNewRegistration)")
        } else {
            print("❌ No active session found")
        }
    }
    
    func logout() {
        isLoggedIn = false
        userID = ""
        userName = ""
        token = nil
        shouldNavigateToLogin = true
        isNewRegistration = false  // Clear registration flag
        
        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "user_name")
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "is_logged_in")
        UserDefaults.standard.removeObject(forKey: "is_new_registration")  // Clear from storage
        
        // Clear profile cache
        UserDefaults.standard.removeObject(forKey: "cached_user_profile")
        UserDefaults.standard.removeObject(forKey: "profile_cache_date")
        UserDefaults.standard.removeObject(forKey: "cached_profile_user_id")
        
        print("👋 User logged out")
    }
    
    func resetNavigationFlag() {
        shouldNavigateToLogin = false
    }
    
    // Helper method to get current auth token
    func getAuthToken() -> String? {
        return token ?? UserDefaults.standard.string(forKey: "auth_token")
    }
    
    // Method to clear registration flag after profile setup
    func clearNewRegistrationFlag() {
        isNewRegistration = false
        UserDefaults.standard.set(false, forKey: "is_new_registration")
        print("🔄 Cleared new registration flag")
    }
    
    // ADD THIS METHOD - Validate session
    func validateSession() -> Bool {
        // Check if token exists and is valid
        guard let token = getAuthToken(), !token.isEmpty else {
            print("❌ No auth token found")
            logout()
            return false
        }
        
        // Check if user ID exists
        guard !userID.isEmpty else {
            print("❌ No user ID found")
            logout()
            return false
        }
        
        // You could also check token expiration here if your JWT includes exp claim
        // For now, we just check if the token exists
        
        print("✅ Session validated successfully")
        return true
    }
}

func tryAutoLogin() {
    let rememberMe = UserDefaults.standard.bool(forKey: "rememberMe")
    
    if rememberMe,
       let token = KeychainHelper.shared.read(service: "auth", account: "jwt"),
       let userId = UserDefaults.standard.string(forKey: "userId"),
       let name = UserDefaults.standard.string(forKey: "userName") {
        SessionManager.shared.login(id: userId, name: name, token: token)
    }
}
