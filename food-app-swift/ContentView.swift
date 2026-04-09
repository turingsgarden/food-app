//
//  ContentView.swift
//  food-app-swift
//
//  Health Agent 版本
//  路由逻辑：
//  未登录 → OnboardingView
//  已登录 + 无健康档案 → HealthProfileView（4步 onboarding）
//  已登录 + 有档案 + 无营养计划 → GoalSelectionView
//  已登录 + 两者都有 → HealthDashboardView（主 Tab）

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @StateObject private var networkMonitor = NetworkMonitor()

    // Health Agent 状态
    @State private var healthProfile: HealthProfile?
    @State private var nutritionPlan: NutritionPlan?
    @State private var isCheckingSetup = true

    var body: some View {
        ZStack {
            if !session.isLoggedIn {
                // ── 未登录：原有登录/注册流程 ──
                NavigationStack {
                    OnboardingView()
                        .navigationBarHidden(true)
                        .environmentObject(themeManager)
                }

            } else if isCheckingSetup {
                // ── 检查中：Loading ──
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
                // ── 无健康档案：4步 Onboarding ──
                NavigationStack {
                    HealthProfileView { profile in
                        self.healthProfile = profile
                        // 档案保存后，去选目标
                    }
                    .environmentObject(themeManager)
                }

            } else if nutritionPlan == nil {
                // ── 有档案，无营养计划：选健康目标 ──
                NavigationStack {
                    GoalSelectionView(healthProfile: healthProfile!) { plan in
                        self.nutritionPlan = plan
                        // 保存到 UserDefaults 供下次启动用
                        saveNutritionPlanLocally(plan)
                    }
                    .environmentObject(themeManager)
                }

            } else {
                // ── 主 App：Health Dashboard ──
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
                // 登出：清空本地状态
                healthProfile = nil
                nutritionPlan = nil
                isCheckingSetup = false
            }
        }
    }

    // MARK: - 启动时检查是否已完成 onboarding

    func checkSetup() {
        guard session.isLoggedIn else {
            isCheckingSetup = false
            return
        }

        isCheckingSetup = true

        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID

        // 1. 先尝试读取本地缓存（快速显示）
        if let cachedPlan = loadNutritionPlanLocally(userId: userId) {
            nutritionPlan = cachedPlan
        }

        // 2. 从服务器获取健康档案
        HealthAPIManager.shared.fetchHealthProfile(userId: userId) { profile in
            self.healthProfile = profile

            if profile != nil {
                // 有档案了，如果还没有营养计划就保持 GoalSelectionView
                // 如果本地已有计划则直接进主界面（上面已经 set 了）
            }

            self.isCheckingSetup = false
        }
    }

    // MARK: - 本地缓存 NutritionPlan

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
