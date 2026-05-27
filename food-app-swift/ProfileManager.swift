import Foundation
import Combine

/// Legacy profile facade — delegates all health data to ``HealthAPIManager``.
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?
    @Published var isNewUser = false

    private var retryCount = 0
    private let maxRetries = 3
    private var cancellables = Set<AnyCancellable>()

    private init() {
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
        let currentUserId = getCurrentUserId()

        guard !currentUserId.isEmpty else {
            print("❌ No user ID available for profile fetch")
            errorMessage = "No user ID available"
            isNewUser = false
            return
        }

        print("🔍 Fetching profile for user: \(currentUserId)")

        if let existingProfile = userProfile, existingProfile.user_id != currentUserId {
            print("🔄 Different user detected, clearing old profile")
            userProfile = nil
            lastSyncDate = nil
            isNewUser = false
            clearCachedProfile()
        }

        if !force,
           let profile = userProfile,
           profile.user_id == currentUserId,
           let lastSync = lastSyncDate,
           Date().timeIntervalSince(lastSync) < 300 {
            print("📱 Using cached profile for user \(currentUserId) (last sync: \(lastSync))")
            return
        }

        if isLoading && !force {
            print("⏳ Profile fetch already in progress for user \(currentUserId)")
            return
        }

        performFetch(userId: currentUserId)
    }

    func saveProfile(_ profile: UserProfile, completion: @escaping (Bool, String?) -> Void) {
        guard SessionManager.shared.getAuthToken() != nil else {
            completion(false, "Authentication required - please log in again")
            return
        }

        isLoading = true
        errorMessage = nil
        print("💾 Saving profile via health profile API for user: \(profile.user_id)")

        HealthAPIManager.shared.fetchHealthProfileOutcome(userId: profile.user_id) { [weak self] outcome in
            guard let self = self else { return }

            let existing: HealthProfile?
            switch outcome {
            case .found(let health):
                existing = health
            case .notFound:
                existing = nil
            case .failure(let message):
                self.isLoading = false
                completion(false, message)
                return
            }

            let merged = Self.mergeHealthProfile(existing: existing, with: profile)
            HealthAPIManager.shared.saveHealthProfile(merged) { success, error in
                self.isLoading = false
                if success {
                    print("✅ Profile saved successfully to health_profiles")
                    self.userProfile = profile
                    self.lastSyncDate = Date()
                    self.errorMessage = nil
                    self.isNewUser = false
                    self.cacheProfile(profile)
                    self.syncToUserDefaults(profile)
                    completion(true, nil)
                } else {
                    print("❌ Profile save failed: \(error ?? "unknown error")")
                    completion(false, error ?? "Failed to save profile")
                }
            }
        }
    }

    func clearProfile() {
        userProfile = nil
        lastSyncDate = nil
        errorMessage = nil
        retryCount = 0
        isNewUser = false
        clearCachedProfile()
        clearUserDefaults()
        print("🗑️ Profile data cleared")
    }

    // MARK: - HealthProfile ↔ UserProfile Mapping

    private static let managedDietKeys: Set<String> = [
        "vegetarian", "vegan", "keto", "gluten_free", "gluten-free"
    ]

    static func userProfile(from health: HealthProfile) -> UserProfile {
        let diet = dietaryBools(from: health.dietaryPreferences)
        return UserProfile(
            _id: nil,
            user_id: health.userId,
            age: health.age,
            gender: genderFromSex(health.sex),
            activity_level: health.activityLevel ?? "2",
            calorie_target: health.calorieTarget ?? 2200,
            is_vegetarian: diet.vegetarian,
            is_keto: diet.keto,
            is_gluten_free: diet.glutenFree,
            updated_at: nil
        )
    }

    static func mergeHealthProfile(existing: HealthProfile?, with user: UserProfile) -> HealthProfile {
        var merged = existing ?? HealthProfile(
            userId: user.user_id,
            heightCm: 170,
            weightKg: 70,
            age: user.age,
            sex: sexFromGender(user.gender),
            dietaryPreferences: [],
            allergens: []
        )

        merged.userId = user.user_id
        merged.age = user.age
        merged.sex = sexFromGender(user.gender)
        merged.activityLevel = user.activity_level
        merged.calorieTarget = user.calorie_target
        merged.dietaryPreferences = mergeDietaryPreferences(
            existing: merged.dietaryPreferences,
            user: user
        )
        return merged
    }

    private static func genderFromSex(_ sex: String) -> String {
        switch sex.lowercased() {
        case "male": return "Male"
        case "female": return "Female"
        case "other": return "Other"
        default:
            return sex.isEmpty ? "" : sex.prefix(1).uppercased() + sex.dropFirst().lowercased()
        }
    }

    private static func sexFromGender(_ gender: String) -> String {
        switch gender {
        case "Male": return "male"
        case "Female": return "female"
        case "Other": return "other"
        default: return gender.lowercased()
        }
    }

    private static func dietaryBools(from preferences: [String]) -> (vegetarian: Bool, keto: Bool, glutenFree: Bool) {
        let lower = Set(preferences.map { $0.lowercased() })
        return (
            lower.contains("vegetarian") || lower.contains("vegan"),
            lower.contains("keto"),
            lower.contains("gluten_free") || lower.contains("gluten-free")
        )
    }

    private static func mergeDietaryPreferences(existing: [String], user: UserProfile) -> [String] {
        var prefs = existing.filter { !managedDietKeys.contains($0.lowercased()) }
        if user.is_vegetarian == true { prefs.append("vegetarian") }
        if user.is_keto == true { prefs.append("keto") }
        if user.is_gluten_free == true { prefs.append("gluten_free") }
        return Array(Set(prefs))
    }

    // MARK: - Private Methods

    private func getCurrentUserId() -> String {
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
        guard SessionManager.shared.getAuthToken() != nil else {
            print("❌ No authentication token available")
            errorMessage = "Authentication required - please log in again"
            isNewUser = false
            return
        }

        isLoading = true
        errorMessage = nil
        isNewUser = false
        print("🔄 Fetching health profile for user: \(userId) (Attempt \(retryCount + 1)/\(maxRetries))")

        HealthAPIManager.shared.fetchHealthProfileOutcome(userId: userId) { [weak self] outcome in
            guard let self = self else { return }
            self.isLoading = false

            switch outcome {
            case .found(let health):
                let profile = Self.userProfile(from: health)
                print("✅ Profile loaded successfully for user \(userId)")
                print("📊 Profile data: Age=\(profile.age), Goal=\(profile.calorieTarget)kcal, Activity=\(profile.activityLevel)")
                self.userProfile = profile
                self.lastSyncDate = Date()
                self.errorMessage = nil
                self.retryCount = 0
                self.isNewUser = false
                self.cacheProfile(profile)
                self.syncToUserDefaults(profile)

            case .notFound:
                print("ℹ️ No health profile found for user \(userId) - new user detected")
                self.userProfile = nil
                self.clearCachedProfile()
                self.errorMessage = nil
                self.retryCount = 0
                self.isNewUser = true

            case .failure(let message):
                print("❌ Profile fetch error: \(message)")
                if message.contains("timeout") || message.contains("timed out") {
                    self.handleRetry(userId: userId, delay: 2, kind: "timeout")
                } else if message.contains("Server error") {
                    self.handleRetry(userId: userId, delay: 3, kind: "server")
                } else {
                    self.errorMessage = message
                    self.retryCount = 0
                    self.isNewUser = false
                }
            }
        }
    }

    private func handleRetry(userId: String, delay: TimeInterval, kind: String) {
        if retryCount < maxRetries {
            retryCount += 1
            print("🔄 \(kind) error - Retrying in \(Int(delay)) seconds (Attempt \(retryCount)/\(maxRetries))")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.performFetch(userId: userId)
            }
        } else {
            print("❌ Max retries reached for profile fetch")
            errorMessage = kind == "timeout"
                ? "Connection timeout. Please check your internet connection."
                : "Server temporarily unavailable"
            retryCount = 0
            isNewUser = false
        }
    }

    private func cacheProfile(_ profile: UserProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "cached_user_profile")
            UserDefaults.standard.set(Date(), forKey: "profile_cache_date")
            UserDefaults.standard.set(profile.user_id, forKey: "cached_profile_user_id")
            print("💾 Profile cached locally for user: \(profile.user_id)")
        }
    }

    private func clearCachedProfile() {
        UserDefaults.standard.removeObject(forKey: "cached_user_profile")
        UserDefaults.standard.removeObject(forKey: "profile_cache_date")
        UserDefaults.standard.removeObject(forKey: "cached_profile_user_id")
        print("🗑️ Cached profile cleared")
    }

    private func syncToUserDefaults(_ profile: UserProfile) {
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

// MARK: - Profile Data Model

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
