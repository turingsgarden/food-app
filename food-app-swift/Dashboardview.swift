//  DashBoardView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/8/26.
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
    @State private var monthlyCalories: Int = 0
    @State private var monthlyAvgCalories: Int = 0
    @State private var weeklyExercise: Int = 0
    @State private var weeklyMeals: Int = 0
    @State private var isLoading = false
    @State private var showMealHistory = false
    @State private var showUploadMeal = false
    @State private var showProfile = false
    @State private var showWaterTracking = false
    @State private var showExerciseTracking = false
    @State private var showWeightTracking = false
    @State private var animateCalories = false
    @State private var calorieGoal: Int = 2000
    @State private var hasInitialized = false
    @State private var showNetworkAlert = false
    @State private var networkError: NetworkError?
    @State private var selectedMealForDetail: Meal?
    @State private var currentStreak: Int = 0
    @State private var selectedDate: Date = Date()
    @State private var selectedWeekStart: Date = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    @State private var selectedMonth: Date = Date()
    @State private var selectedTimeFilter: String = "Daily"
    @State private var showTimePicker = false
    @State private var nutritionPage: Int = 0
    @State private var healthReportCalorieGoal: Int? = nil


    var filteredNutrition: (protein: Int, carbs: Int, fat: Int, fiber: Int, sugar: Int, sodium: Int) {
        var p = 0, c = 0, f = 0, fi = 0, s = 0, so = 0
        for meal in filteredMealsForDisplay {
            let n = extractAllNutrients(from: meal.nutrition_info)
            p += n.protein; c += n.carbs; f += n.fat
            fi += n.fiber; s += n.sugar; so += n.sodium
        }
        return (p, c, f, fi, s, so)
    }

    enum NetworkError: Identifiable {
        case noInternet, serverError, dataLoadFailed, sessionExpired
        var id: String { "\(self)" }
        var title: String {
            switch self {
            case .noInternet: return "No Internet"
            case .serverError: return "Server Error"
            case .dataLoadFailed: return "Load Failed"
            case .sessionExpired: return "Session Expired"
            }
        }
        var message: String {
            switch self {
            case .noInternet: return "Check your internet connection."
            case .serverError: return "Server issue. Try again later."
            case .dataLoadFailed: return "Failed to load. Pull to refresh."
            case .sessionExpired: return "Session expired. Please log in."
            }
        }
    }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "Good Morning ☀️" }
        if h < 17 { return "Good Afternoon 🌤" }
        return "Good Evening 🌙"
    }

    var userName: String { session.userName.isEmpty ? "Friend" : session.userName }
    var dynamicCalorieGoal: Int {
        if let r = healthReportCalorieGoal { return r }
        return profileManager.userProfile?.calorieTarget ?? calorieGoal
    }

    var displayedCalories: Int { filteredMealsForDisplay.reduce(0) { $0 + extractCaloriesInt(from: $1.nutrition_info) } }

    var displayedGoal: Int {
        switch selectedTimeFilter {
        case "Daily": return dynamicCalorieGoal
        case "Weekly": return dynamicCalorieGoal * 7
        case "Monthly":
            let days = Calendar.current.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
            return dynamicCalorieGoal * days
        default: return dynamicCalorieGoal
        }
    }

    var calorieProgress: Double {
        guard displayedGoal > 0 else { return 0 }
        return min(Double(displayedCalories) / Double(displayedGoal), 1.0)
    }


    var filteredMealsForDisplay: [Meal] {
        let cal = Calendar.current
        switch selectedTimeFilter {
        case "Daily":
            return meals.filter { meal in
                guard let s = meal.saved_at, let d = parseISO8601(s) else { return false }
                return cal.isDate(d, inSameDayAs: selectedDate)
            }
        case "Weekly":
            let end = cal.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
            return meals.filter { meal in
                guard let s = meal.saved_at, let d = parseISO8601(s) else { return false }
                return d >= selectedWeekStart && d < end
            }
        case "Monthly":
            guard let interval = cal.dateInterval(of: .month, for: selectedMonth) else { return [] }
            return meals.filter { meal in
                guard let s = meal.saved_at, let d = parseISO8601(s) else { return false }
                return d >= interval.start && d < interval.end
            }
        default:
            return meals.filter { meal in
                guard let s = meal.saved_at, let d = parseISO8601(s) else { return false }
                return Calendar.current.isDateInToday(d)
            }
        }
    }

    var mealsSectionTitle: String {
        let cal = Calendar.current
        switch selectedTimeFilter {
        case "Daily":
            if cal.isDateInToday(selectedDate) { return "Today's Meals" }
            if cal.isDateInYesterday(selectedDate) { return "Yesterday's Meals" }
            let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: selectedDate) + "'s Meals"
        case "Weekly":
            let end = cal.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return f.string(from: selectedWeekStart) + " – " + f.string(from: end)
        case "Monthly":
            let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: selectedMonth) + "'s Meals"
        default: return "Today's Meals"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                themeManager.current.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                       
                        headerSection
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                           
                            .overlay(alignment: .topTrailing) {
                                if showTimePicker {
                                    timePickerDropdown
                                        
                                        .offset(x: -20, y: 56)
                                        .zIndex(999)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)
                                        ))
                                }
                            }
                            .zIndex(showTimePicker ? 999 : 0)

                        
                        dateScrollSelector
                            .padding(.bottom, 16)

                        VStack(spacing: 16) {
                            if profileManager.isNewUser { WelcomeNewUserCard { showProfile = true } }
                            if let netErr = networkError { networkErrorSection(netErr) }
                            else if profileManager.isLoading && profileManager.userProfile == nil && !profileManager.isNewUser {
                                profileLoadingSection
                            }

                            DailyHealthBanner()

                            calorieMainCard

                            if !filteredMealsForDisplay.isEmpty { comprehensiveNutritionSection }

                            todayMealsSection

                            Spacer(minLength: 100)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .refreshable { await refreshDashboard() }

                calStyleFloatingButton
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .onAppear { initializeDashboard() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MealSaved"))) { _ in fetchAllData() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NutritionRecalculated"))) { notification in
                guard let mealId = notification.userInfo?["mealId"] as? String,
                      let nutritionInfo = notification.userInfo?["nutritionInfo"] as? String else { return }
                if let index = meals.firstIndex(where: { $0._id == mealId }) {
                    meals[index].nutrition_info = nutritionInfo
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { fetchAllData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WaterAdded"))) { _ in fetchWaterData() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExerciseAdded"))) { _ in fetchExerciseData() }
            .onReceive(profileManager.$userProfile) { newProfile in
                if let profile = newProfile { withAnimation { calorieGoal = profile.calorieTarget } }
            }
            .sheet(isPresented: $showMealHistory) { MealHistoryView().environmentObject(themeManager) }
            .sheet(isPresented: $showUploadMeal) { BatchUploadView().environmentObject(themeManager) }
            .sheet(isPresented: $showProfile) {
                ProfileView().environmentObject(themeManager)
                    .onDisappear { profileManager.fetchProfile(force: true) }
            }
            .sheet(isPresented: $showWaterTracking) { WaterTrackingView().environmentObject(themeManager) }
            .sheet(isPresented: $showExerciseTracking) { ExerciseTrackingView().environmentObject(themeManager) }
            .sheet(isPresented: $showWeightTracking) { WeightTrackingView().environmentObject(themeManager) }
            .sheet(item: $selectedMealForDetail) { meal in
                NavigationView { MealDetailView(meal: meal).environmentObject(themeManager) }
            }
            .alert(networkError?.title ?? "Error", isPresented: $showNetworkAlert) {
                if networkError == .sessionExpired { Button("Login") { session.logout() } }
                else { Button("Retry") { handleNetworkErrorRetry() } }
                Button("Cancel", role: .cancel) { networkError = nil }
            } message: { Text(networkError?.message ?? "") }
        }
    }

    // MARK: - Header

    var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting).font(.system(size: 13, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                Text(userName).font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
            }
            Spacer()
            HStack(spacing: 10) {
                if currentStreak > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                        Text("\(currentStreak)").font(.system(size: 14, weight: .bold))
                            .foregroundColor(themeManager.current.primaryText)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(themeManager.current.cardBackground).cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(themeManager.current.cardBorder, lineWidth: 1))
                }

              
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showTimePicker.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Text(selectedTimeFilter)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                        Image(systemName: showTimePicker ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(themeManager.current == .dark ? Color.white : Color.black)
                    .cornerRadius(20)
                }
                .buttonStyle(.plain)

           
                Button(action: { showProfile = true }) {
                    ZStack(alignment: .topTrailing) {
                        Circle().fill(themeManager.current.inputBackground).frame(width: 40, height: 40)
                            .overlay(Text(String(userName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(themeManager.current.primaryText))
                        Circle()
                            .fill(profileManager.userProfile != nil ? Color.green : Color.orange)
                            .frame(width: 10, height: 10).offset(x: 2, y: -2)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if showTimePicker { withAnimation { showTimePicker = false } }
        }
    }

    
    var timePickerDropdown: some View {
        VStack(spacing: 0) {
            ForEach(["Daily", "Weekly", "Monthly"], id: \.self) { option in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTimeFilter = option
                        showTimePicker = false
                    }
                }) {
                    HStack {
                        Text(option)
                            .font(.system(size: 14, weight: selectedTimeFilter == option ? .bold : .regular))
                            .foregroundColor(selectedTimeFilter == option
                                ? (themeManager.current == .dark ? .black : .white)
                                : themeManager.current.primaryText)
                        Spacer()
                        if selectedTimeFilter == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(themeManager.current == .dark ? .black : .white)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(selectedTimeFilter == option
                        ? (themeManager.current == .dark ? Color.white : Color.black)
                        : themeManager.current.cardBackground)
                }
                .buttonStyle(.plain)
                if option != "Monthly" {
                    Divider().background(themeManager.current.cardBorder)
                }
            }
        }
        .frame(width: 150)
        .background(themeManager.current.cardBackground)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(themeManager.current.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(themeManager.current == .dark ? 0.4 : 0.12), radius: 16, x: 0, y: 8)
    }




    var datesWithMeals: Set<String> {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return Set(meals.compactMap { meal -> String? in
            guard let s = meal.saved_at, let d = parseISO8601(s) else { return nil }
            return f.string(from: d)
        })
    }

    @ViewBuilder
    var dateScrollSelector: some View {
        switch selectedTimeFilter {
        case "Daily":
            DailyScrollPicker(selectedDate: $selectedDate, datesWithMeals: datesWithMeals)
        case "Weekly":
            WeeklyChipPicker(selectedWeekStart: $selectedWeekStart)
                .padding(.horizontal, 20)
        case "Monthly":
            MonthChipPicker(selectedMonth: $selectedMonth)
                .padding(.horizontal, 20)
        default:
            EmptyView()
        }
    }

    // MARK: - Calorie Card

    var calorieMainCard: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTimeFilter == "Daily" ? "Daily Calories"
                     : selectedTimeFilter == "Weekly" ? "Weekly Calories" : "Monthly Calories")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                    .textCase(.uppercase).tracking(0.5)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(animateCalories ? displayedCalories : 0)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundColor(themeManager.current.primaryText)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: displayedCalories)
                    Text("/ \(displayedGoal) kcal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.current.secondaryText).padding(.bottom, 4)
                }

                Text(getCalorieStatusMessage())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(calorieProgressColor)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 4).fill(calorieProgressColor)
                            .frame(width: geo.size.width * (animateCalories ? calorieProgress : 0), height: 6)
                            .animation(.easeOut(duration: 1.0), value: calorieProgress)
                    }
                }
                .frame(height: 6)
            }
            Spacer()
            ZStack {
                Circle().stroke(Color.gray.opacity(0.12), lineWidth: 10).frame(width: 90, height: 90)
                Circle().trim(from: 0, to: animateCalories ? calorieProgress : 0)
                    .stroke(calorieProgressColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 90, height: 90).rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: calorieProgress)
                VStack(spacing: 2) {
                    Text("\(Int(calorieProgress * 100))%")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Image(systemName: "flame.fill").font(.system(size: 10)).foregroundColor(calorieProgressColor)
                }
            }
        }
        .padding(20).background(themeManager.current.cardBackground).cornerRadius(22)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(themeManager.current.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(themeManager.current == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }

    var calorieProgressColor: Color {
        if calorieProgress < 0.5 { return .green }
        if calorieProgress < 1.0 { return .orange }
        return .red
    }



    var comprehensiveNutritionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nutrition Overview")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Spacer()
                Text(selectedTimeFilter)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(themeManager.current == .dark ? Color.white : Color.black))
            }

            if selectedTimeFilter == "Daily" {
                dailyNutritionPager
            } else {
                weeklyNutritionOverview
            }
        }
    }

    var dailyNutritionPager: some View {
        VStack(spacing: 10) {
            TabView(selection: $nutritionPage) {
                
                unifiedNutritionCircles.tag(0)
             
                dailySummaryCircles.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 160)
            .background(themeManager.current.cardBackground)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))

            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
                    Capsule()
                        .fill(i == nutritionPage
                              ? (themeManager.current == .dark ? Color.white : Color.black)
                              : themeManager.current.cardBorder)
                        .frame(width: i == nutritionPage ? 16 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: nutritionPage)
                }
            }
        }
    }


    var unifiedNutritionCircles: some View {
        let nut = filteredNutrition
        let accentColor = Color(red: 0.95, green: 0.61, blue: 0.20)

        return HStack(spacing: 0) {
            ForEach([
                ("Protein",  nut.protein,  calculateProteinGoal(), "g"),
                ("Carbs",    nut.carbs,    calculateCarbGoal(),    "g"),
                ("Fat",      nut.fat,      calculateFatGoal(),     "g"),
                ("Fiber",    nut.fiber,    25,                     "g"),
                ("Sugar",    nut.sugar,    50,                     "g"),
                ("Sodium",   nut.sodium,   2300,                   "mg"),
            ], id: \.0) { title, current, target, unit in
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(accentColor.opacity(0.15), lineWidth: 5)
                            .frame(width: 46, height: 46)
                        let progress = target > 0 ? min(Double(current) / Double(target), 1.0) : 0.0
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                progress >= 1.0 ? Color.red : accentColor,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .frame(width: 46, height: 46)
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 1.0, dampingFraction: 0.8), value: progress)
                        VStack(spacing: 0) {
                            Text(current >= 1000 ? "\(current/1000)k" : "\(current)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(themeManager.current.primaryText)
                                .minimumScaleFactor(0.5).lineLimit(1)
                            Text(unit)
                                .font(.system(size: 7))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                    }
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(themeManager.current.secondaryText)
                        .lineLimit(1)
                    Text("\(target)\(unit)")
                        .font(.system(size: 8))
                        .foregroundColor(themeManager.current.secondaryText.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 4)
    }

    var dailySummaryCircles: some View {
        HStack(spacing: 0) {
            summaryCircle(title: "Calories", value: displayedCalories, target: dynamicCalorieGoal, unit: "kcal", color: .orange)
            Divider().frame(height: 50).background(themeManager.current.cardBorder)
            summaryCircle(title: "Meals", value: filteredMealsForDisplay.count, target: 5, unit: "today", color: Color(red: 0.35, green: 0.75, blue: 0.45))
            Divider().frame(height: 50).background(themeManager.current.cardBorder)
            summaryCircle(title: "Streak", value: currentStreak, target: 7, unit: "days", color: .purple)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 8)
    }

    func summaryCircle(title: String, value: Int, target: Int, unit: String, color: Color) -> some View {
        let progress = target > 0 ? min(Double(value) / Double(target), 1.0) : 0.0
        return VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 6).frame(width: 60, height: 60)
                Circle().trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: progress)
                Text("\(value)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                    .minimumScaleFactor(0.5).lineLimit(1).padding(.horizontal, 4)
            }
            VStack(spacing: 2) {
                Text(title).font(.caption2).foregroundColor(themeManager.current.primaryText).fontWeight(.semibold)
                Text(unit).font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    var weeklyNutritionOverview: some View {
        let avgCal = selectedTimeFilter == "Weekly"
            ? (filteredMealsForDisplay.isEmpty ? 0 : displayedCalories / max(1, filteredMealsForDisplay.count))
            : monthlyAvgCalories

        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                weeklyStatCircle(title: "Avg Cal", value: avgCal, target: dynamicCalorieGoal, unit: "kcal", color: .orange)
                weeklyStatCircle(title: "Meals", value: filteredMealsForDisplay.count, target: selectedTimeFilter == "Weekly" ? 21 : 90, unit: "logged", color: Color(red: 0.35, green: 0.75, blue: 0.45))
                weeklyStatCircle(title: "Streak", value: currentStreak, target: 7, unit: "days", color: .purple)
            }
            if filteredMealsForDisplay.count > 0 {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 0.35, green: 0.75, blue: 0.45).opacity(0.5)).frame(width: 6, height: 6)
                    Text("You've logged \(filteredMealsForDisplay.count) meals \(selectedTimeFilter == "Weekly" ? "this week" : "this month")")
                        .font(.caption).foregroundColor(themeManager.current.secondaryText)
                    Spacer()
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(themeManager.current.inputBackground))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(themeManager.current.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1)))
    }

    func weeklyStatCircle(title: String, value: Int, target: Int, unit: String, color: Color) -> some View {
        let progress = target > 0 ? min(Double(value) / Double(target), 1.0) : 0.0
        return VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 6).frame(width: 60, height: 60)
                Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: progress)
                Text("\(value)").font(.system(size: 14, weight: .bold)).foregroundColor(themeManager.current.primaryText)
            }
            VStack(spacing: 2) {
                Text(title).font(.caption2).foregroundColor(themeManager.current.primaryText).fontWeight(.medium)
                Text(unit).font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Meals Section

    var todayMealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mealsSectionTitle).font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Spacer()
                Button(action: { showMealHistory = true }) {
                    Text("See all").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }
            if filteredMealsForDisplay.isEmpty {
                EmptyMealsStateCard()
            } else {
                ForEach(Array(filteredMealsForDisplay.prefix(3))) { meal in
                    Button(action: { selectedMealForDetail = meal }) {
                        MealListRow(meal: meal)
                    }
                    .buttonStyle(.plain)
                }
                if filteredMealsForDisplay.count > 3 {
                    Button(action: { showMealHistory = true }) {
                        HStack(spacing: 5) {
                            Text("+ \(filteredMealsForDisplay.count - 3) more meals")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(themeManager.current.secondaryText)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(themeManager.current.inputBackground).cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Floating Button

    var calStyleFloatingButton: some View {
        Button(action: { withAnimation(.spring()) { showUploadMeal = true } }) {
            ZStack {
                Circle().fill(themeManager.current == .dark ? Color.white : Color.black)
                    .frame(width: 60, height: 60)
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                Image(systemName: "plus").font(.system(size: 22, weight: .bold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
            }
        }
        .padding(.trailing, 20).padding(.bottom, 28)
    }

    // MARK: - Error States

    func networkErrorSection(_ error: NetworkError) -> some View {
        HStack {
            Image(systemName: "wifi.exclamationmark").foregroundColor(.red).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(.caption).fontWeight(.semibold).foregroundColor(.red)
                Text(error.message).font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
            Spacer()
            Button("Retry") { handleNetworkErrorRetry() }.font(.caption).foregroundColor(.orange)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }

    var profileLoadingSection: some View {
        HStack {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange)).scaleEffect(0.8)
            Text("Loading your profile...").font(.caption).foregroundColor(themeManager.current.secondaryText)
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1)))
    }

    // MARK: - Data Logic

    func getCalorieStatusMessage() -> String {
        let period = selectedTimeFilter == "Daily" ? "today" : selectedTimeFilter == "Weekly" ? "this week" : "this month"
        if calorieProgress < 0.3 { return "Great start \(period)! 💪" }
        if calorieProgress < 0.7 { return "On track \(period) 🎯" }
        if calorieProgress < 1.0 { return "Almost at your goal!" }
        if calorieProgress < 1.2 { return "Goal reached! 🎉" }
        return "Over goal - consider lighter options"
    }

    func initializeDashboard() {
        guard !hasInitialized else { return }
        hasInitialized = true
        loadUserPreferences()
     
        // 1. Fetch profile if needed (fire-and-forget, fast)
        if profileManager.userProfile == nil && !profileManager.isNewUser {
            profileManager.fetchProfile()
        }
     
        // 2. Fetch calorie goal first – when it returns, kick off the rest
        fetchHealthReportCalorieGoal {
            // 3. Now fetch meals + water + exercise together (server is warm)
            self.fetchAllData()
            self.calculateStreak()
        }
     
        // 4. Animate after a short delay regardless
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.8)) { self.animateCalories = true }
        }
    }

    // Completion handler added so initializeDashboard() can chain off it
    func fetchHealthReportCalorieGoal(completion: (() -> Void)? = nil) {
        guard let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/get-health-report")
        else {
            completion?()   // still unblock the chain even on auth error
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
     
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { DispatchQueue.main.async { completion?() } }   // always fires
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dailyCal = json["daily_calories"] as? Int
            else { return }
            DispatchQueue.main.async { self.healthReportCalorieGoal = dailyCal }
        }.resume()
    }
    
    
    
   // MARK: - Parallel data fetch (called after server is known to be warm)
    
   func fetchAllData() { fetchMeals(); fetchWaterData(); fetchExerciseData() }
    

    func loadUserPreferences() {
        if let profile = profileManager.userProfile { calorieGoal = profile.calorieTarget }
        else if let saved = UserDefaults.standard.object(forKey: "calorie_target") as? Int { calorieGoal = saved }
    }

    // MARK: - Individual fetches with tiered timeouts
     
    func fetchMeals() {
        guard let userId = getCurrentUserId(),
              let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-meals?user_id=\(userId)")
        else { networkError = .noInternet; return }
     
        isLoading = true
        var request = URLRequest(url: url)
        request.timeoutInterval = 30          // server already warm at this point
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
     
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.isLoading = false }
     
            if error != nil {
                DispatchQueue.main.async { self.networkError = .dataLoadFailed }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { self.networkError = .dataLoadFailed }
                return
            }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    DispatchQueue.main.async {
                        self.networkError = .sessionExpired
                        self.showNetworkAlert = true
                    }
                    return
                } else if http.statusCode != 200 {
                    DispatchQueue.main.async { self.networkError = .serverError }
                    return
                }
            }
            do {
                let decoded = try JSONDecoder().decode([Meal].self, from: data)
                DispatchQueue.main.async {
                    var uniqueMeals: [Meal] = []
                    var seenIds: Set<String> = []
                    for meal in decoded {
                        if !seenIds.contains(meal._id) {
                            seenIds.insert(meal._id)
                            uniqueMeals.append(meal)
                        }
                    }
                    self.meals = uniqueMeals.sorted {
                        guard let d1 = parseISO8601($0.saved_at ?? ""),
                              let d2 = parseISO8601($1.saved_at ?? "") else { return false }
                        return d1 > d2
                    }
                    self.calculateMonthlyStats()
                    self.calculateWeeklyStats()
                }
            } catch {
                DispatchQueue.main.async { self.networkError = .dataLoadFailed }
            }
        }.resume()
    }
     

    
    func fetchWaterData() {
        guard let userId = getCurrentUserId(),
              let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-water?user_id=\(userId)")
        else { return }
     
        var request = URLRequest(url: url)
        request.timeoutInterval = 15          // lightweight endpoint
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
     
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode([WaterEntry].self, from: data)
            else { return }
            DispatchQueue.main.async { self.waterIntake = decoded }
        }.resume()
    }
    
    func fetchExerciseData() {
        guard let userId = getCurrentUserId(),
              let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/user-exercise?user_id=\(userId)")
        else { return }
     
        var request = URLRequest(url: url)
        request.timeoutInterval = 15          // lightweight endpoint
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
     
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode([ExerciseEntry].self, from: data)
            else { return }
            DispatchQueue.main.async { self.exerciseEntries = decoded }
        }.resume()
    }
    func calculateMonthlyStats() {
        let calendar = Calendar.current; let today = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        var monthlyCal = 0; var monthlyDays = Set<String>()
        for meal in meals {
            guard let savedAt = meal.saved_at, let validDate = parseISO8601(savedAt) else { continue }
            let n = extractAllNutrients(from: meal.nutrition_info)
            if validDate >= startOfMonth {
                monthlyCal += n.calories
                let dc = calendar.dateComponents([.year, .month, .day], from: validDate)
                monthlyDays.insert("\(dc.year!)-\(dc.month!)-\(dc.day!)")
            }
        }
        monthlyCalories = monthlyCal
        monthlyAvgCalories = monthlyDays.count > 0 ? monthlyCal / monthlyDays.count : 0
    }

    func calculateWeeklyStats() {
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        weeklyMeals = meals.filter { meal in
            guard let s = meal.saved_at, let d = parseISO8601(s) else { return false }
            return d >= startOfWeek
        }.count
    }

    func calculateStreak() {
        let calendar = Calendar.current; var streak = 0; var checkDate = calendar.startOfDay(for: Date())
        for _ in 0..<30 {
            let hasM = meals.contains { meal in
                guard let s = meal.saved_at, let d = parseISO8601(s) else { return false }
                return calendar.isDate(d, inSameDayAs: checkDate)
            }
            if hasM { streak += 1; checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate }
            else { break }
        }
        withAnimation { currentStreak = streak }
    }

    func extractAllNutrients(from text: String) -> (calories: Int, protein: Int, carbs: Int, fat: Int, fiber: Int, sugar: Int, sodium: Int) {
        var calories = 0, protein = 0, carbs = 0, fat = 0, fiber = 0, sugar = 0, sodium = 0
        for line in text.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2,
               let v = Float(parts[1].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) {
                let value = Int(v.rounded()); let name = parts[0].lowercased()
                if name.contains("calorie") || name.contains("kcal") { calories = value }
                else if name.contains("protein") { protein = value }
                else if name.contains("carb") { carbs = value }
                else if (name.contains("fat") || name == "fats") && !name.contains("saturated") { fat = value }
                else if name.contains("fiber") || name.contains("fibre") { fiber = value }
                else if name.contains("sugar") && !name.contains("added") { sugar = value }
                else if name.contains("sodium") || name.contains("salt") { sodium = value }
            }
        }
        return (calories, protein, carbs, fat, fiber, sugar, sodium)
    }

    func extractCaloriesInt(from text: String) -> Int {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calorie"),
               let v = Float(parts[1].replacingOccurrences(of: ",", with: "")) { return Int(v) }
        }
        return 0
    }

    func handleNetworkErrorRetry() { networkError = nil; fetchAllData(); profileManager.fetchProfile(force: true) }
    func getCurrentUserId() -> String? { session.userID.isEmpty ? UserDefaults.standard.string(forKey: "user_id") : session.userID }
    // MARK: - Pull-to-refresh (serial, same pattern as init)
     
    func refreshDashboard() async {
        await withCheckedContinuation { continuation in
            hasInitialized = false
            networkError = nil
            profileManager.fetchProfile(force: true)
     
            fetchHealthReportCalorieGoal {
                self.fetchAllData()
                self.calculateStreak()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    continuation.resume()
                }
            }
        }
    }
    func calculateProteinGoal() -> Int { Int(Double(dynamicCalorieGoal) * 0.2 / 4) }
    func calculateCarbGoal() -> Int { Int(Double(dynamicCalorieGoal) * 0.5 / 4) }
    func calculateFatGoal() -> Int { Int(Double(dynamicCalorieGoal) * 0.3 / 9) }
}



struct DailyScrollPicker: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedDate: Date
  
    var datesWithMeals: Set<String> = []

    @State private var displayWeekStart: Date = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

    var daysInWeek: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: displayWeekStart) }
    }

    var body: some View {
        VStack(spacing: 10) {
     
            HStack {
                Button(action: { shiftWeek(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                Text(weekRangeLabel())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Button(action: { shiftWeek(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isCurrentWeek
                            ? themeManager.current.secondaryText.opacity(0.2)
                            : themeManager.current.secondaryText)
                }
                .disabled(isCurrentWeek)
            }
            .padding(.horizontal, 4)

     
            HStack(spacing: 0) {
                ForEach(daysInWeek, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                    let isToday    = Calendar.current.isDateInToday(day)
                    let isFuture   = day > Date()
                    let hasMeals   = datesWithMeals.contains(dayKey(day))

                    Button(action: { guard !isFuture else { return }; selectedDate = day }) {
                        VStack(spacing: 6) {
                            
                            Text(shortDay(day))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(
                                    isSelected ? (themeManager.current == .dark ? Color.black : Color.white)
                                    : isFuture  ? themeManager.current.secondaryText.opacity(0.25)
                                    : themeManager.current.secondaryText
                                )

                       
                            ZStack {
                              
                                Circle()
                                    .fill(
                                        isSelected
                                            ? (themeManager.current == .dark ? Color.white : Color.black)
                                            : isToday
                                                ? Color(UIColor.systemGray5)
                                                : Color.clear
                                    )
                                    .frame(width: 36, height: 36)


                                if hasMeals && !isSelected {
                                    Circle()
                                        .stroke(Color.orange, lineWidth: 2)
                                        .frame(width: 36, height: 36)
                                }


                                if isFuture {
                                    Circle()
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        .foregroundColor(themeManager.current.cardBorder)
                                        .frame(width: 36, height: 36)
                                }


                                Text(dayNum(day))
                                    .font(.system(size: 16, weight: isSelected || isToday ? .bold : .regular))
                                    .foregroundColor(
                                        isSelected
                                            ? (themeManager.current == .dark ? Color.black : Color.white)
                                            : isFuture
                                                ? themeManager.current.primaryText.opacity(0.2)
                                                : hasMeals
                                                    ? Color.orange
                                                    : themeManager.current.primaryText
                                    )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                }
            }
        }

        .padding(.horizontal, 20)
    }

    var isCurrentWeek: Bool {
        guard let currentStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else { return true }
        return Calendar.current.isDate(displayWeekStart, inSameDayAs: currentStart)
    }

    func shiftWeek(by delta: Int) {
        guard let newStart = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: displayWeekStart) else { return }
        if delta > 0 && isCurrentWeek { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { displayWeekStart = newStart }
    }

    func weekRangeLabel() -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: displayWeekStart) ?? displayWeekStart
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: displayWeekStart) + " – " + f.string(from: end)
    }

    func shortDay(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return String(f.string(from: d).prefix(3))
    }

    func dayNum(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }

    func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
}

struct WeeklyChipPicker: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedWeekStart: Date
    var recentWeeks: [Date] {
        (0..<8).compactMap {
            Calendar.current.date(byAdding: .weekOfYear, value: -$0, to:
                Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        }
    }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentWeeks, id: \.self) { weekStart in
                    let isSelected = Calendar.current.isDate(weekStart, inSameDayAs: selectedWeekStart)
                    let isCurrent = Calendar.current.isDate(weekStart,
                        inSameDayAs: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
                    Button(action: { selectedWeekStart = weekStart }) {
                        HStack(spacing: 5) {
                            if isCurrent {
                                Text("This Week").font(.system(size: 12, weight: .bold))
                                    .foregroundColor(isSelected ? (themeManager.current == .dark ? .black : .white) : .orange)
                            } else {
                                Text(weekLabel(weekStart))
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? (themeManager.current == .dark ? .black : .white) : themeManager.current.primaryText)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 20)
                            .fill(isSelected ? (themeManager.current == .dark ? Color.white : Color.black) : themeManager.current.inputBackground))
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(isCurrent && !isSelected ? Color.orange.opacity(0.5) : themeManager.current.cardBorder,
                                    lineWidth: isCurrent && !isSelected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    func weekLabel(_ start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: start) + "–" + f.string(from: end)
    }
}

struct MonthChipPicker: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedMonth: Date
    var recentMonths: [Date] {
        (0..<12).compactMap { Calendar.current.date(byAdding: .month, value: -$0, to: Date()) }
            .compactMap { d -> Date? in
                var comps = Calendar.current.dateComponents([.year, .month], from: d)
                comps.day = 1
                return Calendar.current.date(from: comps)
            }
    }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recentMonths, id: \.self) { month in
                    let isSelected = Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month)
                    let isCurrent = Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
                    Button(action: { selectedMonth = month }) {
                        Text(isCurrent ? "This Month" : monthLabel(month))
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? (themeManager.current == .dark ? .black : .white) : themeManager.current.primaryText)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 20)
                                .fill(isSelected ? (themeManager.current == .dark ? Color.white : Color.black) : themeManager.current.inputBackground))
                            .overlay(RoundedRectangle(cornerRadius: 20)
                                .stroke(isCurrent && !isSelected ? Color.orange.opacity(0.5) : themeManager.current.cardBorder,
                                        lineWidth: isCurrent && !isSelected ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    func monthLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f.string(from: date)
    }
}

// MARK: - Supporting Components

struct MacroCell: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String; let title: String; let current: Int; let goal: Int; let unit: String; let color: Color
    var progress: Double { guard goal > 0 else { return 0 }; return min(Double(current) / Double(goal), 1.0) }
    var remaining: Int { max(0, goal - current) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 5).frame(width: 40, height: 40)
                Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 40, height: 40).rotationEffect(.degrees(-90)).animation(.easeOut(duration: 0.8), value: progress)
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(current)\(unit)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(themeManager.current.primaryText)
                Text("\(remaining)\(unit) left").font(.system(size: 11, weight: .medium)).foregroundColor(themeManager.current.secondaryText)
            }
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundColor(themeManager.current.secondaryText).textCase(.uppercase).tracking(0.4)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }
}

struct MealListRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let meal: Meal
    var calories: Int? {
        for line in meal.nutrition_info.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calorie") { return Int(parts[1]) }
        }
        return nil
    }
    var mealTime: String {
        guard let s = meal.saved_at, let d = parseISO8601(s) else { return "" }
        if Calendar.current.isDateInToday(d) { let f = DateFormatter(); f.timeStyle = .short; return f.string(from: d) }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }
    var mealIcon: String {
        switch (meal.meal_type ?? "").lowercased() {
        case "breakfast": return "sun.max.fill"
        case "lunch": return "sun.min.fill"
        case "dinner": return "moon.stars.fill"
        default: return "fork.knife"
        }
    }
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let base64 = meal.image_thumb ?? meal.image_full, !base64.isEmpty,
                   let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    themeManager.current.inputBackground
                        .overlay(Image(systemName: "fork.knife").foregroundColor(themeManager.current.secondaryText.opacity(0.5)))
                }
            }
            .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.dish_prediction).font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: mealIcon).font(.system(size: 10)).foregroundColor(themeManager.current.secondaryText)
                    Text(meal.meal_type?.capitalized ?? "Meal").font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                    Text("·").foregroundColor(themeManager.current.secondaryText.opacity(0.5))
                    Text(mealTime).font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                    if meal.from_diet_plan == true {
                        Text("Diet Plan").font(.system(size: 10, weight: .semibold)).foregroundColor(.purple)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1)).cornerRadius(4)
                    }
                }
            }
            Spacer()
            if let cal = calories {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(cal)").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundColor(themeManager.current.primaryText)
                    Text("kcal").font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
        }
        .padding(14).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }
}

struct WelcomeNewUserCard: View {
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.15)).frame(width: 70, height: 70)
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 36)).foregroundColor(.orange)
            }
            VStack(spacing: 8) {
                Text("Welcome to NutriSnap!").font(.system(size: 17, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Text("Set up your nutrition profile to get personalized recommendations")
                    .font(.subheadline).foregroundColor(themeManager.current.secondaryText).multilineTextAlignment(.center)
            }
            Button(action: action) {
                HStack { Image(systemName: "arrow.right.circle.fill"); Text("Set Up Profile") }
                    .fontWeight(.semibold).foregroundColor(.white).frame(maxWidth: .infinity)
                    .padding(.vertical, 14).background(Color.orange).cornerRadius(14)
            }
        }
        .padding(24).frame(maxWidth: .infinity).background(themeManager.current.cardBackground).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.orange.opacity(0.3), lineWidth: 1.5))
    }
}

struct EmptyMealsStateCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.system(size: 32)).foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            VStack(spacing: 4) {
                Text("No meals today").font(.system(size: 15, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                Text("Tap + to start tracking").font(.caption).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6])).foregroundColor(themeManager.current.cardBorder))
    }
}

struct SmallNutrientCircle: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let current: Int; let target: Int; let unit: String; let color: Color; let icon: String
    var progress: Double { guard target > 0 else { return 0 }; return min(Double(current) / Double(target), 1.0) }
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 5).frame(width: 48, height: 48)
                Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 48, height: 48).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: progress)
                VStack(spacing: 0) {
                    Text("\(current)").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText).minimumScaleFactor(0.6).lineLimit(1)
                    Text(unit).font(.system(size: 7)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundColor(themeManager.current.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
