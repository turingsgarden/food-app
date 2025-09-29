//
//  ProfileView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 7/13/25.
//

import SwiftUI
import StoreKit

struct ProfileView: View {
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var showLogoutAlert = false
    @State private var isLoggingOut = false
    @State private var showEditProfile = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var hasAppeared = false
    @State private var showHelpSupport = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.black.opacity(0.95),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if profileManager.isLoading && profileManager.userProfile == nil && !hasAppeared {
                    // Loading state only on initial load
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .scaleEffect(1.5)
                        
                        Text("Loading your profile...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                } else {
                    // Main content - always show, even without profile
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header with Profile Picture
                            profileHeaderSection
                            
                            if let profile = profileManager.userProfile {
                                // Stats Cards
                                profileStatsSection(profile: profile)
                                
                                // Settings Section
                                settingsSection(profile: profile)
                            } else {
                                // Profile setup prompt
                                profileSetupPromptSection
                            }
                            
                            // Account Section - Always visible
                            accountSection
                            
                            // App Info
                            appInfoSection()
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if profileManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .scaleEffect(0.8)
                    } else if profileManager.userProfile != nil {
                        Button(action: {
                            print("🔄 Manual refresh button tapped")
                            profileManager.fetchProfile(force: true)
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    print("👤 ProfileView appeared - fetching profile")
                    profileManager.fetchProfile(force: false)
                }
            }
            .alert("Logout", isPresented: $showLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    performLogout()
                }
            } message: {
                Text("Are you sure you want to logout? You'll need to login again to access your meals.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showEditProfile) {
                ProfileSetupView(existingProfile: profileManager.userProfile)
                    .onDisappear {
                        // Force refresh after profile setup/edit
                        print("🔃 Profile setup/edit completed, refreshing profile")
                        profileManager.fetchProfile(force: true)
                    }
            }
            
            .alert("Help & Support", isPresented: $showHelpSupport) {
                Button("Contact Support") {
                    openEmailSupport()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("For support, please contact us at support@nutricam.com")
            }            .refreshable {
                await refreshProfile()
            }
        }
    }
    
    private func openEmailSupport() {
        let email = "support@nutricam.com"
        let subject = "NutriCam Support Request"
        let body = "Hi NutriCam Support Team,\n\nI need help with:\n\n[Please describe your issue here]\n\n---\nApp Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")\nDevice: \(UIDevice.current.model)\niOS Version: \(UIDevice.current.systemVersion)"
        
        if let url = URL(string: "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    var profileHeaderSection: some View {
        VStack(spacing: 16) {
            // Profile Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .orange.opacity(0.7)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Text(session.userName.prefix(1).uppercased())
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: .orange.opacity(0.3), radius: 20)
            
            VStack(spacing: 4) {
                Text(session.userName)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                if let profile = profileManager.userProfile {
                    Text("\(profile.age) years old • \(profile.gender)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    if let lastSync = profileManager.lastSyncDate {
                        Text("Last synced: \(formatSyncDate(lastSync))")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                } else {
                    Text("Profile not set up")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
            
            // Edit/Setup Profile Button
            Button(action: { showEditProfile = true }) {
                HStack {
                    Image(systemName: profileManager.userProfile != nil ? "pencil" : "person.fill.badge.plus")
                    Text(profileManager.userProfile != nil ? "Edit Profile" : "Setup Profile")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                        .overlay(
                            Capsule()
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.top, 20)
    }
    
    @ViewBuilder
    var profileSetupPromptSection: some View {
        VStack(spacing: 20) {
            // Informative Card
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                
                VStack(spacing: 8) {
                    Text("Complete Your Profile")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Set up your profile to get personalized nutrition recommendations and accurate calorie tracking")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                Button(action: { showEditProfile = true }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Set Up Now")
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    @ViewBuilder
    func profileStatsSection(profile: UserProfile) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Daily Goal",
                value: "\(profile.calorieTarget)",
                unit: "kcal",
                icon: "target",
                color: .orange
            )
            
            StatCard(
                title: "Activity",
                value: profile.activityLevelText(),
                unit: "",
                icon: "figure.run",
                color: .green
            )
        }
    }
    
    @ViewBuilder
    func settingsSection(profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "person.fill",
                    title: "Personal Information",
                    subtitle: "\(profile.age) years • \(profile.gender) • \(profile.activityLevelText())",
                    action: { showEditProfile = true }
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                SettingsRow(
                    icon: "target",
                    title: "Nutrition Goals",
                    subtitle: "\(profile.calorieTarget) kcal daily target",
                    action: { showEditProfile = true }
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                SettingsRow(
                    icon: "leaf.fill",
                    title: "Dietary Preferences",
                    subtitle: profile.dietaryPreferencesText,
                    action: { showEditProfile = true }
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                SettingsRow(
                    icon: "star.fill",
                    title: "Rate NutriCam",
                    subtitle: "Love the app? Leave us a review!",
                    action: rateApp
                )
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                SettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "Privacy Policy, FAQ and support",
                    action: { showHelpSupport = true }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
    
    @ViewBuilder
    var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "arrow.right.square.fill",
                    title: "Logout",
                    subtitle: "Sign out of your account",
                    titleColor: .red,
                    action: { showLogoutAlert = true }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.red.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    @ViewBuilder
    func appInfoSection() -> some View {
        VStack(spacing: 8) {
            Text("NutriCam")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text("Version 1.0.0")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.7))
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Helper Functions
    
    func formatSyncDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func refreshProfile() async {
        await withCheckedContinuation { continuation in
            print("🔄 Pull-to-refresh triggered")
            profileManager.fetchProfile(force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                continuation.resume()
            }
        }
    }
    
    // FIXED: Allow logout regardless of profile status
    func performLogout() {
        isLoggingOut = true
        
        // Clear all data
        profileManager.clearProfile()
        
        // Perform logout
        session.logout()
        
        // Dismiss view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoggingOut = false
            self.dismiss()
        }
    }
    
    func rateApp() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            AppStore.requestReview(in: windowScene)
        } else {
            if let url = URL(string: "https://apps.apple.com/us/app/nutrition-cam/id6749919732") {
                UIApplication.shared.open(url)
            }
        }
    }
}

// Keep all existing supporting views (StatCard, SettingsRow, HelpSupportView, etc.) unchanged...
// [Rest of the supporting views remain the same as in original file]

// MARK: - Supporting Views

struct PrivacyPolicyPoint: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SupportContactRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.green)
                    .font(.title3)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FullPrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    
    let privacyPolicyText = """
    Privacy Policy for NutriSnap

    Last updated: August 01, 2025

    This Privacy Policy describes Our policies and procedures on the collection, use and disclosure of Your information when You use the Service and tells You about Your privacy rights and how the law protects You.

    We use Your Personal data to provide and improve the Service. By using the Service, You agree to the collection and use of information in accordance with this Privacy Policy.

    COLLECTING AND USING YOUR PERSONAL DATA

    Types of Data Collected:
    • Email address
    • Usage Data (IP address, browser type, device information)
    • Photos and camera access (for meal analysis)
    • Location information (with your permission)

    How We Use Your Data:
    • To provide and maintain our Service
    • To manage your account and registration
    • To contact you about updates and security notifications
    • To analyze usage and improve our Service
    • For business transfers or legal requirements

    DATA SECURITY
    The security of Your Personal Data is important to Us. While We strive to use commercially acceptable means to protect Your Personal Data, We cannot guarantee its absolute security.

    YOUR RIGHTS
    • Right to access your personal data
    • Right to correct or update your information
    • Right to delete your personal data
    • Right to data portability

    CHILDREN'S PRIVACY
    Our Service does not address anyone under the age of 13. We do not knowingly collect personally identifiable information from anyone under the age of 13.

    CONTACT US
    If you have any questions about this Privacy Policy, You can contact us:
    • By email: nutrisnap@gmail.com

    For the complete Privacy Policy, visit our website or contact us directly.
    """
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(privacyPolicyText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding()
                }
            }
            .background(Color.black)
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text(value)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var titleColor: Color = .white
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(titleColor == .white ? .orange : titleColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(titleColor)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
