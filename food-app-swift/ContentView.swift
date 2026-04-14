//  BatchUploadView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/8/26.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()


    @State private var healthProfile: HealthProfile?
    @State private var nutritionPlan: NutritionPlan?
    @State private var isCheckingSetup = true

    var body: some View {
        ZStack {
            if !session.isLoggedIn {

                NavigationStack {
                    OnboardingView()
                        .navigationBarHidden(true)
                        .environmentObject(themeManager)
                }

            } else if isCheckingSetup {

                ZStack {
                    themeManager.current.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(
                                tint: themeManager.current.primaryText))
                            .scaleEffect(1.2)
                        Text("Loading your profile…")
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }

            } else if healthProfile == nil {

                NavigationStack {
                    HealthProfileView { profile in
                        self.healthProfile = profile

                    }
                    .environmentObject(themeManager)
                }

            } else if nutritionPlan == nil {
                
                NavigationStack {
                    GoalSelectionView(healthProfile: healthProfile!) { plan in
                        self.nutritionPlan = plan
                       
                        saveNutritionPlanLocally(plan)
                    }
                    .environmentObject(themeManager)
                }

            } else {
                
                HealthDashboardView(
                    nutritionPlan: nutritionPlan!,
                    healthProfile: healthProfile!
                )
                .environmentObject(themeManager)
                .overlay(alignment: .top) {
                    OfflineBanner(networkMonitor: networkMonitor)
                }
            }
        }
        .preferredColorScheme(themeManager.current.colorScheme)
        .onAppear { checkSetup() }
        .onChange(of: session.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                checkSetup()
            } else {

                healthProfile = nil
                nutritionPlan = nil
                isCheckingSetup = false
            }
        }
    }



    func checkSetup() {
        guard session.isLoggedIn else {
            isCheckingSetup = false
            return
        }

        isCheckingSetup = true

        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID

       
        if let cachedPlan = loadNutritionPlanLocally(userId: userId) {
            nutritionPlan = cachedPlan
        }

        
        HealthAPIManager.shared.fetchHealthProfile(userId: userId) { profile in
            self.healthProfile = profile

            if profile != nil {
                
            }

            self.isCheckingSetup = false
        }
    }

    

    func saveNutritionPlanLocally(_ plan: NutritionPlan) {
        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID
        if let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: "nutrition_plan_\(userId)")
        }
    }

    func loadNutritionPlanLocally(userId: String) -> NutritionPlan? {
        guard let data = UserDefaults.standard.data(forKey: "nutrition_plan_\(userId)"),
              let plan = try? JSONDecoder().decode(NutritionPlan.self, from: data)
        else { return nil }
        return plan
    }
}
