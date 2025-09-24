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
    
    init() {
        tryAutoLogin()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    switch newPhase {
                    case .background:
                        print("📱 App moved to background")
                        // Option 1: Logout immediately when app goes to background
                        // Uncomment the next line if you want immediate logout
                        // performLogout()
                        
                        // Option 2: Save timestamp for session timeout
                        UserDefaults.standard.set(Date(), forKey: "app_background_time")
                        
                    case .inactive:
                        print("📱 App became inactive")
                        
                    case .active:
                        print("📱 App became active")
                        // Check for session timeout when app returns
                        checkSessionTimeout()
                        
                    @unknown default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    print("🔴 App will terminate - logging out")
                    performLogout()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Alternative: Logout when app enters background
                    // Uncomment if you want this behavior
                    // performLogout()
                }
        }
    }
    
    private func performLogout() {
        print("🚪 Performing auto logout")
        session.logout()
        
        // Clear all sensitive data
        clearSensitiveData()
    }
    
    private func checkSessionTimeout() {
        // Check if app was in background for too long (e.g., 5 minutes)
        if let backgroundTime = UserDefaults.standard.object(forKey: "app_background_time") as? Date {
            let timeInBackground = Date().timeIntervalSince(backgroundTime)
            let timeoutDuration: TimeInterval = 300 // 5 minutes
            
            if timeInBackground > timeoutDuration {
                print("⏰ Session timeout - app was in background for \(Int(timeInBackground)) seconds")
                performLogout()
            }
            
            // Clear the background timestamp
            UserDefaults.standard.removeObject(forKey: "app_background_time")
        }
    }
    
    private func clearSensitiveData() {
        // Clear any cached images or sensitive data
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
