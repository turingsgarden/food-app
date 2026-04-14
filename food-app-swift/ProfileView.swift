// ProfileView.swift
// 改动：
// 1. Settings 拆分：Personal Info（username/email/dob/gender）和 My Health Profile（身高体重等）分开
// 2. 主题切换改为 System / Light / Dark 三选一，带预览图
// 3. 显示 email

import SwiftUI
import StoreKit

// MARK: - Theme Preference

enum ThemePreference: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var showLogoutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var showEditPersonalInfo = false
    @State private var showEditHealthProfile = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @State private var showHelpSupport = false
    @State private var savedHealthProfile: HealthProfile? = nil
    @State private var userEmail: String = ""
    // ✅ 主题偏好（三选一）
    @State private var themePreference: ThemePreference = .system

    var userName: String { session.userName.isEmpty ? "User" : session.userName }

    var currentUserId: String {
        session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID
    }

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
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    profileManager.fetchProfile(force: false)
                    fetchUserEmail()
                    HealthAPIManager.shared.fetchHealthProfile(userId: currentUserId) { profile in
                        self.savedHealthProfile = profile
                    }
                    loadThemePreference()
                }
            }
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) { performLogout() }
            } message: { Text("Are you sure you want to logout?") }
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { showDeleteConfirmation = true }
            } message: { Text("This will permanently delete all your data.") }
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
            // ✅ Personal Info 编辑
            .sheet(isPresented: $showEditPersonalInfo) {
                EditPersonalInfoView()
                    .environmentObject(themeManager)
                    .onDisappear { profileManager.fetchProfile(force: true); fetchUserEmail() }
            }
            // ✅ Health Profile 编辑
            .sheet(isPresented: $showEditHealthProfile) {
                EditHealthProfileView(
                    existingProfile: savedHealthProfile,
                    onComplete: { updatedProfile in
                        self.savedHealthProfile = updatedProfile
                        profileManager.fetchProfile(force: true)
                    }
                )
                .environmentObject(themeManager)
                .onDisappear {
                    profileManager.fetchProfile(force: true)
                    HealthAPIManager.shared.fetchHealthProfile(userId: currentUserId) { profile in
                        self.savedHealthProfile = profile
                    }
                }
            }
            .refreshable { await refreshProfile() }
        }
    }

    // MARK: - Loading

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText))
                .scaleEffect(1.3)
            Text("Loading profile…")
                .font(.system(size: 14))
                .foregroundColor(themeManager.current.secondaryText)
        }
    }

    // MARK: - Scroll Content

    var scrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                avatarSection.padding(.top, 8)
                if let profile = profileManager.userProfile {
                    statsSection(profile: profile)
                }
                settingsSection
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(themeManager.current.inputBackground)
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(themeManager.current.cardBorder, lineWidth: 1.5))
                Text(String(userName.prefix(1)).uppercased())
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
            }

            VStack(spacing: 5) {
                Text(userName)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)

                if !userEmail.isEmpty {
                    Text(userEmail)
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.current.secondaryText)
                }

                if let profile = profileManager.userProfile {
                    Text("\(profile.age) years old · \(profile.gender)")
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.current.secondaryText.opacity(0.7))
                    if let lastSync = profileManager.lastSyncDate {
                        Text("Synced \(formatSyncDate(lastSync))")
                            .font(.system(size: 11))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.45))
                    }
                }

                // Edit Profile 快捷按钮
                Button(action: { showEditPersonalInfo = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .semibold))
                        Text("Edit Profile").font(.system(size: 13, weight: .semibold))
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

    var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Settings")
            VStack(spacing: 0) {
                // ✅ Personal Info - 分开的入口
                profileRow(
                    icon: "person.fill",
                    label: "Personal Info",
                    detail: personalInfoDetail
                ) { showEditPersonalInfo = true }

                rowDivider

                // ✅ Health Profile - 分开的入口
                profileRow(
                    icon: "heart.text.square.fill",
                    label: "Health Profile",
                    detail: healthProfileDetail
                ) { showEditHealthProfile = true }

                rowDivider

                // ✅ 主题切换（三选一）
                appearanceSection

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

    var personalInfoDetail: String {
        var parts: [String] = []
        if let p = profileManager.userProfile {
            parts.append("\(p.age)y")
            parts.append(p.gender)
        }
        if !userEmail.isEmpty { parts.append(userEmail) }
        return parts.isEmpty ? "Tap to edit" : parts.joined(separator: " · ")
    }

    var healthProfileDetail: String {
        if let hp = savedHealthProfile {
            var parts: [String] = ["\(Int(hp.heightCm))cm", "\(Int(hp.weightKg))kg"]
            if !hp.dietaryPreferences.isEmpty && !hp.dietaryPreferences.contains("no_restriction") {
                if let first = hp.dietaryPreferences.first {
                    parts.append(first.replacingOccurrences(of: "_", with: " ").capitalized)
                }
            }
            return parts.joined(separator: " · ")
        }
        return "Tap to set up health data"
    }

    // ✅ 主题三选一（System / Light / Dark）带预览
    var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("Choose your preferred theme")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }

            // 三个主题选项
            HStack(spacing: 10) {
                ForEach(ThemePreference.allCases, id: \.self) { pref in
                    themeOptionCard(pref)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    func themeOptionCard(_ pref: ThemePreference) -> some View {
        let isSelected = themePreference == pref

        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                themePreference = pref
                applyTheme(pref)
            }
        }) {
            VStack(spacing: 8) {
                // 迷你预览图
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(previewBackground(pref))
                        .frame(height: 52)
                        .overlay(
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(previewAccent(pref).opacity(0.8))
                                    .frame(width: 36, height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(previewAccent(pref).opacity(0.4))
                                    .frame(width: 28, height: 4)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(previewAccent(pref).opacity(0.2))
                                    .frame(width: 22, height: 4)
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected
                                    ? (themeManager.current == .dark ? Color.white : Color.black)
                                    : themeManager.current.cardBorder,
                                        lineWidth: isSelected ? 2 : 1)
                        )

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(themeManager.current == .dark ? Color.white : Color.black)
                                    .background(Circle().fill(previewBackground(pref)).padding(1))
                            }
                            Spacer()
                        }
                        .padding(5)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: pref.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected
                            ? (themeManager.current == .dark ? Color.white : Color.black)
                            : themeManager.current.secondaryText)
                    Text(pref.rawValue)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected
                            ? (themeManager.current == .dark ? Color.white : Color.black)
                            : themeManager.current.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    func previewBackground(_ pref: ThemePreference) -> Color {
        switch pref {
        case .system: return Color(UIColor.systemBackground)
        case .light: return Color.white
        case .dark: return Color.black
        }
    }

    func previewAccent(_ pref: ThemePreference) -> Color {
        switch pref {
        case .system: return Color.gray
        case .light: return Color.black
        case .dark: return Color.white
        }
    }

    func applyTheme(_ pref: ThemePreference) {
        switch pref {
        case .system:
            // 跟随系统
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            themeManager.current = isDark ? .dark : .light
        case .light:
            themeManager.current = .light
        case .dark:
            themeManager.current = .dark
        }
        UserDefaults.standard.set(pref.rawValue, forKey: "theme_preference")
    }

    func loadThemePreference() {
        let saved = UserDefaults.standard.string(forKey: "theme_preference") ?? "System"
        themePreference = ThemePreference(rawValue: saved) ?? .system
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

    func fetchUserEmail() {
        guard let token = session.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/get-login-methods") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONDecoder().decode([String: String].self, from: data) else { return }
            DispatchQueue.main.async { self.userEmail = json["email"] ?? "" }
        }.resume()
    }

    func formatSyncDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    func refreshProfile() async {
        await withCheckedContinuation { continuation in
            profileManager.fetchProfile(force: true)
            fetchUserEmail()
            HealthAPIManager.shared.fetchHealthProfile(userId: currentUserId) { profile in
                self.savedHealthProfile = profile
            }
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
        case "sedentary": return "Sedentary"
        case "lightly_active": return "Light"
        case "moderately_active": return "Moderate"
        case "very_active": return "Active"
        case "extremely_active": return "Extreme"
        default: return activityLevelText()
        }
    }
}

// MARK: - Supporting Views

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
