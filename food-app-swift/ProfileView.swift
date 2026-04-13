// ProfileView.swift — 统一黑白风格 + Edit Profile 接入 HealthProfileView
// 改动：showEditProfile sheet 从旧 ProfileSetupView → HealthProfileView(existingProfile:)

import SwiftUI
import StoreKit

struct ProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var showLogoutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteConfirmation = false
    @State private var isLoggingOut = false
    @State private var isDeletingAccount = false
    @State private var showEditProfile = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @State private var showHelpSupport = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var isSavingName = false
    @State private var nameError = ""

    var userName: String { session.userName.isEmpty ? "User" : session.userName }

    var body: some View {
        NavigationView {
            ZStack {
                themeManager.current.background.ignoresSafeArea()
                if profileManager.isLoading && profileManager.userProfile == nil && !hasAppeared {
                    loadingView
                } else {
                    scrollContent
                }
                if isDeletingAccount { deletionOverlay }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear { if !hasAppeared { hasAppeared = true; profileManager.fetchProfile(force: false) } }
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) { performLogout() }
            } message: { Text("Are you sure you want to logout?") }
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { showDeleteConfirmation = true }
            } message: { Text("This will permanently delete all your data. This action cannot be undone.") }
            .alert("Final Confirmation", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Forever", role: .destructive) { performAccountDeletion() }
            } message: { Text("All your data will be lost forever.") }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            .alert("Help & Support", isPresented: $showHelpSupport) {
                Button("Contact Support") { openEmailSupport() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("For support, contact us at support@nutricam.com") }
            // ✅ 用 HealthProfileView 替代旧的 ProfileSetupView
            .sheet(isPresented: $showEditProfile) {
                HealthProfileView(
                    existingProfile: healthProfileFromUserProfile(),
                    onComplete: { savedProfile in
                        // 同时更新 HealthAPI 侧的档案
                        HealthAPIManager.shared.saveHealthProfile(savedProfile) { _, _ in }
                        profileManager.fetchProfile(force: true)
                    }
                )
                .environmentObject(themeManager)
                .onDisappear { profileManager.fetchProfile(force: true) }
            }
            .refreshable { await refreshProfile() }
        }
    }

    // ✅ 把 ProfileManager 的 UserProfile 转成 HealthProfile 用于预填充
    func healthProfileFromUserProfile() -> HealthProfile? {
        guard profileManager.userProfile != nil else { return nil }
        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID
        // ✅ UserProfile 没有 height/weight/dietaryPreferences，用默认值
        // HealthProfileView 打开后用户可以自行填写
        return HealthProfile(
            userId: userId,
            heightCm: 170,
            weightKg: 70,
            age: profileManager.userProfile?.age ?? 25,
            sex: profileManager.userProfile?.gender.lowercased() ?? "other",
            systolicBP: nil, diastolicBP: nil,
            fastingBloodSugar: nil, totalCholesterol: nil, triglycerides: nil,
            dietaryPreferences: [],
            allergens: []
        )
    }

    // MARK: - Loading

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText))
                .scaleEffect(1.3)
            Text("Loading profile…").font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
        }
    }

    // MARK: - Scroll Content

    var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                avatarSection.padding(.top, 8)
                if let profile = profileManager.userProfile {
                    statsSection(profile: profile)
                    settingsSection(profile: profile)
                } else {
                    setupPrompt
                }
                accountSection
                appInfo
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { profileManager.fetchProfile(force: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
        }
    }

    // MARK: - Avatar

    var avatarSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(themeManager.current.inputBackground)
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(themeManager.current.cardBorder, lineWidth: 1.5))
                Text(String(userName.prefix(1)).uppercased())
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
            }

            VStack(spacing: 8) {
                if isEditingName {
                    VStack(spacing: 10) {
                        TextField("Enter new name", text: $editedName)
                            .font(.system(size: 15)).foregroundColor(themeManager.current.primaryText)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(themeManager.current.inputBackground).cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeManager.current.cardBorder, lineWidth: 1))

                        if !nameError.isEmpty {
                            Text(nameError).font(.caption).foregroundColor(.red)
                        }

                        HStack(spacing: 12) {
                            Button("Cancel") { isEditingName = false; nameError = "" }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeManager.current.secondaryText)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(themeManager.current.inputBackground).cornerRadius(10)

                            Button(action: saveName) {
                                Group {
                                    if isSavingName {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(
                                            tint: themeManager.current == .dark ? .black : .white)).scaleEffect(0.8)
                                    } else { Text("Save") }
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.current == .dark ? .black : .white)
                                .padding(.horizontal, 20).padding(.vertical, 8)
                                .background(themeManager.current == .dark ? Color.white : Color.black).cornerRadius(10)
                            }
                            .disabled(isSavingName)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    HStack(spacing: 8) {
                        Text(userName)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                        Button(action: { editedName = session.userName; nameError = ""; isEditingName = true }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                    }
                }

                if let profile = profileManager.userProfile {
                    Text("\(profile.age) years old • \(profile.gender)")
                        .font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
                    if let lastSync = profileManager.lastSyncDate {
                        Text("Synced \(formatSyncDate(lastSync))")
                            .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText.opacity(0.6))
                    }
                }

                Button(action: { showEditProfile = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: profileManager.userProfile != nil ? "pencil" : "person.fill.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(profileManager.userProfile != nil ? "Edit Profile" : "Set Up Profile")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(themeManager.current == .dark ? Color.white : Color.black)
                    .cornerRadius(20)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Stats

    func statsSection(profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            profileStatCell(icon: "flame.fill", value: "\(profile.calorieTarget)", unit: "kcal",
                            label: "Daily Goal", color: Color(red: 0.95, green: 0.61, blue: 0.20))
            profileStatCell(icon: "figure.run", value: profile.activityLevelShort(), unit: "",
                            label: "Activity", color: Color(red: 0.35, green: 0.62, blue: 0.93))
        }
    }

    func profileStatCell(icon: String, value: String, unit: String, label: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundColor(color)
            VStack(spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(themeManager.current.primaryText)
                    if !unit.isEmpty { Text(unit).font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText) }
                }
                Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(themeManager.current.secondaryText)
                    .textCase(.uppercase).tracking(0.3)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    // MARK: - Settings

    func settingsSection(profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Settings")
            VStack(spacing: 0) {
                profileRow(icon: "person.fill", label: "Personal Info",
                           detail: "\(profile.age)y • \(profile.gender)") { showEditProfile = true }
                rowDivider
                profileRow(icon: "target", label: "Nutrition Goals",
                           detail: "\(profile.calorieTarget) kcal") { showEditProfile = true }
                rowDivider
                profileRow(icon: "leaf.fill", label: "Dietary Preferences",
                           detail: profile.dietaryPreferencesText.isEmpty ? "None" : profile.dietaryPreferencesText) { showEditProfile = true }
                rowDivider
                appearanceRow
                rowDivider
                profileRow(icon: "star.fill", label: "Rate NutriCam",
                           detail: "Leave us a review") { rateApp() }
                rowDivider
                profileRow(icon: "questionmark.circle.fill", label: "Help & Support",
                           detail: "FAQ and contact") { showHelpSupport = true }
            }
            .background(themeManager.current.cardBackground).cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
        }
    }

    var appearanceRow: some View {
        HStack(spacing: 14) {
            Image(systemName: themeManager.current == .dark ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(themeManager.current.primaryText).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Appearance").font(.system(size: 15, weight: .medium)).foregroundColor(themeManager.current.primaryText)
                Text(themeManager.current == .dark ? "Dark Mode" : "Light Mode")
                    .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
            }
            Spacer()
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    themeManager.current = themeManager.current == .dark ? .light : .dark
                }
            }) {
                ZStack {
                    Capsule()
                        .fill(themeManager.current == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        .frame(width: 52, height: 28)
                        .overlay(Capsule().stroke(themeManager.current.cardBorder, lineWidth: 1))
                    HStack {
                        if themeManager.current == .light { Spacer() }
                        Circle().fill(themeManager.current == .dark ? Color.white : Color.black)
                            .frame(width: 22, height: 22).padding(3)
                        if themeManager.current == .dark { Spacer() }
                    }
                    .frame(width: 52)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - Account

    var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Account")
            VStack(spacing: 0) {
                Button(action: { showLogoutAlert = true }) {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.right.square.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.red).frame(width: 22)
                        Text("Logout").font(.system(size: 15, weight: .medium)).foregroundColor(.red)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider().background(themeManager.current.cardBorder).padding(.leading, 52)

                Button(action: { showDeleteAccountAlert = true }) {
                    HStack(spacing: 14) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold)).foregroundColor(.red).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete Account").font(.system(size: 15, weight: .medium)).foregroundColor(.red)
                            Text("Permanently removes all data").font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .background(themeManager.current.cardBackground).cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.red.opacity(0.15), lineWidth: 1))
        }
    }

    var appInfo: some View {
        VStack(spacing: 4) {
            Text("NutriSnap").font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.6))
            Text("Version 1.0.0").font(.system(size: 11))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
        }
        .padding(.top, 8)
    }

    var setupPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 44)).foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            VStack(spacing: 6) {
                Text("Profile not set up").font(.system(size: 17, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Text("Set up your profile to get personalized nutrition goals")
                    .font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText).multilineTextAlignment(.center)
            }
            Button(action: { showEditProfile = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Set Up Now")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(themeManager.current == .dark ? .black : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(themeManager.current == .dark ? Color.white : Color.black).cornerRadius(14)
            }
            .padding(.horizontal, 20)
        }
        .padding(24).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    var deletionOverlay: some View {
        Color.black.opacity(0.5).ignoresSafeArea()
            .overlay(VStack(spacing: 16) {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.4)
                Text("Deleting account…").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
            }
            .padding(32).background(Color.black.opacity(0.7)).cornerRadius(20))
    }

    // MARK: - Row Components

    func profileRow(icon: String, label: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 15, weight: .medium)).foregroundColor(themeManager.current.primaryText)
                    Text(detail).font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            }
            .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var rowDivider: some View {
        Divider().background(themeManager.current.cardBorder).padding(.leading, 52)
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(themeManager.current.secondaryText)
            .textCase(.uppercase).tracking(0.5).padding(.horizontal, 4)
    }

    // MARK: - Actions

    func formatSyncDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    func refreshProfile() async {
        await withCheckedContinuation { continuation in
            profileManager.fetchProfile(force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { continuation.resume() }
        }
    }

    func performLogout() { profileManager.clearProfile(); session.logout(); dismiss() }

    func performAccountDeletion() {
        isDeletingAccount = true
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/delete_account") else {
            isDeletingAccount = false; errorMessage = "Server error"; showErrorAlert = true; return
        }
        var request = URLRequest(url: url); request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = session.getAuthToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.isDeletingAccount = false
                if error != nil { self.errorMessage = "Network error."; self.showErrorAlert = true; return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.profileManager.clearProfile(); self.session.logout(); self.dismiss()
                } else {
                    self.errorMessage = "Failed to delete account. Please contact support."; self.showErrorAlert = true
                }
            }
        }.resume()
    }

    func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { nameError = "Name must be at least 2 characters"; return }
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/update_name") else { nameError = "Server error"; return }
        isSavingName = true; nameError = ""
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = session.getAuthToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": trimmed])
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.isSavingName = false
                if error != nil { self.nameError = "Network error"; return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.session.userName = trimmed; self.isEditingName = false; self.profileManager.fetchProfile(force: true)
                } else { self.nameError = "Failed to update name" }
            }
        }.resume()
    }

    func openEmailSupport() {
        if let url = URL(string: "mailto:support@nutricam.com?subject=NutriCam%20Support%20Request") {
            UIApplication.shared.open(url)
        }
    }

    func rateApp() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            AppStore.requestReview(in: windowScene)
        }
    }
}

// MARK: - UserProfile extensions

extension UserProfile {
    func activityLevelShort() -> String {
        switch activityLevel.lowercased() {
        case "sedentary":         return "Sedentary"
        case "lightly_active":    return "Light"
        case "moderately_active": return "Moderate"
        case "very_active":       return "Active"
        case "extremely_active":  return "Extreme"
        default:                  return activityLevelText()
        }
    }
}

// MARK: - Supporting Views（保留，供其他地方使用）

struct StatCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let value: String; let unit: String; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text(value).font(.title3.bold()).foregroundColor(themeManager.current.primaryText)
                    if !unit.isEmpty { Text(unit).font(.caption).foregroundColor(themeManager.current.secondaryText) }
                }
                Text(title).font(.caption).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1)))
    }
}

struct SettingsRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String; let title: String; let subtitle: String
    var titleColor: Color = .primary
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title3)
                    .foregroundColor(titleColor == .primary ? themeManager.current.primaryText : titleColor).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.medium)
                        .foregroundColor(titleColor == .primary ? themeManager.current.primaryText : titleColor)
                    Text(subtitle).font(.caption).foregroundColor(themeManager.current.secondaryText).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(themeManager.current.secondaryText)
            }
            .padding().contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FullPrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                Text("Privacy Policy for NutriSnap\n\nLast updated: August 01, 2025\n\nWe collect email, usage data, photos, and location (with permission) to provide and improve our service. Contact: support@nutricam.com")
                    .font(.system(size: 14)).foregroundColor(.primary).padding()
            }
            .navigationTitle("Privacy Policy").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
