//
//  ProfileView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 7/13/25.
//

import SwiftUI

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
                
                if profileManager.isLoading && profileManager.userProfile == nil {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .scaleEffect(1.5)
                        
                        Text("Loading your profile...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                } else if let profile = profileManager.userProfile {
                    // Profile loaded
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header with Profile Picture
                            profileHeaderSection(profile: profile)
                            
                            // Stats Cards
                            profileStatsSection(profile: profile)
                            
                            // Settings Section
                            settingsSection(profile: profile)
                            
                            // Danger Zone
                            dangerZoneSection()
                            
                            // App Info
                            appInfoSection()
                        }
                        .padding(.horizontal)
                    }
                } else {
                    // No profile found or error state
                    VStack(spacing: 20) {
                        if let errorMessage = profileManager.errorMessage {
                            // Show error with retry option
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.red.opacity(0.6))
                            
                            VStack(spacing: 8) {
                                Text("Profile Error")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Button(action: {
                                print("🔄 Retry button tapped")
                                profileManager.fetchProfile(force: true)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
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
                            }
                        } else {
                            // Profile not found - needs setup
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.orange.opacity(0.6))
                            
                            VStack(spacing: 8) {
                                Text("Profile Not Found")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                
                                Text("Complete your profile setup to get personalized recommendations")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Button(action: { showEditProfile = true }) {
                                HStack {
                                    Image(systemName: "person.fill.badge.plus")
                                    Text("Complete Profile")
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
                            }
                            
                            // Allow logout even without profile
                            Button(action: { showLogoutAlert = true }) {
                                Text("Logout")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.top, 20)
                            }
                        }
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
                    } else {
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
                        print("🔍 Profile setup/edit completed, refreshing profile")
                        profileManager.fetchProfile(force: true)
                    }
            }
            .sheet(isPresented: $showHelpSupport) {
                HelpSupportView()
            }
            .refreshable {
                await refreshProfile()
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    func profileHeaderSection(profile: UserProfile) -> some View {
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
                
                Text("\(profile.age) years old • \(profile.gender)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                if let lastSync = profileManager.lastSyncDate {
                    Text("Last synced: \(formatSyncDate(lastSync))")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            
            // Edit Profile Button
            Button(action: { showEditProfile = true }) {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit Profile")
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
    func dangerZoneSection() -> some View {
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
            Text("NutriSnap")
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
    
    // FIXED: Remove profile checks from logout
    func performLogout() {
        isLoggingOut = true
        
        // Clear profile data
        profileManager.clearProfile()
        
        // Clear session - this should always work regardless of profile status
        session.logout()
        
        // Small delay for UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isLoggingOut = false
            self.dismiss()
        }
    }
}

// MARK: - Help & Support View (keeping existing implementation)
struct HelpSupportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showFullPrivacyPolicy = false
    
    var body: some View {
        NavigationView {
            ZStack {
                backgroundGradient
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        privacyPolicySection
                        supportSection
                        appInfoSection
                    }
                    .padding(.horizontal)
                }
            }
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                }
            }
            .sheet(isPresented: $showFullPrivacyPolicy) {
                FullPrivacyPolicyView()
            }
        }
    }
    
    private var backgroundGradient: some View {
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
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Help & Support")
                .font(.largeTitle.bold())
                .foregroundColor(.white)
            
            Text("Privacy Policy and Support Information")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.top, 20)
    }
    
    private var privacyPolicySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            privacyPolicyHeader
            privacyPolicyPoints
            privacyPolicyButtons
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var privacyPolicyHeader: some View {
        HStack {
            Image(systemName: "shield.fill")
                .foregroundColor(.blue)
            Text("Privacy Policy Summary")
                .font(.headline)
                .foregroundColor(.white)
        }
    }
    
    private var privacyPolicyPoints: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivacyPolicyPoint(
                icon: "envelope.fill",
                title: "Data Collection",
                description: "We collect your email address and usage data to provide and improve our service."
            )
            
            PrivacyPolicyPoint(
                icon: "camera.fill",
                title: "Photos & Location",
                description: "We access your camera and photo library only to analyze meal photos for nutrition tracking."
            )
            
            PrivacyPolicyPoint(
                icon: "lock.fill",
                title: "Data Security",
                description: "Your personal data is encrypted and stored securely. We never sell your information to third parties."
            )
            
            PrivacyPolicyPoint(
                icon: "trash.fill",
                title: "Data Deletion",
                description: "You can delete your account and all associated data at any time through the app settings."
            )
            
            PrivacyPolicyPoint(
                icon: "person.badge.shield.checkmark.fill",
                title: "Children's Privacy",
                description: "Our service is not intended for users under 13. We don't knowingly collect data from children."
            )
        }
    }
    
    private var privacyPolicyButtons: some View {
        VStack(spacing: 12) {
            fullPolicyButton
            externalLinkButton
        }
    }
    
    private var fullPolicyButton: some View {
        Button(action: {
            showFullPrivacyPolicy = true
        }) {
            HStack {
                Image(systemName: "doc.text.fill")
                Text("View Full Privacy Policy")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundColor(.blue)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    private var externalLinkButton: some View {
        Button(action: {
            if let url = URL(string: "https://www.termsfeed.com/live/d4b4e1ed-8150-4ccb-a430-340180b7bc9d") {
                UIApplication.shared.open(url)
            }
        }) {
            HStack {
                Image(systemName: "link")
                Text("For more details")
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .foregroundColor(.orange)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            supportHeader
            supportButtons
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var supportHeader: some View {
        HStack {
            Image(systemName: "questionmark.circle.fill")
                .foregroundColor(.green)
            Text("Support & Contact")
                .font(.headline)
                .foregroundColor(.white)
        }
    }
    
    private var supportButtons: some View {
        VStack(spacing: 12) {
            SupportContactRow(
                icon: "envelope.fill",
                title: "Email Support",
                subtitle: "nutrisnap@gmail.com",
                action: {
                    if let url = URL(string: "mailto:nutrisnap@gmail.com") {
                        UIApplication.shared.open(url)
                    }
                }
            )
            
            SupportContactRow(
                icon: "star.fill",
                title: "Rate the App",
                subtitle: "Help us improve with your feedback",
                action: {
                    // Can add App Store rating functionality later
                }
            )
        }
    }
    
    private var appInfoSection: some View {
        VStack(spacing: 8) {
            Text("NutriSnap v1.0.0")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text("AI-Powered Nutrition Tracking")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }
}

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