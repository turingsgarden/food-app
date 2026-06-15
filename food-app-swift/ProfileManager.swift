import Foundation
import Combine

class ProfileManager: ObservableObject {
    static let shared = ProfileManager()
    
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    @Published var isNewUser = false  // NEW: Track if this is a new user without profile
    
    private let baseURL = AppConfig.apiBaseURL
    private var cancellables = Set<AnyCancellable>()
    private var currentFetchTask: URLSessionDataTask?
    private var retryCount = 0
    private let maxRetries = 3
    
    private init() {
        // Listen for login changes
        SessionManager.shared.$isLoggedIn
            .sink { [weak self] isLoggedIn in
                if isLoggedIn {
                    print("👤 User logged in, clearing old profile and fetching new one")
                    self?.clearProfile()
                    self?.fetchProfile(force: true)
                } else {
                    print("👤 User logged out, clearing profile")
                    self?.clearProfile()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func fetchProfile(force: Bool = false) {
        // Get current user ID
        let currentUserId = getCurrentUserId()
        
        guard !currentUserId.isEmpty else {
            print("❌ No user ID available for profile fetch")
            errorMessage = "No user ID available"
            isNewUser = false
            return
        }
        
        print("🔍 Fetching profile for user: \(currentUserId)")
        
        // Cancel any existing request
        currentFetchTask?.cancel()
        
        // Clear old profile if it's for a different user
        if let existingProfile = userProfile, existingProfile.user_id != currentUserId {
            print("🔄 Different user detected, clearing old profile")
            userProfile = nil
            lastSyncDate = nil
            isNewUser = false
            clearCachedProfile()
        }
        
        // Skip if recently fetched unless forced
        if !force,
           let profile = userProfile,
           profile.user_id == currentUserId,
           let lastSync = lastSyncDate,
           Date().timeIntervalSince(lastSync) < 300 { // 5 minutes cache
            print("📱 Using cached profile for user \(currentUserId) (last sync: \(lastSync))")
            return
        }
        
        // Skip if already loading for same user
        if isLoading && !force {
            print("⏳ Profile fetch already in progress for user \(currentUserId)")
            return
        }
        
        performFetch(userId: currentUserId)
    }
    
    private func getCurrentUserId() -> String {
        // Priority: SessionManager first, then UserDefaults
        if !SessionManager.shared.userID.isEmpty {
            return SessionManager.shared.userID
        }
        
        if let userDefaultsId = UserDefaults.standard.string(forKey: "user_id"),
           !userDefaultsId.isEmpty {
            return userDefaultsId
        }
        
        return ""
    }
    
    private func performFetch(userId: String) {
        guard let url = URL(string: "\(baseURL)/get-profile?user_id=\(userId)") else {
            print("❌ Invalid profile URL")
            errorMessage = "Invalid URL"
            isNewUser = false
            return
        }
        
        // Get the JWT token
        guard let token = SessionManager.shared.getAuthToken() else {
            print("❌ No authentication token available")
            errorMessage = "Authentication required - please log in again"
            isNewUser = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        isNewUser = false  // Reset state
        print("🔄 Fetching profile from MongoDB for user: \(userId) (Attempt \(retryCount + 1)/\(maxRetries))")
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add JWT token to Authorization header
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        currentFetchTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error as NSError? {
                    print("❌ Profile fetch error: \(error.localizedDescription)")
                    
                    if error.code == NSURLErrorTimedOut {
                        self?.handleTimeout(userId: userId)
                    } else if error.code == NSURLErrorCancelled {
                        print("🚫 Profile fetch cancelled")
                        return
                    } else {
                        self?.errorMessage = "Network error: \(error.localizedDescription)"
                        self?.retryCount = 0
                        self?.isNewUser = false
                    }
                    return
                }
                
                guard let data = data else {
                    print("❌ No profile data received")
                    self?.errorMessage = "No data received"
                    self?.isNewUser = false
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Profile fetch status: \(httpResponse.statusCode)")
                    
                    switch httpResponse.statusCode {
                    case 200:
                        self?.handleSuccessfulResponse(data: data, userId: userId)
                        self?.isNewUser = false
                    case 401:
                        print("❌ Unauthorized - token may be expired")
                        self?.errorMessage = "Session expired - please log in again"
                        self?.retryCount = 0
                        self?.isNewUser = false
                        // Could trigger logout here if needed
                    case 404:
                        // This is EXPECTED for new users - not an error!
                        print("ℹ️ No profile found for user \(userId) - new user detected")
                        self?.userProfile = nil
                        self?.clearCachedProfile()
                        self?.errorMessage = nil  // Don't show error for new users
                        self?.retryCount = 0
                        self?.isNewUser = true  // Mark as new user
                    case 500...599:
                        self?.handleServerError(userId: userId)
                        self?.isNewUser = false
                    default:
                        print("❌ Profile fetch failed with status: \(httpResponse.statusCode)")
                        self?.errorMessage = "Server error (\(httpResponse.statusCode))"
                        self?.retryCount = 0
                        self?.isNewUser = false
                    }
                } else {
                    self?.errorMessage = "Invalid response"
                    self?.isNewUser = false
                }
            }
        }
        
        currentFetchTask?.resume()
    }
    
    private func handleSuccessfulResponse(data: Data, userId: String) {
        do {
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            print("✅ Profile loaded successfully for user \(userId)")
            print("📊 Profile data: Age=\(profile.age), Goal=\(profile.calorieTarget)kcal, Activity=\(profile.activityLevel)")
            
            // Always replace the profile, don't merge
            self.userProfile = profile
            self.lastSyncDate = Date()
            self.errorMessage = nil
            self.retryCount = 0
            self.isNewUser = false  // Not a new user anymore
            
            // Cache the new profile
            self.cacheProfile(profile)
            self.syncToUserDefaults(profile)
            
        } catch {
            print("❌ Profile decode error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📄 Raw response: \(jsonString)")
            }
            self.errorMessage = "Data parsing error"
            self.isNewUser = false
        }
    }
    
    private func handleTimeout(userId: String) {
        if retryCount < maxRetries {
            retryCount += 1
            print("⏰ Timeout - Retrying in 2 seconds (Attempt \(retryCount)/\(maxRetries))")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.performFetch(userId: userId)
            }
        } else {
            print("❌ Max retries reached for profile fetch")
            errorMessage = "Connection timeout. Please check your internet connection."
            retryCount = 0
            isNewUser = false
        }
    }
    
    private func handleServerError(userId: String) {
        if retryCount < maxRetries {
            retryCount += 1
            print("🔄 Server error - Retrying in 3 seconds (Attempt \(retryCount)/\(maxRetries))")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.performFetch(userId: userId)
            }
        } else {
            print("❌ Max retries reached for server error")
            errorMessage = "Server temporarily unavailable"
            retryCount = 0
            isNewUser = false
        }
    }
    
    func saveProfile(_ profile: UserProfile, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/save-profile") else {
            completion(false, "Invalid URL")
            return
        }
        
        // Get the JWT token
        guard let token = SessionManager.shared.getAuthToken() else {
            completion(false, "Authentication required - please log in again")
            return
        }
        
        isLoading = true
        errorMessage = nil
        print("💾 Saving profile to MongoDB for user: \(profile.user_id)")
        
        // Create payload matching backend expectations
        let payload: [String: Any] = [
            "user_id": profile.user_id,
            "age": profile.age,
            "gender": profile.gender,
            "activity_level": profile.activity_level,
            "calorie_target": profile.calorie_target,
            "is_vegetarian": profile.is_vegetarian ?? false,
            "is_keto": profile.is_keto ?? false,
            "is_gluten_free": profile.is_gluten_free ?? false
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            isLoading = false
            completion(false, "Failed to encode profile data")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add JWT token to Authorization header
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = jsonData
        request.timeoutInterval = 45
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("❌ Profile save error: \(error.localizedDescription)")
                    completion(false, error.localizedDescription)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 Profile save status: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode == 200 {
                        print("✅ Profile saved successfully to MongoDB")
                        
                        // Update local state immediately - REPLACE, don't merge
                        self?.userProfile = profile
                        self?.lastSyncDate = Date()
                        self?.errorMessage = nil
                        self?.isNewUser = false  // Not a new user anymore
                        self?.cacheProfile(profile)
                        self?.syncToUserDefaults(profile)
                        
                        completion(true, nil)
                    } else if httpResponse.statusCode == 401 {
                        print("❌ Unauthorized - token may be expired")
                        completion(false, "Session expired - please log in again")
                    } else {
                        var errorMessage = "Failed to save profile"
                        
                        if let data = data,
                           let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = errorDict["error"] as? String {
                            errorMessage = message
                        }
                        
                        print("❌ Profile save failed: \(errorMessage)")
                        completion(false, errorMessage)
                    }
                } else {
                    completion(false, "No response from server")
                }
            }
        }.resume()
    }
    
    func clearProfile() {
        currentFetchTask?.cancel()
        userProfile = nil
        lastSyncDate = nil
        errorMessage = nil
        retryCount = 0
        isNewUser = false
        clearCachedProfile()
        clearUserDefaults()
        print("🗑️ Profile data cleared")
    }
    
    // MARK: - Private Methods
    
    private func cacheProfile(_ profile: UserProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "cached_user_profile")
            UserDefaults.standard.set(Date(), forKey: "profile_cache_date")
            UserDefaults.standard.set(profile.user_id, forKey: "cached_profile_user_id")
            print("💾 Profile cached locally for user: \(profile.user_id)")
        }
    }
    
    private func loadCachedProfile() {
        let currentUserId = getCurrentUserId()
        
        guard !currentUserId.isEmpty,
              let data = UserDefaults.standard.data(forKey: "cached_user_profile"),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data),
              let cachedUserId = UserDefaults.standard.string(forKey: "cached_profile_user_id") else {
            return
        }
        
        // Only load if it's for the current user
        guard cachedUserId == currentUserId else {
            print("🗑️ Cached profile is for different user, clearing")
            clearCachedProfile()
            return
        }
        
        // Check cache age (max 1 hour)
        if let cacheDate = UserDefaults.standard.object(forKey: "profile_cache_date") as? Date,
           Date().timeIntervalSince(cacheDate) < 3600 {
            self.userProfile = profile
            self.lastSyncDate = cacheDate
            self.isNewUser = false
            print("📱 Loaded cached profile for user \(currentUserId) (cached: \(cacheDate))")
        } else {
            print("⏰ Cached profile expired, will fetch fresh data")
            clearCachedProfile()
        }
    }
    
    private func clearCachedProfile() {
        UserDefaults.standard.removeObject(forKey: "cached_user_profile")
        UserDefaults.standard.removeObject(forKey: "profile_cache_date")
        UserDefaults.standard.removeObject(forKey: "cached_profile_user_id")
        print("🗑️ Cached profile cleared")
    }
    
    private func syncToUserDefaults(_ profile: UserProfile) {
        // Sync essential data to UserDefaults for backward compatibility
        UserDefaults.standard.set(profile.calorie_target, forKey: "calorie_target")
        UserDefaults.standard.set(profile.age, forKey: "user_age")
        UserDefaults.standard.set(profile.gender, forKey: "user_gender")
        UserDefaults.standard.set(profile.activity_level, forKey: "user_activity_level")
        print("🔄 Profile synced to UserDefaults for user: \(profile.user_id)")
    }
    
    private func clearUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "calorie_target")
        UserDefaults.standard.removeObject(forKey: "user_age")
        UserDefaults.standard.removeObject(forKey: "user_gender")
        UserDefaults.standard.removeObject(forKey: "user_activity_level")
    }
}

// MARK: - Profile Data Model (keep existing)

struct UserProfile: Codable, Identifiable, Equatable {
    let _id: String?
    let user_id: String
    let age: Int
    let gender: String
    let activity_level: String
    let calorie_target: Int
    let is_vegetarian: Bool?
    let is_keto: Bool?
    let is_gluten_free: Bool?
    let updated_at: String?
    
    var id: String { user_id }
    
    var activityLevel: String {
        return activity_level
    }
    
    var calorieTarget: Int {
        return calorie_target
    }
    
    var dietaryPreferencesText: String {
        var preferences: [String] = []
        if is_vegetarian == true { preferences.append("Vegetarian") }
        if is_keto == true { preferences.append("Keto") }
        if is_gluten_free == true { preferences.append("Gluten-Free") }
        return preferences.isEmpty ? "None" : preferences.joined(separator: ", ")
    }
    
    func activityLevelText() -> String {
        switch activity_level {
        case "1": return "Sedentary"
        case "2": return "Lightly Active"
        case "3": return "Active"
        case "4": return "Very Active"
        default: return "Unknown"
        }
    }
    
    // MARK: - Equatable Conformance
    static func == (lhs: UserProfile, rhs: UserProfile) -> Bool {
        return lhs.user_id == rhs.user_id &&
               lhs.age == rhs.age &&
               lhs.gender == rhs.gender &&
               lhs.activity_level == rhs.activity_level &&
               lhs.calorie_target == rhs.calorie_target &&
               lhs.is_vegetarian == rhs.is_vegetarian &&
               lhs.is_keto == rhs.is_keto &&
               lhs.is_gluten_free == rhs.is_gluten_free
    }
}
