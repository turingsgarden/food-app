//
//  Dashboardview.swift
//  food-app-swift
//
//  Created by Helen Tu on 3/27/26.
//

import SwiftUI
import Charts
import Foundation

struct DashboardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @State private var meals: [Meal] = []
    @State private var waterIntake: [WaterEntry] = []
    @State private var exerciseEntries: [ExerciseEntry] = []
    @State private var weightEntries: [WeightEntry] = []
    @State private var todayCalories: Int = 0
    @State private var todayWater: Double = 0.0
    @State private var todayExercise: Int = 0
    @State private var currentWeight: Double = 0.0
    @State private var monthlyCalories: Int = 0
    @State private var monthlyAvgCalories: Int = 0
    @State private var monthlyWater: Double = 0.0
    @State private var monthlyExercise: Int = 0
    @State private var weeklyExercise: Int = 0
    @State private var weeklyAvgWater: Double = 0.0
    @State private var weeklyMeals: Int = 0
    @State private var isLoading = false
    @State private var scrollToLatest = false
    @State private var showMealHistory = false
    @State private var showUploadMeal = false
    @State private var showProfile = false
    @State private var showWaterTracking = false
    @State private var showExerciseTracking = false
    @State private var showWeightTracking = false
    @State private var errorMessage = ""
    @State private var selectedTimeFilter = "Today"
    @State private var animateCalories = false
    @State private var calorieGoal: Int = 2000
    @State private var hasInitialized = false
    @State private var showNetworkAlert = false
    @State private var networkError: NetworkError?
    @State private var showProfileAlert = false
    @State private var selectedMealForDetail: Meal?
    @State private var selectedSummaryTab = 0
    @State private var totalProtein: Int = 0
    @State private var totalCarbs: Int = 0
    @State private var totalFat: Int = 0
    @State private var totalFiber: Int = 0
    @State private var totalSugar: Int = 0
    @State private var totalSodium: Int = 0
    @State private var currentStreak: Int = 0
    @State private var weeklyGoalProgress: Double = 0.0

    let timeFilters = ["Today", "This Week", "This Month"]

    enum NetworkError: Identifiable {
        case noInternet, serverError, profileSyncFailed, dataLoadFailed, sessionExpired
        var id: String {
            switch self {
            case .noInternet: return "no_internet"
            case .serverError: return "server_error"
            case .profileSyncFailed: return "profile_sync_failed"
            case .dataLoadFailed: return "data_load_failed"
            case .sessionExpired: return "session_expired"
            }
        }
        var title: String {
            switch self {
            case .noInternet: return "No Internet Connection"
            case .serverError: return "Server Error"
            case .profileSyncFailed: return "Profile Sync Failed"
            case .dataLoadFailed: return "Data Load Failed"
            case .sessionExpired: return "Session Expired"
            }
        }
        var message: String {
            switch self {
            case .noInternet: return "Please check your internet connection and try again."
            case .serverError: return "Our servers are experiencing issues. Please try again later."
            case .profileSyncFailed: return "Unable to sync your profile. Some features may be limited."
            case .dataLoadFailed: return "Failed to load your data. Pull to refresh to try again."
            case .sessionExpired: return "Your session has expired. Please log in again."
            }
        }
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }

    var userName: String { session.userName.isEmpty ? "Friend" : session.userName }
    var dynamicCalorieGoal: Int { profileManager.userProfile?.calorieTarget ?? calorieGoal }

    var displayedCalories: Int {
        switch selectedTimeFilter {
        case "Today": return todayCalories
        case "This Week": return Int(Double(todayCalories) * 7)
        case "This Month": return monthlyCalories
        default: return todayCalories
        }
    }

    var displayedGoal: Int {
        switch selectedTimeFilter {
        case "Today": return dynamicCalorieGoal
        case "This Week": return dynamicCalorieGoal * 7
        case "This Month":
            let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
            return dynamicCalorieGoal * days
        default: return dynamicCalorieGoal
        }
    }

    var calorieProgress: Double {
        let goal = displayedGoal
        guard goal > 0 else { return 0 }
        return min(Double(displayedCalories) / Double(goal), 1.0)
    }

    var calorieProgressColor: Color {
        if calorieProgress < 0.5 { return .green }
        else if calorieProgress < 0.8 { return .yellow }
        else if calorieProgress < 1.0 { return .orange }
        else { return .red }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        timeFilterSection
                        if profileManager.isNewUser {
                            WelcomeNewUserCard { showProfile = true }
                        } else if profileManager.userProfile == nil && !profileManager.isLoading && profileManager.errorMessage != nil {
                            if let errorMessage = profileManager.errorMessage { profileErrorSection(errorMessage) }
                        }
                        if let networkError = networkError { networkErrorSection(networkError) }
                        else if profileManager.isLoading && profileManager.userProfile == nil && !profileManager.isNewUser { profileLoadingSection }
                        enhancedMainStatsSection
                        if !meals.isEmpty { recentMealsSection }
                        if !meals.isEmpty { comprehensiveNutritionSection }
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal).padding(.top, 10)
                }
                .refreshable { await refreshDashboard() }
                enhancedFloatingUploadButton
                RecalculationFloatingButton()
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .onAppear { initializeDashboard() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealSaved"))) { _ in
                fetchAllData(); scrollToLatest = true
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NutritionRecalculated"))) { notification in
                guard let mealId = notification.userInfo?["mealId"] as? String,
                      let nutritionInfo = notification.userInfo?["nutritionInfo"] as? String else { return }
                if let index = meals.firstIndex(where: { $0._id == mealId }) {
                    meals[index].nutrition_info = nutritionInfo
                    if let imageDesc = notification.userInfo?["imageDescription"] as? String, !imageDesc.isEmpty {
                        meals[index].image_description = imageDesc
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { fetchAllData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WaterAdded"))) { _ in fetchWaterData() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExerciseAdded"))) { _ in fetchExerciseData() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WeightAdded"))) { _ in fetchWeightData() }
            .onReceive(profileManager.$userProfile) { newProfile in
                if let profile = newProfile { withAnimation { calorieGoal = profile.calorieTarget } }
            }
            .onReceive(session.$shouldNavigateToLogin) { _ in }
            .sheet(isPresented: $showMealHistory) { MealHistoryView().environmentObject(themeManager) }
            .sheet(isPresented: $showUploadMeal) { BatchUploadView().environmentObject(themeManager) }
            .sheet(isPresented: $showProfile) {
                ProfileView().environmentObject(themeManager).onDisappear { profileManager.fetchProfile(force: true) }
            }
            .sheet(isPresented: $showWaterTracking) { WaterTrackingView().environmentObject(themeManager) }
            .sheet(isPresented: $showExerciseTracking) { ExerciseTrackingView().environmentObject(themeManager) }
            .sheet(isPresented: $showWeightTracking) { WeightTrackingView().environmentObject(themeManager) }
            .sheet(item: $selectedMealForDetail) { meal in
                NavigationView { MealDetailView(meal: meal).environmentObject(themeManager) }
            }
            .alert("Complete Your Profile", isPresented: $showProfileAlert) {
                Button("Complete Now") { showProfile = true }
                Button("Later", role: .cancel) {}
            } message: {
                Text("Set up your profile to get personalized nutrition goals and better tracking.")
            }
            .alert(networkError?.title ?? "Error", isPresented: $showNetworkAlert) {
                if networkError == .sessionExpired { Button("Login") { session.logout() } }
                else { Button("Retry") { handleNetworkErrorRetry() } }
                Button("Cancel", role: .cancel) { networkError = nil }
            } message: { Text(networkError?.message ?? "An error occurred") }
        }
    }

    // MARK: - Header

    var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting).font(.caption).foregroundColor(themeManager.current.secondaryText)
                    Text("\(userName) 👋").font(.title2).bold().foregroundColor(themeManager.current.primaryText)
                }
                Spacer()
                ZStack {
                    ProfileCircle(userName: userName, size: 44, showBorder: true, borderColor: .orange) { showProfile = true }
                    Circle()
                        .fill(profileManager.isLoading ? Color.yellow : profileManager.userProfile != nil ? Color.green : profileManager.isNewUser ? Color.orange : Color.red)
                        .frame(width: 12, height: 12).offset(x: 16, y: -16)
                }
            }
            HStack {
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.caption).foregroundColor(themeManager.current.secondaryText)
                Spacer()
                if currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill").foregroundColor(.orange)
                        Text("\(currentStreak) day streak").font(.caption).foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                }
            }
        }
    }

    // MARK: - Time Filter

    var timeFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(timeFilters, id: \.self) { filter in
                    Button(action: { withAnimation(.spring()) { selectedTimeFilter = filter } }) {
                        Text(filter).font(.subheadline)
                            .fontWeight(selectedTimeFilter == filter ? .semibold : .regular)
                            .foregroundColor(selectedTimeFilter == filter ? .black : themeManager.current.primaryText)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 25)
                                .fill(selectedTimeFilter == filter ? Color.orange : themeManager.current.inputBackground))
                            .overlay(RoundedRectangle(cornerRadius: 25)
                                .stroke(selectedTimeFilter == filter ? Color.clear : themeManager.current.cardBorder, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Error Sections

    func networkErrorSection(_ error: NetworkError) -> some View {
        HStack {
            Image(systemName: error == .sessionExpired ? "exclamationmark.lock.fill" : "wifi.exclamationmark")
                .foregroundColor(.red).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(.caption).fontWeight(.semibold).foregroundColor(.red)
                Text(error.message).font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
            Spacer()
            Button(error == .sessionExpired ? "Login" : "Retry") {
                if error == .sessionExpired { session.logout() } else { handleNetworkErrorRetry() }
            }
            .font(.caption).foregroundColor(.orange)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }

    var profileLoadingSection: some View {
        HStack {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange)).scaleEffect(0.8)
            Text("Loading your profile...").font(.caption).foregroundColor(themeManager.current.secondaryText)
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1)))
    }

    func profileErrorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text("Profile Error").font(.caption).fontWeight(.semibold).foregroundColor(.red)
                Text(error).font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
            Spacer()
            Button("Retry") { profileManager.fetchProfile(force: true) }.font(.caption).foregroundColor(.orange)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }

    // MARK: - Main Stats

    var enhancedMainStatsSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(calorieProgressColor.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: getCalorieStatusIcon())
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(calorieProgressColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Calories").font(.subheadline).fontWeight(.medium)
                            .foregroundColor(themeManager.current.primaryText)
                        Text(selectedTimeFilter).font(.caption2).fontWeight(.medium)
                            .foregroundColor(themeManager.current.secondaryText)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(themeManager.current.inputBackground))
                    }
                    if profileManager.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange)).scaleEffect(0.7)
                    }
                }
                HStack(alignment: .bottom, spacing: 4) {
                    Text("\(animateCalories ? displayedCalories : 0)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: displayedCalories)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("/ \(displayedGoal)").font(.callout).foregroundColor(themeManager.current.secondaryText)
                        Text("kcal").font(.caption).foregroundColor(themeManager.current.secondaryText)
                    }
                    .padding(.bottom, 4)
                }
                Text(getCalorieStatusMessage()).font(.caption).foregroundColor(calorieProgressColor).fontWeight(.medium)
            }
            Spacer()
            ZStack {
                Circle().stroke(themeManager.current.cardBorder, lineWidth: 8).frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: animateCalories ? calorieProgress : 0)
                    .stroke(AngularGradient(gradient: Gradient(stops: [
                        .init(color: calorieProgressColor, location: 0.0),
                        .init(color: calorieProgressColor.opacity(0.8), location: 0.5),
                        .init(color: calorieProgressColor, location: 1.0)
                    ]), center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80).rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: calorieProgress)
                VStack(spacing: 2) {
                    Text("\(Int(calorieProgress * 100))%")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Image(systemName: getTrendIcon()).font(.system(size: 8)).foregroundColor(calorieProgressColor)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(themeManager.current.cardBackground)
                RoundedRectangle(cornerRadius: 20).stroke(
                    LinearGradient(gradient: Gradient(colors: [calorieProgressColor.opacity(0.3), calorieProgressColor.opacity(0.1), Color.clear]),
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
            }
        )
    }

    func getCalorieStatusIcon() -> String {
        if profileManager.isNewUser { return "person.crop.circle.badge.plus" }
        else if calorieProgress < 0.3 { return "arrow.up.circle.fill" }
        else if calorieProgress < 0.7 { return "checkmark.circle.fill" }
        else if calorieProgress < 1.0 { return "exclamationmark.circle.fill" }
        else { return "xmark.circle.fill" }
    }

    func getCalorieStatusMessage() -> String {
        if profileManager.isNewUser { return "Set up profile for personalized goals" }
        else if calorieProgress < 0.3 { return "Great start! Keep it up" }
        else if calorieProgress < 0.7 { return "On track for your goal" }
        else if calorieProgress < 1.0 { return "Almost there!" }
        else if calorieProgress < 1.2 { return "Goal achieved!" }
        else { return "Over goal - consider lighter options" }
    }

    func getTrendIcon() -> String {
        if calorieProgress < 0.5 { return "arrow.up" }
        else if calorieProgress < 1.0 { return "arrow.right" }
        else { return "arrow.down" }
    }

    // MARK: - Recent Meals

    var recentMealsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Meals").font(.title3.bold()).foregroundColor(themeManager.current.primaryText)
                Spacer()
                Button(action: { showMealHistory = true }) {
                    HStack(spacing: 4) { Text("View All"); Image(systemName: "chevron.right") }
                        .font(.caption).foregroundColor(.orange)
                }
            }
            if isLoading && meals.isEmpty {
                HStack {
                    Spacer()
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    Text("Loading meals...").font(.caption).foregroundColor(themeManager.current.secondaryText)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if meals.isEmpty {
                EmptyMealsStateCard()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(meals.prefix(6))) { meal in
                            FixedSizeMealCard(meal: meal).onTapGesture { selectedMealForDetail = meal }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Nutrition Overview

    var comprehensiveNutritionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Nutrition Overview").font(.title3.bold()).foregroundColor(themeManager.current.primaryText)
                Spacer()
                HStack(spacing: 2) {
                    ForEach([(0, "Today"), (1, "Week")], id: \.0) { tab, label in
                        Button(action: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { selectedSummaryTab = tab }
                        }) {
                            Text(label).font(.caption)
                                .fontWeight(selectedSummaryTab == tab ? .semibold : .regular)
                                .foregroundColor(selectedSummaryTab == tab ? .black : themeManager.current.primaryText)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedSummaryTab == tab ? Color.orange : Color.clear)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: selectedSummaryTab))
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(themeManager.current.inputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeManager.current.cardBorder, lineWidth: 1)))
            }
            ZStack {
                if selectedSummaryTab == 0 {
                    todaysCircularNutritionView
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    WeeklyNutritionOverview(avgCalories: monthlyAvgCalories, targetCalories: dynamicCalorieGoal,
                                            mealsLogged: weeklyMeals, streak: currentStreak)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: selectedSummaryTab)
        }
    }

    var todaysCircularNutritionView: some View {
        let todaysNutritionText = createTodaysNutritionText()
        return Group {
            if !todaysNutritionText.isEmpty {
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        TodaysNutrientCircle(title: "Protein", current: totalProtein, target: calculateProteinGoal(), unit: "g", color: .blue, icon: "bolt.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Carbs", current: totalCarbs, target: calculateCarbGoal(), unit: "g", color: .green, icon: "leaf.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Fat", current: totalFat, target: calculateFatGoal(), unit: "g", color: .yellow, icon: "drop.fill")
                            .environmentObject(themeManager)
                    }
                    HStack(spacing: 16) {
                        TodaysNutrientCircle(title: "Fiber", current: totalFiber, target: 25, unit: "g", color: .brown, icon: "circle.grid.2x2.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Sugar", current: totalSugar, target: 50, unit: "g", color: .pink, icon: "heart.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Sodium", current: totalSodium, target: 2300, unit: "mg", color: .red, icon: "triangle.fill")
                            .environmentObject(themeManager)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1)))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie").font(.system(size: 40)).foregroundColor(.orange.opacity(0.6))
                    Text("No nutrition data today").font(.headline).foregroundColor(themeManager.current.primaryText)
                    Text("Add your first meal to see detailed nutrition breakdown").font(.caption)
                        .foregroundColor(themeManager.current.secondaryText).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8])).foregroundColor(.orange.opacity(0.3))))
            }
        }
    }

    var enhancedFloatingUploadButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { withAnimation(.spring()) { showUploadMeal = true } }) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Add Meal")
                    }
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.orange, Color.orange.opacity(0.8)]),
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(25).shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding()
            }
        }
    }

    // MARK: - Data Functions

    func initializeDashboard() {
        guard !hasInitialized else { return }
        hasInitialized = true
        loadUserPreferences()
        if profileManager.userProfile == nil && !profileManager.isNewUser { profileManager.fetchProfile() }
        fetchAllData(); calculateStreak()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.8)) { animateCalories = true }
        }
    }

    func fetchAllData() { fetchMeals(); fetchWaterData(); fetchExerciseData(); fetchWeightData() }

    func loadUserPreferences() {
        if let profile = profileManager.userProfile { calorieGoal = profile.calorieTarget }
        else if let saved = UserDefaults.standard.object(forKey: "calorie_target") as? Int { calorieGoal = saved }
    }

    func fetchMeals() {
        guard let userId = getCurrentUserId(), let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-meals?user_id=\(userId)") else {
            networkError = .noInternet; return
        }
        isLoading = true
        var request = URLRequest(url: url); request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.isLoading = false }
            if let error = error { DispatchQueue.main.async { self.networkError = .dataLoadFailed; print("❌ \(error.localizedDescription)") }; return }
            guard let data = data else { DispatchQueue.main.async { self.networkError = .dataLoadFailed }; return }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 { DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return }
                else if httpResponse.statusCode != 200 { DispatchQueue.main.async { self.networkError = .serverError }; return }
            }
            do {
                let decoded = try JSONDecoder().decode([Meal].self, from: data)
                DispatchQueue.main.async {
                    var uniqueMeals: [Meal] = []; var seenIds: Set<String> = []
                    for meal in decoded { if !seenIds.contains(meal._id) { seenIds.insert(meal._id); uniqueMeals.append(meal) } }
                    self.meals = uniqueMeals.sorted {
                        guard let d1 = ISO8601DateFormatter().date(from: $0.saved_at ?? ""),
                              let d2 = ISO8601DateFormatter().date(from: $1.saved_at ?? "") else { return false }
                        return d1 > d2
                    }
                    self.calculateStats(); self.calculateWeeklyStats()
                }
            } catch { DispatchQueue.main.async { self.networkError = .dataLoadFailed } }
        }.resume()
    }

    func fetchWaterData() {
        guard let userId = getCurrentUserId(), let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-water?user_id=\(userId)") else { return }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 { DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return }
                else if httpResponse.statusCode != 200 { return }
            }
            if let decoded = try? JSONDecoder().decode([WaterEntry].self, from: data) {
                DispatchQueue.main.async { self.waterIntake = decoded; self.calculateWaterStats() }
            }
        }.resume()
    }

    func fetchExerciseData() {
        guard let userId = getCurrentUserId(), let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-exercise?user_id=\(userId)") else { return }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 { DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return }
                else if httpResponse.statusCode != 200 { return }
            }
            if let decoded = try? JSONDecoder().decode([ExerciseEntry].self, from: data) {
                DispatchQueue.main.async { self.exerciseEntries = decoded; self.calculateExerciseStats() }
            }
        }.resume()
    }

    func fetchWeightData() {
        guard let userId = getCurrentUserId(), let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-weight?user_id=\(userId)") else { return }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 { DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return }
                else if httpResponse.statusCode != 200 { return }
            }
            if let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data) {
                DispatchQueue.main.async { self.weightEntries = decoded.sorted { $0.recorded_at > $1.recorded_at }; self.calculateWeightStats() }
            }
        }.resume()
    }

    func calculateStats() {
        let calendar = Calendar.current; let today = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let isoFormatter = ISO8601DateFormatter(); isoFormatter.timeZone = TimeZone.current
        var todayCal = 0, todayProt = 0, todayCarb = 0, todayFt = 0, todayFib = 0, todaySug = 0, todaySod = 0
        var monthlyCal = 0, monthlyDays = Set<String>()
        for meal in meals {
            guard let savedAt = meal.saved_at, let validDate = isoFormatter.date(from: savedAt) else { continue }
            let n = extractAllNutrients(from: meal.nutrition_info)
            if calendar.isDateInToday(validDate) {
                todayCal += n.calories; todayProt += n.protein; todayCarb += n.carbs; todayFt += n.fat
                todayFib += n.fiber; todaySug += n.sugar; todaySod += n.sodium
            }
            if validDate >= startOfMonth {
                monthlyCal += n.calories
                let dc = calendar.dateComponents([.year, .month, .day], from: validDate)
                monthlyDays.insert("\(dc.year!)-\(dc.month!)-\(dc.day!)")
            }
        }
        withAnimation {
            todayCalories = todayCal; totalProtein = todayProt; totalCarbs = todayCarb; totalFat = todayFt
            totalFiber = todayFib; totalSugar = todaySug; totalSodium = todaySod
            monthlyCalories = monthlyCal
            monthlyAvgCalories = monthlyDays.count > 0 ? monthlyCal / monthlyDays.count : 0
        }
    }

    func extractAllNutrients(from text: String) -> (calories: Int, protein: Int, carbs: Int, fat: Int, fiber: Int, sugar: Int, sodium: Int) {
        var calories = 0, protein = 0, carbs = 0, fat = 0, fiber = 0, sugar = 0, sodium = 0
        for line in text.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, let floatVal = Float(parts[1].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) {
                let value = Int(floatVal.rounded()); let name = parts[0].lowercased()
                if name.contains("calorie") || name.contains("kcal") { calories = value }
                else if name.contains("protein") { protein = value }
                else if name.contains("carb") { carbs = value }
                else if (name.contains("fat") || name == "fats") && !name.contains("saturated") && !name.contains("trans") { fat = value }
                else if name.contains("fiber") || name.contains("fibre") { fiber = value }
                else if name.contains("sugar") && !name.contains("added") { sugar = value }
                else if name.contains("sodium") || name.contains("salt") { sodium = value }
            }
        }
        return (calories, protein, carbs, fat, fiber, sugar, sodium)
    }

    func createTodaysNutritionText() -> String {
        let todaysMeals = meals.filter { isSameDay($0.saved_at) }
        if todaysMeals.isEmpty { return "" }
        var totalCal = 0, totalProt = 0, totalCarb = 0, totalFt = 0, totalFib = 0, totalSug = 0, totalSod = 0
        for meal in todaysMeals {
            let n = extractAllNutrients(from: meal.nutrition_info)
            totalCal += n.calories; totalProt += n.protein; totalCarb += n.carbs
            totalFt += n.fat; totalFib += n.fiber; totalSug += n.sugar; totalSod += n.sodium
        }
        DispatchQueue.main.async {
            self.totalProtein = totalProt; self.totalCarbs = totalCarb; self.totalFat = totalFt
            self.totalFiber = totalFib; self.totalSugar = totalSug; self.totalSodium = totalSod
        }
        return "Calories|\(totalCal)|kcal\nProtein|\(totalProt)|g\nFat|\(totalFt)|g\nCarbohydrates|\(totalCarb)|g\nFiber|\(totalFib)|g\nSugar|\(totalSug)|g\nSodium|\(totalSod)|mg"
    }

    func calculateWaterStats() {
        let calendar = Calendar.current; let today = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? today
        var tw = 0.0; var ww: [Double] = []
        for entry in waterIntake {
            if let d = ISO8601DateFormatter().date(from: entry.recorded_at) {
                if calendar.isDate(d, inSameDayAs: today) { tw += entry.amount }
                if d >= startOfWeek { ww.append(entry.amount) }
            }
        }
        withAnimation { todayWater = tw; weeklyAvgWater = ww.isEmpty ? 0 : ww.reduce(0, +) / Double(ww.count) }
    }

    func calculateExerciseStats() {
        let calendar = Calendar.current; let today = calendar.startOfDay(for: Date())
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? today
        var te = 0, we = 0
        for entry in exerciseEntries {
            if let d = ISO8601DateFormatter().date(from: entry.recorded_at) {
                if calendar.isDate(d, inSameDayAs: today) { te += entry.duration }
                if d >= startOfWeek { we += entry.duration }
            }
        }
        withAnimation { todayExercise = te; weeklyExercise = we }
    }

    func calculateWeightStats() {
        if let latest = weightEntries.first { withAnimation { currentWeight = latest.weight } }
    }

    func calculateWeeklyStats() {
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        weeklyMeals = meals.filter { meal in
            guard let s = meal.saved_at, let d = ISO8601DateFormatter().date(from: s) else { return false }
            return d >= startOfWeek
        }.count
    }

    func calculateStreak() {
        let calendar = Calendar.current; var streak = 0; var currentDate = calendar.startOfDay(for: Date())
        for _ in 0..<30 {
            let hasM = meals.contains { meal in
                guard let s = meal.saved_at, let d = ISO8601DateFormatter().date(from: s) else { return false }
                return calendar.isDate(d, inSameDayAs: currentDate)
            }
            if hasM { streak += 1; currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate } else { break }
        }
        withAnimation { currentStreak = streak }
    }

    func handleNetworkErrorRetry() { networkError = nil; fetchAllData(); profileManager.fetchProfile(force: true) }

    func getCurrentUserId() -> String? {
        session.userID.isEmpty ? UserDefaults.standard.string(forKey: "user_id") : session.userID
    }

    func isSameDay(_ dateString: String?) -> Bool {
        guard let dateString = dateString else { return false }
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone.current
        guard let mealDate = formatter.date(from: dateString) else { return false }
        return Calendar.current.isDateInToday(mealDate)
    }

    func extractNutrient(name: String, from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains(name.lowercased()) { return Int(parts[1]) }
        }
        return nil
    }

    func refreshDashboard() async {
        await withCheckedContinuation { continuation in
            hasInitialized = false; networkError = nil
            profileManager.fetchProfile(force: true); fetchAllData(); calculateStreak()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { continuation.resume() }
        }
    }

    func calculateProteinGoal() -> Int { Int(Double(dynamicCalorieGoal) * 0.2 / 4) }
    func calculateCarbGoal() -> Int { Int(Double(dynamicCalorieGoal) * 0.5 / 4) }
    func calculateFatGoal() -> Int { Int(Double(dynamicCalorieGoal) * 0.3 / 9) }
}

// MARK: - Supporting Views

struct WelcomeNewUserCard: View {
    let action: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(LinearGradient(gradient: Gradient(colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.1)]),
                                             startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 80, height: 80)
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 40))
                    .foregroundStyle(LinearGradient(colors: [.orange, .orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            VStack(spacing: 12) {
                Text("Welcome to NutriSnap!").font(.title3.bold()).foregroundColor(.white)
                Text("Let's set up your nutrition profile to get personalized recommendations and accurate tracking")
                    .font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                Button(action: action) {
                    HStack { Image(systemName: "arrow.right.circle.fill"); Text("Set Up Profile") }
                        .fontWeight(.semibold).foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .cornerRadius(12).shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                Text("Takes less than 2 minutes").font(.caption).foregroundColor(.gray)
            }
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24)
            .fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)]),
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 24)
                .stroke(LinearGradient(colors: [Color.orange.opacity(0.4), Color.orange.opacity(0.2)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)))
        .shadow(color: .orange.opacity(0.1), radius: 20, x: 0, y: 10)
    }
}

// ✅ 修复：加 @EnvironmentObject，所有颜色改为 theme
struct TodaysNutrientCircle: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let current: Int; let target: Int; let unit: String; let color: Color; let icon: String
    var progress: Double { guard target > 0 else { return 0 }; return min(Double(current) / Double(target), 1.0) }
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 8).frame(width: 70, height: 70)
                Circle().trim(from: 0, to: progress)
                    .stroke(LinearGradient(gradient: Gradient(colors: [color, color.opacity(0.7)]),
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 70, height: 70).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.2, dampingFraction: 0.8), value: progress)
                VStack(spacing: 1) {
                    Text("\(current)").font(.system(size: 16, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("\(unit)").font(.system(size: 8))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
                Text(title).font(.caption2)
                    .foregroundColor(themeManager.current.primaryText).fontWeight(.medium)
                Text("\(target) \(unit)").font(.caption2)
                    .foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeeklyNutritionOverview: View {
    let avgCalories: Int; let targetCalories: Int; let mealsLogged: Int; let streak: Int
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                WeeklyStatCircle(title: "Avg Calories", value: avgCalories, target: targetCalories, unit: "kcal", color: .orange)
                WeeklyStatCircle(title: "Meals", value: mealsLogged, target: 21, unit: "logged", color: .green)
                WeeklyStatCircle(title: "Streak", value: streak, target: 7, unit: "days", color: .purple)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("This Week's Progress").font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                HStack { Circle().fill(Color.green.opacity(0.3)).frame(width: 8, height: 8); Text("You've logged \(mealsLogged) meals this week").font(.caption).foregroundColor(.gray); Spacer() }
                if streak > 0 {
                    HStack { Circle().fill(Color.orange.opacity(0.3)).frame(width: 8, height: 8); Text("Current tracking streak: \(streak) days").font(.caption).foregroundColor(.gray); Spacer() }
                }
            }
            .padding().background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1)))
    }
}

struct WeeklyStatCircle: View {
    let title: String; let value: Int; let target: Int; let unit: String; let color: Color
    var progress: Double { guard target > 0 else { return 0 }; return min(Double(value) / Double(target), 1.0) }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 6).frame(width: 60, height: 60)
                Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: progress)
                Text("\(value)").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            VStack(spacing: 2) {
                Text(title).font(.caption2).foregroundColor(.white).fontWeight(.medium)
                Text(unit).font(.caption2).foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyMealsStateCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundColor(.orange.opacity(0.6))
            VStack(spacing: 4) {
                Text("No meals yet").font(.headline).foregroundColor(themeManager.current.primaryText)
                Text("Start tracking...").font(.caption).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .background(RoundedRectangle(cornerRadius: 16).fill(themeManager.current.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5])).foregroundColor(themeManager.current.cardBorder)))
    }
}

struct NutritionDisplayItem {
    let name: String; let value: String; let unit: String; let color: Color
}

struct FixedSizeMealCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let meal: Meal
    @State private var isPressed = false
    @State private var imageLoaded = false
    var body: some View {
        VStack(spacing: 0) { imageSection; contentSection }
        .frame(width: 180, height: 180)
        .background(RoundedRectangle(cornerRadius: 20).fill(themeManager.current.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(themeManager.current.cardBorder, lineWidth: 1)))
        .scaleEffect(isPressed ? 0.98 : 1.0).animation(.easeInOut(duration: 0.15), value: isPressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeInOut(duration: 0.1)) { isPressed = true } }
            .onEnded { _ in withAnimation(.easeInOut(duration: 0.1)) { isPressed = false } })
    }
    private var imageSection: some View {
        ZStack {
            Rectangle().fill(themeManager.current.inputBackground)
            Group {
                if let base64 = meal.image_thumb ?? meal.image_full, !base64.isEmpty,
                   let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                        .opacity(imageLoaded ? 1 : 0).onAppear { withAnimation(.easeInOut(duration: 0.3)) { imageLoaded = true } }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.title2).foregroundColor(.gray.opacity(0.6))
                        Text("No Image").font(.caption2).foregroundColor(.gray.opacity(0.8))
                    }
                }
            }
            LinearGradient(gradient: Gradient(colors: [Color.clear, Color.black.opacity(0.15)]), startPoint: .center, endPoint: .bottom)
            caloriesBadgeOverlay
        }
        .frame(width: 180, height: 110).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private var caloriesBadgeOverlay: some View {
        VStack {
            HStack {
                Spacer()
                if let calories = extractMealCalories(from: meal.nutrition_info) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 8)).foregroundColor(.orange)
                        Text("\(calories)").font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3).background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(.top, 6).padding(.trailing, 6)
                }
            }
            Spacer()
        }
    }
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meal.dish_prediction).font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
                .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 2)
            metadataSection
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let mealType = meal.meal_type {
                HStack(spacing: 3) {
                    Image(systemName: getMealTypeIcon(for: mealType)).font(.system(size: 9)).foregroundColor(.orange.opacity(0.8))
                    Text(mealType).font(.system(size: 10)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            if let savedAt = meal.saved_at, let date = ISO8601DateFormatter().date(from: savedAt) {
                Text(formatMealDateTime(date)).font(.system(size: 9)).foregroundColor(themeManager.current.secondaryText)
            }
        }
    }
    private func extractMealCalories(from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calorie") { return Int(parts[1]) }
        }
        return nil
    }
    private func formatMealDateTime(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date) }
        else if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        else { let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date) }
    }
    private func getMealTypeIcon(for mealType: String) -> String {
        switch mealType.lowercased() {
        case "breakfast": return "sun.max.fill"
        case "lunch": return "sun.min.fill"
        case "dinner": return "moon.stars.fill"
        case "evening snacks", "snacks": return "cup.and.saucer.fill"
        default: return "fork.knife"
        }
    }
}
