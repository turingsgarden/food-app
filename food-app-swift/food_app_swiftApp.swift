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
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.scenePhase) var scenePhase
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.current.colorScheme)    
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    switch newPhase {
                    case .background:
                        print("📱 App moved to background")
                        UserDefaults.standard.set(Date(), forKey: "app_background_time")
                    case .inactive:
                        print("📱 App became inactive")
                    case .active:
                        print("📱 App became active")
                        checkSessionTimeout()
                    @unknown default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    print("🔴 App will terminate")
                }
        }
    }
    
    private func checkSessionTimeout() {
        if let backgroundTime = UserDefaults.standard.object(forKey: "app_background_time") as? Date {
            let timeInBackground = Date().timeIntervalSince(backgroundTime)
            let timeoutDuration: TimeInterval = 7 * 24 * 60 * 60
            if timeInBackground > timeoutDuration && session.isLoggedIn {
                print("⏰ Session timeout")
                performLogout()
            }
            UserDefaults.standard.removeObject(forKey: "app_background_time")
        }
    }
    
    private func performLogout() {
        session.logout()
        clearSensitiveData()
    }
    
    private func clearSensitiveData() {
        URLCache.shared.removeAllCachedResponses()
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
                for fileURL in fileURLs where fileURL.pathExtension == "jpg" || fileURL.pathExtension == "png" {
                    try FileManager.default.removeItem(at: fileURL)
                }
            } catch { print("Error clearing cached files: \(error)") }
        }
    }
}
