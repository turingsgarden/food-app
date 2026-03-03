import Foundation
import SwiftUI

class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var isLoggedIn = false
    @Published var userID = ""
    @Published var userName = ""
    @Published var userEmail = ""
    @Published var loginMethod = ""
    @Published var token: String? = nil
    @Published var shouldNavigateToLogin = false
    @Published var isNewRegistration = false
    
    private let sessionDuration: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    
    private init() {
        checkLoginStatus()
    }
    
    func login(id: String, name: String, email: String = "", token: String, loginMethod: String = "email", isNewUser: Bool = false) {
        isLoggedIn = true
        userID = id
        userName = name
        userEmail = email
        self.loginMethod = loginMethod
        self.token = token
        self.isNewRegistration = isNewUser
        
        let loginTimestamp = Date().timeIntervalSince1970
        
        UserDefaults.standard.set(id, forKey: "user_id")
        UserDefaults.standard.set(name, forKey: "user_name")
        UserDefaults.standard.set(email, forKey: "user_email")
        UserDefaults.standard.set(loginMethod, forKey: "login_method")
        UserDefaults.standard.set(token, forKey: "auth_token")
        UserDefaults.standard.set(true, forKey: "is_logged_in")
        UserDefaults.standard.set(isNewUser, forKey: "is_new_registration")
        UserDefaults.standard.set(loginTimestamp, forKey: "login_timestamp")
        
        // ✅ CRITICAL: Save token to NetworkManager
        NetworkManager.shared.saveToken(token)
        
        print("✅ User logged in: \(name) with ID: \(id)")
        print("📧 Email: \(email)")
        print("🔑 Method: \(loginMethod)")
        print("🔐 Token stored successfully")
        print("💾 Token saved to NetworkManager")
        print("⏰ Login will persist for 7 days from now")
        print("🆕 Is new registration: \(isNewUser)")
    }
    
    func checkLoginStatus() {
        if let id = UserDefaults.standard.string(forKey: "user_id"),
           let name = UserDefaults.standard.string(forKey: "user_name"),
           let token = UserDefaults.standard.string(forKey: "auth_token"),
           UserDefaults.standard.bool(forKey: "is_logged_in") {
            
            let loginTimestamp = UserDefaults.standard.double(forKey: "login_timestamp")
            let currentTimestamp = Date().timeIntervalSince1970
            let timeSinceLogin = currentTimestamp - loginTimestamp
            
            if timeSinceLogin > sessionDuration {
                print("⏰ Session expired (older than 7 days)")
                print("📅 Last login: \(Date(timeIntervalSince1970: loginTimestamp))")
                logout()
                return
            }
            
            let daysRemaining = Int((sessionDuration - timeSinceLogin) / (24 * 60 * 60))
            
            self.userID = id
            self.userName = name
            self.userEmail = UserDefaults.standard.string(forKey: "user_email") ?? ""
            self.loginMethod = UserDefaults.standard.string(forKey: "login_method") ?? "email"
            self.token = token
            self.isLoggedIn = true
            
            // ✅ CRITICAL: Restore token to NetworkManager
            NetworkManager.shared.saveToken(token)
            
            self.isNewRegistration = UserDefaults.standard.bool(forKey: "is_new_registration")
            
            print("✅ Session restored for user: \(name)")
            print("📧 Email: \(userEmail)")
            print("🔑 Login method: \(loginMethod)")
            print("💾 Token restored to NetworkManager")
            print("⏰ Session expires in \(daysRemaining) days")
            print("🆕 Previous registration flag: \(isNewRegistration)")
        } else {
            print("❌ No active session found")
        }
    }
    
    func logout() {
        isLoggedIn = false
        userID = ""
        userName = ""
        userEmail = ""
        loginMethod = ""
        token = nil
        shouldNavigateToLogin = true
        isNewRegistration = false
        
        UserDefaults.standard.removeObject(forKey: "user_id")
        UserDefaults.standard.removeObject(forKey: "user_name")
        UserDefaults.standard.removeObject(forKey: "user_email")
        UserDefaults.standard.removeObject(forKey: "login_method")
        UserDefaults.standard.removeObject(forKey: "auth_token")
        UserDefaults.standard.removeObject(forKey: "is_logged_in")
        UserDefaults.standard.removeObject(forKey: "is_new_registration")
        UserDefaults.standard.removeObject(forKey: "login_timestamp")
        
        UserDefaults.standard.removeObject(forKey: "cached_user_profile")
        UserDefaults.standard.removeObject(forKey: "profile_cache_date")
        UserDefaults.standard.removeObject(forKey: "cached_profile_user_id")
        
        // ✅ CRITICAL: Clear token from NetworkManager
        NetworkManager.shared.clearToken()
        
        print("👋 User logged out")
        print("🗑️ NetworkManager token cleared")
    }
    
    func resetNavigationFlag() {
        shouldNavigateToLogin = false
    }
    
    func getAuthToken() -> String? {
        return token ?? UserDefaults.standard.string(forKey: "auth_token")
    }
    
    func clearNewRegistrationFlag() {
        isNewRegistration = false
        UserDefaults.standard.set(false, forKey: "is_new_registration")
        print("🔄 Cleared new registration flag")
    }
    
    func validateSession() -> Bool {
        guard let token = getAuthToken(), !token.isEmpty else {
            print("❌ No auth token found")
            logout()
            return false
        }
        
        guard !userID.isEmpty else {
            print("❌ No user ID found")
            logout()
            return false
        }
        
        let loginTimestamp = UserDefaults.standard.double(forKey: "login_timestamp")
        let currentTimestamp = Date().timeIntervalSince1970
        let timeSinceLogin = currentTimestamp - loginTimestamp
        
        if timeSinceLogin > sessionDuration {
            print("❌ Session expired (older than 7 days)")
            logout()
            return false
        }
        
        let daysRemaining = Int((sessionDuration - timeSinceLogin) / (24 * 60 * 60))
        print("✅ Session validated successfully")
        print("⏰ Session expires in \(daysRemaining) days")
        
        return true
    }
    
    func extendSession() {
        let newTimestamp = Date().timeIntervalSince1970
        UserDefaults.standard.set(newTimestamp, forKey: "login_timestamp")
        print("🔄 Session extended - 7 more days from now")
    }
    
    func getRemainingSessionDays() -> Int {
        let loginTimestamp = UserDefaults.standard.double(forKey: "login_timestamp")
        let currentTimestamp = Date().timeIntervalSince1970
        let timeSinceLogin = currentTimestamp - loginTimestamp
        let timeRemaining = sessionDuration - timeSinceLogin
        
        return max(0, Int(timeRemaining / (24 * 60 * 60)))
    }
}
