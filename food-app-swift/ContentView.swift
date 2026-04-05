//
//  ContentView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 6/17/25.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var checkingProfile = false
    @State private var needsProfileSetup = false
    @State private var showProfileSetupPrompt = false

    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if session.isLoggedIn {
                        DashboardView()
                            .navigationBarHidden(true)
                            .environmentObject(networkMonitor)
                            .environmentObject(themeManager)
                            .onAppear { checkProfileStatusInBackground() }
                            .sheet(isPresented: $showProfileSetupPrompt) {
                                ProfileSetupPromptView {
                                    needsProfileSetup = false
                                    showProfileSetupPrompt = false
                                    profileManager.fetchProfile(force: true)
                                }
                                .environmentObject(themeManager)  // ✅
                            }
                    } else {
                        OnboardingView()
                            .navigationBarHidden(true)
                            .environmentObject(themeManager)  // ✅
                    }
                }
                .navigationDestination(isPresented: $session.shouldNavigateToLogin) {
                    OnboardingView()
                        .navigationBarBackButtonHidden(true)
                        .environmentObject(themeManager)  // ✅
                        .onAppear { SessionManager.shared.resetNavigationFlag() }
                }

                VStack {
                    OfflineBanner(networkMonitor: networkMonitor)
                    Spacer()
                }
                .ignoresSafeArea(.all, edges: .horizontal)
            }
        }
    }

    func checkProfileStatusInBackground() {
        guard SessionManager.shared.isLoggedIn else { return }
        if SessionManager.shared.isNewRegistration {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showProfileSetupPrompt = true
                SessionManager.shared.clearNewRegistrationFlag()
            }
            return
        }
        if profileManager.userProfile == nil && !profileManager.isLoading {
            profileManager.fetchProfile(force: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if profileManager.userProfile == nil && !profileManager.isLoading && profileManager.errorMessage == nil {
                    showProfileSetupPrompt = true
                }
            }
        }
    }
}

// MARK: - Profile Setup Prompt

struct ProfileSetupPromptView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var navigateToSetup = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 80))
                    .foregroundStyle(LinearGradient(colors: [.orange, .orange.opacity(0.7)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Complete Your Profile").font(.title.bold())
                    .foregroundColor(themeManager.current.primaryText)
                Text("Set up your profile to get personalized nutrition recommendations based on your age, gender, and activity level")
                    .font(.body).foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    BenefitRow(icon: "target", text: "Personalized calorie goals")
                    BenefitRow(icon: "chart.line.uptrend.xyaxis", text: "Accurate progress tracking")
                    BenefitRow(icon: "person.fill", text: "Customized recommendations")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground))
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: { navigateToSetup = true }) {
                        Text("Set Up Profile").fontWeight(.semibold).foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                            .cornerRadius(12).shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    Button(action: { onComplete(); dismiss() }) {
                        Text("Skip for now").font(.subheadline)
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }
                .padding(.horizontal).padding(.bottom, 40)
            }
            .background(themeManager.current.background.ignoresSafeArea())
            .navigationDestination(isPresented: $navigateToSetup) {
                ProfileSetupView()
                    .navigationBarBackButtonHidden(true)
                    .environmentObject(themeManager)  // ✅
                    .onDisappear { onComplete(); dismiss() }
            }
        }
        .preferredColorScheme(themeManager.current.colorScheme)
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.orange).frame(width: 24)
            Text(text).font(.subheadline).foregroundColor(themeManager.current.primaryText)
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
