//
//  food_app_swiftApp.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 6/17/25.
//

import SwiftUI
import GoogleSignIn
import GoogleSignInSwift

@main
struct food_app_swiftApp: App {
    @StateObject private var session = SessionManager.shared
    @Environment(\.scenePhase) var scenePhase
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    switch newPhase {
                    case .background:
                        print("📱 App moved to background")
                        // Update last activity timestamp for 30-day inactivity tracking
                        // Note: We no longer log out based on background time
                        UserDefaults.standard.set(Date(), forKey: "last_activity_time")
                        
                    case .inactive:
                        print("📱 App became inactive")
                        
                    case .active:
                        print("📱 App became active")
                        // Only check for session timeout, not profile status
                        checkSessionTimeout()
                        
                    @unknown default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    print("🔴 App will terminate")
                    // Don't auto-logout on termination
                }
        }
    }
    
    private func checkSessionTimeout() {
        // Check for 30-day inactivity timeout (not background time)
        // Users should stay logged in unless inactive for 30 days
        
        if session.isLoggedIn {
            // Update last activity timestamp
            UserDefaults.standard.set(Date(), forKey: "last_activity_time")
            
            // Check if session has been inactive for 30 days
            if let lastActivity = UserDefaults.standard.object(forKey: "last_activity_time") as? Date {
                let inactivityDuration = Date().timeIntervalSince(lastActivity)
                let thirtyDaysInSeconds: TimeInterval = 30 * 24 * 60 * 60 // 30 days
                
                if inactivityDuration > thirtyDaysInSeconds {
                    print("⏰ Session expired - inactive for \(Int(inactivityDuration / 86400)) days")
                    performLogout()
                    return
                }
            }
            
            // Validate that auth token still exists
            if SessionManager.shared.getAuthToken() == nil {
                print("⏰ Session invalid - no auth token found")
                performLogout()
                return
            }
            
            print("✅ Session still valid")
        }
        
        // Clear the old background timestamp (no longer used for logout)
        UserDefaults.standard.removeObject(forKey: "app_background_time")
    }
    
    private func performLogout() {
        print("🚪 Performing session timeout logout")
        session.logout()
        clearSensitiveData()
    }
    
    private func clearSensitiveData() {
        // Clear cached data
        URLCache.shared.removeAllCachedResponses()
        
        // Clear image cache if you have one
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    if fileURL.pathExtension == "jpg" || fileURL.pathExtension == "png" {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                }
            } catch {
                print("Error clearing cached files: \(error)")
            }
        }
        
        print("🧹 Cleared sensitive data")
    }
}
