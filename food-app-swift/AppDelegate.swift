//
//  AppDelegate.swift
//  food-app-swift
//
//  Created by Yifan Zhang on 2025/8/21.
//

import UIKit
import GoogleSignIn

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // 配置 Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "97893618983-ierm2fkrfsmjmf421timffggri4fka3l.apps.googleusercontent.com"
        )

        return true
    }

    // iOS 9+
    @available(iOS 9.0, *)
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}
