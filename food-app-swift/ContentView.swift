//
//  ContentView.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 6/17/25.
//

// ContentView.swift - Updated version
import SwiftUI

struct ContentView: View {
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()  // Add this
    @State private var checkingProfile = true
    @State private var needsProfileSetup = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Group {
                    if session.isLoggedIn {
                        if checkingProfile {
                            LoadingView()
                        } else if needsProfileSetup {
                            ProfileSetupView()
                                .navigationBarHidden(true)
                                .onDisappear {
                                    SessionManager.shared.clearNewRegistrationFlag()
                                }
                        } else {
                            DashboardView()
                                .navigationBarHidden(true)
                                .environmentObject(networkMonitor)  // Pass to dashboard
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
        .onAppear {
            performInitialChecks()
        }
    }
    
    func performInitialChecks() {
        // Validate session on app launch
        if SessionManager.shared.isLoggedIn {
            let isValid = SessionManager.shared.validateSession()
            if !isValid {
                print("❌ Invalid session detected on app launch")
                // Session validation failed, user will be logged out
            } else {
                // Session is valid, check profile status
                checkProfileStatus()
            }
        } else {
            // Not logged in, no need to check profile
            checkingProfile = false
        }
    }
    
    func checkProfileStatus() {
        guard SessionManager.shared.isLoggedIn else {
            checkingProfile = false
            return
        }
        
        print("🔍 Checking profile status...")
        print("🆕 Is new registration: \(SessionManager.shared.isNewRegistration)")
        
        // Only force profile setup for NEW registrations
        if SessionManager.shared.isNewRegistration {
            print("🆕 New registration detected - forcing profile setup")
            checkingProfile = false
            needsProfileSetup = true
            return
        }
        
        // For existing users, just go to dashboard
        // The dashboard will show the welcome card if they don't have a profile
        print("👤 Existing user - proceeding to dashboard")
        checkingProfile = false
        needsProfileSetup = false
        
        // Let ProfileManager fetch the profile in the background
        // Dashboard will handle showing the welcome card if needed
        profileManager.fetchProfile(force: false)
    }
}

#Preview {
    ContentView()
}
