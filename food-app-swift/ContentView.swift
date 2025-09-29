//
//  ContentView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 6/17/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()
    @State private var checkingProfile = false  // Changed from true to false
    @State private var needsProfileSetup = false
    @State private var showProfileSetupPrompt = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if session.isLoggedIn {
                        // Always show dashboard after login
                        DashboardView()
                            .navigationBarHidden(true)
                            .environmentObject(networkMonitor)
                            .onAppear {
                                checkProfileStatusInBackground()
                            }
                            .sheet(isPresented: $showProfileSetupPrompt) {
                                ProfileSetupPromptView {
                                    needsProfileSetup = false
                                    showProfileSetupPrompt = false
                                    profileManager.fetchProfile(force: true)
                                }
                            }
                    } else {
                        OnboardingView()
                            .navigationBarHidden(true)
                    }
                }
                .navigationDestination(isPresented: $session.shouldNavigateToLogin) {
                    OnboardingView()
                        .navigationBarBackButtonHidden(true)
                        .onAppear {
                            SessionManager.shared.resetNavigationFlag()
                        }
                }
                
                // Offline Banner Overlay
                VStack {
                    OfflineBanner(networkMonitor: networkMonitor)
                    Spacer()
                }
                .ignoresSafeArea(.all, edges: .horizontal)
            }
        }
    }
    
    func checkProfileStatusInBackground() {
        guard SessionManager.shared.isLoggedIn else {
            return
        }
        
        // Check if this is a new registration
        if SessionManager.shared.isNewRegistration {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showProfileSetupPrompt = true
                SessionManager.shared.clearNewRegistrationFlag()
            }
            return
        }
        
        // Check profile status without blocking UI
        if profileManager.userProfile == nil && !profileManager.isLoading {
            profileManager.fetchProfile(force: false)
            
            // Show prompt after a delay if still no profile
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if profileManager.userProfile == nil &&
                   !profileManager.isLoading &&
                   profileManager.errorMessage == nil {
                    showProfileSetupPrompt = true
                }
            }
        }
    }
}

// New prompt view for profile setup
struct ProfileSetupPromptView: View {
    let onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var navigateToSetup = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Icon
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Title
                Text("Complete Your Profile")
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                // Description
                Text("Set up your profile to get personalized nutrition recommendations based on your age, gender, and activity level")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Benefits list
                VStack(alignment: .leading, spacing: 16) {
                    BenefitRow(icon: "target", text: "Personalized calorie goals")
                    BenefitRow(icon: "chart.line.uptrend.xyaxis", text: "Accurate progress tracking")
                    BenefitRow(icon: "person.fill", text: "Customized recommendations")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal)
                
                Spacer()
                
                // Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        navigateToSetup = true
                    }) {
                        Text("Set Up Profile")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
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
                    
                    Button(action: {
                        onComplete()
                        dismiss()
                    }) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .background(
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
            )
            .navigationDestination(isPresented: $navigateToSetup) {
                ProfileSetupView()
                    .navigationBarBackButtonHidden(true)
                    .onDisappear {
                        onComplete()
                        dismiss()
                    }
            }
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
