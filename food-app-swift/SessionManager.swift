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
        
        // Store login timestamp for 30-day session persistence
        UserDefaults.standard.set(Date(), forKey: "login_timestamp")
        UserDefaults.standard.set(Date(), forKey: "last_activity_time")
        
        print("✅ User logged in: \(name) with ID: \(id)")
        print("🔐 Token stored successfully")
        print("📅 Login timestamp saved for 30-day persistence")
        print("🆕 Is new registration: \(isNewUser)")  // Log registration status
    }
    
    func checkLoginStatus() {
        if let id = UserDefaults.standard.string(forKey: "user_id"),
           let name = UserDefaults.standard.string(forKey: "user_name"),
           let token = UserDefaults.standard.string(forKey: "auth_token"),
           UserDefaults.standard.bool(forKey: "is_logged_in") {
            
            // Check if session has expired (30 days of inactivity)
            if isSessionExpired() {
                print("⏰ Session expired due to 30 days of inactivity")
                logout()
                return
            }
            
            self.userID = id
            self.userName = name
            self.token = token
            self.isLoggedIn = true
            
            // Check registration flag from UserDefaults
            self.isNewRegistration = UserDefaults.standard.bool(forKey: "is_new_registration")
            
            // Update last activity time
            UserDefaults.standard.set(Date(), forKey: "last_activity_time")
            
            print("✅ Session restored for user: \(name)")
            print("📅 Session still valid (within 30-day window)")
            print("🆕 Previous registration flag: \(isNewRegistration)")
        } else {
            print("❌ No active session found")
        }
    }
    
    // Check if session has exceeded 30-day inactivity limit
    private func isSessionExpired() -> Bool {
        guard let lastActivity = UserDefaults.standard.object(forKey: "last_activity_time") as? Date else {
            // If no last activity recorded, check login timestamp
            guard let loginTime = UserDefaults.standard.object(forKey: "login_timestamp") as? Date else {
                return false // No timestamps, session is valid (legacy support)
            }
            let daysSinceLogin = Date().timeIntervalSince(loginTime) / 86400
            return daysSinceLogin > 30
        }
        
        let daysSinceActivity = Date().timeIntervalSince(lastActivity) / 86400
        return daysSinceActivity > 30
    }
    
    func logout() {
        isLoggedIn = false
        userID = ""
        userName = ""
        token = nil
        shouldNavigateToLogin = true
        isNewRegistration = false  // Clear registration flag
        
        // Clear UserDefaults - session data
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "user_name")
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "is_logged_in")
        UserDefaults.standard.removeObject(forKey: "is_new_registration")
        
        // Clear session timestamps
        UserDefaults.standard.removeObject(forKey: "login_timestamp")
        UserDefaults.standard.removeObject(forKey: "last_activity_time")
        
        // Clear profile cache
        UserDefaults.standard.removeObject(forKey: "cached_user_profile")
        UserDefaults.standard.removeObject(forKey: "profile_cache_date")
        UserDefaults.standard.removeObject(forKey: "cached_profile_user_id")
        
        // Clear NetworkManager token
        NetworkManager.shared.clearToken()
        
        print("👋 User logged out - all session data cleared")
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
    
    // Validate session - checks token and 30-day expiry
    func validateSession() -> Bool {
        // Check if session is expired (30 days inactivity)
        if isSessionExpired() {
            print("❌ Session expired due to inactivity")
            logout()
            return false
        }
        
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
        
        // Update last activity timestamp
        updateLastActivity()
        
        print("✅ Session validated successfully")
        return true
    }
    
    // Update last activity timestamp - call this on user interactions
    func updateLastActivity() {
        UserDefaults.standard.set(Date(), forKey: "last_activity_time")
    }
    
    // Get days until session expires
    func daysUntilSessionExpires() -> Int {
        guard let lastActivity = UserDefaults.standard.object(forKey: "last_activity_time") as? Date else {
            return 30 // Default to full 30 days if no activity recorded
        }
        let daysSinceActivity = Date().timeIntervalSince(lastActivity) / 86400
        return max(0, 30 - Int(daysSinceActivity))
    }
}
