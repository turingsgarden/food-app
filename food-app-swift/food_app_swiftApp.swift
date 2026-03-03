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
                        // Save timestamp for session timeout
                        UserDefaults.standard.set(Date(), forKey: "app_background_time")
                        
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
        // Only check for actual timeout, not profile status
        if let backgroundTime = UserDefaults.standard.object(forKey: "app_background_time") as? Date {
            let timeInBackground = Date().timeIntervalSince(backgroundTime)
            let timeoutDuration: TimeInterval = 7 * 24 * 60 * 60
            
            // Only logout if session has actually timed out
            if timeInBackground > timeoutDuration && session.isLoggedIn {
                print("⏰ Session timeout - app was in background for \(Int(timeInBackground)) seconds")
                performLogout()
            }
            
            // Clear the background timestamp
            UserDefaults.standard.removeObject(forKey: "app_background_time")
        }
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
