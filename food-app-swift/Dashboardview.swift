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

    @State private var selectedDate: Date = Date()
    @State private var selectedWeekStart: Date = {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }()
    @State private var selectedMonth: Date = Date()
    @State private var selectedTimeFilter: String = "Daily"
    let timeFilters = ["Daily", "Weekly", "Monthly"]

    @State private var weeklyCalories: Int = 0
    @State private var weeklyProtein: Int = 0
    @State private var weeklyCarbs: Int = 0
    @State private var weeklyFat: Int = 0


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
        case 0..<12: return "Good Morning ☀️"
        case 12..<17: return "Good Afternoon 🌤"
        default: return "Good Evening 🌙"
        }
    }

    var userName: String { session.userName.isEmpty ? "Friend" : session.userName }
    var dynamicCalorieGoal: Int { profileManager.userProfile?.calorieTarget ?? calorieGoal }

    
    var displayedCalories: Int {
        let isoF = ISO8601DateFormatter(); isoF.timeZone = TimeZone.current
        let cal = Calendar.current
        switch selectedTimeFilter {
        case "Daily":
            return meals.filter { m in
                guard let s = m.saved_at, let d = isoF.date(from: s) else { return false }
                return cal.isDate(d, inSameDayAs: selectedDate)
            }.reduce(0) { $0 + extractCaloriesInt(from: $1.nutrition_info) }
        case "Weekly":
            let end = cal.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
            return meals.filter { m in
                guard let s = m.saved_at, let d = isoF.date(from: s) else { return false }
                return d >= selectedWeekStart && d < end
            }.reduce(0) { $0 + extractCaloriesInt(from: $1.nutrition_info) }
        case "Monthly":
            guard let interval = cal.dateInterval(of: .month, for: selectedMonth) else { return 0 }
            return meals.filter { m in
                guard let s = m.saved_at, let d = isoF.date(from: s) else { return false }
                return d >= interval.start && d < interval.end
            }.reduce(0) { $0 + extractCaloriesInt(from: $1.nutrition_info) }
        default: return todayCalories
        }
    }

    var displayedGoal: Int {
        let cal = Calendar.current
        switch selectedTimeFilter {
        case "Daily": return dynamicCalorieGoal
        case "Weekly": return dynamicCalorieGoal * 7
        case "Monthly":
            let days = cal.range(of: .day, in: .month, for: selectedMonth)?.count ?? 30
            return dynamicCalorieGoal * days
        default: return dynamicCalorieGoal
        }
    }

    func extractCaloriesInt(from text: String) -> Int {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calorie"),
               let v = Float(parts[1].replacingOccurrences(of: ",", with: "")) { return Int(v) }
        }
        return 0
    }

    var calorieProgress: Double {
        guard displayedGoal > 0 else { return 0 }
        return min(Double(displayedCalories) / Double(displayedGoal), 1.0)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                themeManager.current.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ── Header ──
                        headerSection
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 12)


                        timeFilterSection
                            .padding(.bottom, 12)


                        periodSelectorSection
                            .padding(.bottom, 16)

                        VStack(spacing: 16) {
                            
                            if profileManager.isNewUser {
                                WelcomeNewUserCard { showProfile = true }
                            } else if profileManager.userProfile == nil && !profileManager.isLoading && profileManager.errorMessage != nil {
                                if let err = profileManager.errorMessage { profileErrorSection(err) }
                            }
                            if let netErr = networkError { networkErrorSection(netErr) }
                            else if profileManager.isLoading && profileManager.userProfile == nil && !profileManager.isNewUser {
                                profileLoadingSection
                            }

                            
                            calorieMainCard

                           
                            macrosGrid

                            
                            todayMealsSection

                            
                            if !meals.isEmpty { comprehensiveNutritionSection }

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
            } message: { Text("Set up your profile to get personalized nutrition goals and better tracking.") }
            .alert(networkError?.title ?? "Error", isPresented: $showNetworkAlert) {
                if networkError == .sessionExpired { Button("Login") { session.logout() } }
                else { Button("Retry") { handleNetworkErrorRetry() } }
                Button("Cancel", role: .cancel) { networkError = nil }
            } message: { Text(networkError?.message ?? "An error occurred") }
        }
    }

    

    var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                Text(userName)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
            }
            Spacer()
            HStack(spacing: 10) {
                
                if currentStreak > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                        Text("\(currentStreak)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(themeManager.current.primaryText)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(themeManager.current.cardBackground)
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(themeManager.current.cardBorder, lineWidth: 1))
                }
                
                Button(action: { showProfile = true }) {
                    ZStack(alignment: .topTrailing) {
                        Circle()
                            .fill(themeManager.current.inputBackground)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(userName.prefix(1)).uppercased())
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(themeManager.current.primaryText)
                            )
                        Circle()
                            .fill(profileManager.isLoading ? Color.yellow
                                  : profileManager.userProfile != nil ? Color.green
                                  : profileManager.isNewUser ? Color.orange : Color.red)
                            .frame(width: 10, height: 10)
                            .offset(x: 2, y: -2)
                    }
                }
            }
        }
    }

    

    var timeFilterSection: some View {
        HStack(spacing: 0) {
            ForEach(timeFilters, id: \.self) { filter in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTimeFilter = filter
                    }
                }) {
                    Text(filter)
                        .font(.system(size: 14, weight: selectedTimeFilter == filter ? .bold : .regular))
                        .foregroundColor(selectedTimeFilter == filter
                            ? (themeManager.current == .dark ? .black : .white)
                            : themeManager.current.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedTimeFilter == filter
                                      ? (themeManager.current == .dark ? Color.white : Color.black)
                                      : Color.clear)
                        )
                }
            }
        }
        .padding(4)
        .background(themeManager.current.inputBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    

    @ViewBuilder
    var periodSelectorSection: some View {
        switch selectedTimeFilter {
        case "Daily":
            DailyScrollSelector(selectedDate: $selectedDate)
                .padding(.horizontal, 20)
        case "Weekly":
            WeeklyScrollSelector(selectedWeekStart: $selectedWeekStart)
                .padding(.horizontal, 20)
        case "Monthly":
            MonthlyGridSelector(selectedMonth: $selectedMonth)
                .padding(.horizontal, 20)
        default:
            EmptyView()
        }
    }

    

    var calorieMainCard: some View {
        HStack(spacing: 20) {
            
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedTimeFilter == "Daily" ? "Daily Calories" : selectedTimeFilter == "Weekly" ? "Weekly Calories" : "Monthly Calories")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(animateCalories ? displayedCalories : 0)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundColor(themeManager.current.primaryText)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: displayedCalories)
                    Text("/ \(displayedGoal) kcal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(themeManager.current.secondaryText)
                        .padding(.bottom, 4)
                }

                Text(getCalorieStatusMessage())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(calorieProgressColor)

                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(calorieProgressColor)
                            .frame(width: geo.size.width * (animateCalories ? calorieProgress : 0), height: 6)
                            .animation(.easeOut(duration: 1.0), value: calorieProgress)
                    }
                }
                .frame(height: 6)
            }

            Spacer()

            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.12), lineWidth: 10)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: animateCalories ? calorieProgress : 0)
                    .stroke(
                        calorieProgressColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: calorieProgress)
                VStack(spacing: 2) {
                    Text("\(Int(calorieProgress * 100))%")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundColor(calorieProgressColor)
                }
            }
        }
        .padding(20)
        .background(themeManager.current.cardBackground)
        .cornerRadius(22)
        .overlay(RoundedRectangle(cornerRadius: 22)
            .stroke(themeManager.current.cardBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(themeManager.current == .dark ? 0.3 : 0.05),
                radius: 8, x: 0, y: 4)
    }

    var calorieProgressColor: Color {
        if calorieProgress < 0.5 { return .green }
        else if calorieProgress < 0.8 { return Color.orange }
        else if calorieProgress < 1.0 { return Color.orange }
        else { return .red }
    }

    

    var macrosGrid: some View {
        HStack(spacing: 12) {
            MacroCell(
                icon: "fork.knife",
                title: "Protein",
                current: totalProtein,
                goal: calculateProteinGoal(),
                unit: "g",
                color: Color(red: 0.93, green: 0.36, blue: 0.36)
            )
            MacroCell(
                icon: "leaf.fill",
                title: "Carbs",
                current: totalCarbs,
                goal: calculateCarbGoal(),
                unit: "g",
                color: Color(red: 0.95, green: 0.61, blue: 0.20)
            )
            MacroCell(
                icon: "drop.fill",
                title: "Fat",
                current: totalFat,
                goal: calculateFatGoal(),
                unit: "g",
                color: Color(red: 0.35, green: 0.62, blue: 0.93)
            )
        }
    }


    var filteredMealsForDisplay: [Meal] {
        let cal = Calendar.current
        let isoF = ISO8601DateFormatter(); isoF.timeZone = TimeZone.current
        switch selectedTimeFilter {
        case "Daily":
            return meals.filter { meal in
                guard let s = meal.saved_at, let d = isoF.date(from: s) else { return false }
                return cal.isDate(d, inSameDayAs: selectedDate)
            }
        case "Weekly":
            let end = cal.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
            return meals.filter { meal in
                guard let s = meal.saved_at, let d = isoF.date(from: s) else { return false }
                return d >= selectedWeekStart && d < end
            }
        case "Monthly":
            guard let interval = cal.dateInterval(of: .month, for: selectedMonth) else { return [] }
            return meals.filter { meal in
                guard let s = meal.saved_at, let d = isoF.date(from: s) else { return false }
                return d >= interval.start && d < interval.end
            }
        default:
            return meals.filter { isSameDay($0.saved_at) }
        }
    }

    var mealsSectionTitle: String {
        let cal = Calendar.current
        switch selectedTimeFilter {
        case "Daily":
            if cal.isDateInToday(selectedDate) { return "Today's Meals" }
            if cal.isDateInYesterday(selectedDate) { return "Yesterday's Meals" }
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return f.string(from: selectedDate) + "'s Meals"
        case "Weekly":
            let end = cal.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return f.string(from: selectedWeekStart) + " – " + f.string(from: end)
        case "Monthly":
            let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
            return f.string(from: selectedMonth) + "'s Meals"
        default: return "Today's Meals"
        }
    }

    var todayMealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(mealsSectionTitle)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                    .animation(.none, value: mealsSectionTitle)
                Spacer()
                Button(action: { showMealHistory = true }) {
                    Text("See all")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }

            if filteredMealsForDisplay.isEmpty {
                EmptyMealsStateCard()
            } else {
                
                let displayMeals = selectedTimeFilter == "Daily"
                    ? Array(filteredMealsForDisplay.prefix(10))
                    : Array(filteredMealsForDisplay.prefix(5))
                ForEach(displayMeals) { meal in
                    Button(action: { selectedMealForDetail = meal }) {
                        MealListRow(meal: meal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    

    var comprehensiveNutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nutrition Overview")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Spacer()

                Text(selectedTimeFilter == "Daily" ? "Daily" : selectedTimeFilter == "Weekly" ? "Weekly" : "Monthly")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(themeManager.current == .dark ? Color.white : Color.black))
            }


            ZStack {
                if selectedTimeFilter == "Daily" {
                    todaysCircularNutritionView
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    
                    WeeklyNutritionOverview(
                        avgCalories: selectedTimeFilter == "Weekly"
                            ? (filteredMealsForDisplay.count > 0 ? displayedCalories / max(1, filteredMealsForDisplay.count) : 0)
                            : monthlyAvgCalories,
                        targetCalories: dynamicCalorieGoal,
                        mealsLogged: filteredMealsForDisplay.count,
                        streak: currentStreak
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: selectedTimeFilter)
        }
    }


    var todaysCircularNutritionView: some View {
        let todaysNutritionText = createTodaysNutritionText()
        return Group {
            if !todaysNutritionText.isEmpty {
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        TodaysNutrientCircle(title: "Protein", current: totalProtein, target: calculateProteinGoal(), unit: "g", color: Color(red: 0.93, green: 0.36, blue: 0.36), icon: "bolt.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Carbs", current: totalCarbs, target: calculateCarbGoal(), unit: "g", color: Color(red: 0.95, green: 0.61, blue: 0.20), icon: "leaf.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Fat", current: totalFat, target: calculateFatGoal(), unit: "g", color: Color(red: 0.35, green: 0.62, blue: 0.93), icon: "drop.fill")
                            .environmentObject(themeManager)
                    }
                    HStack(spacing: 16) {
                        TodaysNutrientCircle(title: "Fiber", current: totalFiber, target: 25, unit: "g", color: .purple, icon: "circle.grid.2x2.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Sugar", current: totalSugar, target: 50, unit: "g", color: .pink, icon: "heart.fill")
                            .environmentObject(themeManager)
                        TodaysNutrientCircle(title: "Sodium", current: totalSodium, target: 2300, unit: "mg", color: .red, icon: "triangle.fill")
                            .environmentObject(themeManager)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 18)
                    .fill(themeManager.current.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(themeManager.current.cardBorder, lineWidth: 1)))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie").font(.system(size: 36))
                        .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
                    Text("No nutrition data today")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("Add your first meal to see breakdown")
                        .font(.caption)
                        .foregroundColor(themeManager.current.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .background(RoundedRectangle(cornerRadius: 18)
                    .fill(themeManager.current.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundColor(themeManager.current.cardBorder)))
            }
        }
    }



    var calStyleFloatingButton: some View {
        Button(action: { withAnimation(.spring()) { showUploadMeal = true } }) {
            ZStack {
                Circle()
                    .fill(themeManager.current == .dark ? Color.white : Color.black)
                    .frame(width: 60, height: 60)
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 28)
    }



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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }

    var profileLoadingSection: some View {
        HStack {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .orange)).scaleEffect(0.8)
            Text("Loading your profile...")
                .font(.caption).foregroundColor(themeManager.current.secondaryText)
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08))
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
            Button("Retry") { profileManager.fetchProfile(force: true) }
                .font(.caption).foregroundColor(.orange)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1)))
    }



    func getCalorieStatusMessage() -> String {
        if profileManager.isNewUser { return "Set up profile for personalized goals" }
        let period = selectedTimeFilter == "Daily" ? "today" : selectedTimeFilter == "Weekly" ? "this week" : "this month"
        if calorieProgress < 0.3 { return "Great start \(period)! 💪" }
        else if calorieProgress < 0.7 { return "On track \(period) 🎯" }
        else if calorieProgress < 1.0 { return "Almost at your goal!" }
        else if calorieProgress < 1.2 { return "Goal reached! 🎉" }
        else { return "Over goal - consider lighter options" }
    }

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
            if let error = error {
                DispatchQueue.main.async { self.networkError = .dataLoadFailed; print("❌ \(error.localizedDescription)") }; return
            }
            guard let data = data else { DispatchQueue.main.async { self.networkError = .dataLoadFailed }; return }
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return
                } else if httpResponse.statusCode != 200 {
                    DispatchQueue.main.async { self.networkError = .serverError }; return
                }
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
                if httpResponse.statusCode == 401 {
                    DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return
                } else if httpResponse.statusCode != 200 { return }
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
                if httpResponse.statusCode == 401 {
                    DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return
                } else if httpResponse.statusCode != 200 { return }
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
                if httpResponse.statusCode == 401 {
                    DispatchQueue.main.async { self.networkError = .sessionExpired; self.showNetworkAlert = true }; return
                } else if httpResponse.statusCode != 200 { return }
            }
            if let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data) {
                DispatchQueue.main.async {
                    self.weightEntries = decoded.sorted { $0.recorded_at > $1.recorded_at }
                    self.calculateWeightStats()
                }
            }
        }.resume()
    }

    func calculateStats() {
        let calendar = Calendar.current; let today = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let isoFormatter = ISO8601DateFormatter(); isoFormatter.timeZone = TimeZone.current
        var todayCal = 0, todayProt = 0, todayCarb = 0, todayFt = 0, todayFib = 0, todaySug = 0, todaySod = 0
        var weeklyCal = 0, weeklyProt = 0, weeklyCarb = 0, weeklyFt = 0
        var monthlyCal = 0, monthlyDays = Set<String>()
        for meal in meals {
            guard let savedAt = meal.saved_at, let validDate = isoFormatter.date(from: savedAt) else { continue }
            let n = extractAllNutrients(from: meal.nutrition_info)
            if calendar.isDateInToday(validDate) {
                todayCal += n.calories; todayProt += n.protein; todayCarb += n.carbs; todayFt += n.fat
                todayFib += n.fiber; todaySug += n.sugar; todaySod += n.sodium
            }
  
            if validDate >= startOfWeek {
                weeklyCal += n.calories; weeklyProt += n.protein; weeklyCarb += n.carbs; weeklyFt += n.fat
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
            weeklyCalories = weeklyCal; weeklyProtein = weeklyProt; weeklyCarbs = weeklyCarb; weeklyFat = weeklyFt
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
       
        let todaysMeals = filteredMealsForDisplay
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
            if hasM { streak += 1; currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate }
            else { break }
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



struct DailyScrollSelector: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedDate: Date

    @State private var displayWeekStart: Date = {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }()

    var daysInWeek: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: displayWeekStart) }
    }

    var body: some View {
        VStack(spacing: 10) {

            HStack {
                Button(action: { shiftWeek(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(width: 30, height: 30)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(8)
                }
                Spacer()
                Text(weekRangeLabel())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Button(action: { shiftWeek(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isCurrentWeek ? themeManager.current.secondaryText.opacity(0.3) : themeManager.current.primaryText)
                        .frame(width: 30, height: 30)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(8)
                }
                .disabled(isCurrentWeek)
            }


            HStack(spacing: 6) {
                ForEach(daysInWeek, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                    let isToday = Calendar.current.isDateInToday(day)
                    let isFuture = day > Date()
                    Button(action: { guard !isFuture else { return }; selectedDate = day }) {
                        VStack(spacing: 4) {
                            Text(shortDay(day))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(isSelected
                                    ? (themeManager.current == .dark ? .black : .white)
                                    : isFuture ? themeManager.current.secondaryText.opacity(0.25)
                                    : themeManager.current.secondaryText)
                            Text(dayNum(day))
                                .font(.system(size: 16, weight: isSelected ? .black : .semibold))
                                .foregroundColor(isSelected
                                    ? (themeManager.current == .dark ? .black : .white)
                                    : isFuture ? themeManager.current.primaryText.opacity(0.25)
                                    : themeManager.current.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected
                                      ? (themeManager.current == .dark ? Color.white : Color.black)
                                      : isToday ? themeManager.current.inputBackground : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isToday && !isSelected ? themeManager.current.cardBorder : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                }
            }
        }
    }

    var isCurrentWeek: Bool {
        guard let currentStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start else { return true }
        return Calendar.current.isDate(displayWeekStart, inSameDayAs: currentStart)
    }

    func shiftWeek(by delta: Int) {
        if let newStart = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: displayWeekStart) {
            // Don't go past current week
            if delta > 0 && isCurrentWeek { return }
            displayWeekStart = newStart
        }
    }

    func weekRangeLabel() -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: displayWeekStart) ?? displayWeekStart
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: displayWeekStart) + " – " + f.string(from: end)
    }

    func shortDay(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return String(f.string(from: d).prefix(3))
    }
    func dayNum(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }
}



struct WeeklyScrollSelector: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedWeekStart: Date

    var recentWeeks: [Date] {
        
        (0..<12).compactMap {
            Calendar.current.date(byAdding: .weekOfYear, value: -$0, to:
                Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(recentWeeks, id: \.self) { weekStart in
                    let isSelected = Calendar.current.isDate(weekStart, inSameDayAs: selectedWeekStart)
                    let isCurrentWeek = Calendar.current.isDate(weekStart,
                        inSameDayAs: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
                    Button(action: { selectedWeekStart = weekStart }) {
                        VStack(spacing: 4) {
                            if isCurrentWeek {
                                Text("This Week")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(isSelected
                                        ? (themeManager.current == .dark ? .black : .white)
                                        : .orange)
                            }
                            Text(weekLabel(weekStart))
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected
                                    ? (themeManager.current == .dark ? .black : .white)
                                    : themeManager.current.primaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected
                                      ? (themeManager.current == .dark ? Color.white : Color.black)
                                      : themeManager.current.inputBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isCurrentWeek && !isSelected ? Color.orange.opacity(0.4) : themeManager.current.cardBorder,
                                        lineWidth: isCurrentWeek && !isSelected ? 1.5 : 1)
                        )
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


struct MonthlyGridSelector: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var selectedMonth: Date


    @State private var displayYear: Int = Calendar.current.component(.year, from: Date())

    var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    var minYear: Int { currentYear - 2 }

    var monthsInYear: [Date] {
        let cal = Calendar.current
        return (1...12).compactMap { month in
            var comps = DateComponents(); comps.year = displayYear; comps.month = month; comps.day = 1
            return cal.date(from: comps)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            
            HStack {
                Button(action: { if displayYear > minYear { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { displayYear -= 1 } } }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(displayYear > minYear ? themeManager.current.primaryText : themeManager.current.secondaryText.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(8)
                }
                .disabled(displayYear <= minYear)

                Spacer()

                Text("\(displayYear)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                    .animation(.none, value: displayYear)

                Spacer()

                Button(action: { if displayYear < currentYear { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { displayYear += 1 } } }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(displayYear < currentYear ? themeManager.current.primaryText : themeManager.current.secondaryText.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(8)
                }
                .disabled(displayYear >= currentYear)
            }

            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(monthsInYear, id: \.self) { month in
                        let cal = Calendar.current
                        let mNum = cal.component(.month, from: month)
                        let isSelected = cal.isDate(month, equalTo: selectedMonth, toGranularity: .month)
                        let isCurrentMonth = displayYear == currentYear && mNum == currentMonth
                        let isFuture = displayYear == currentYear && mNum > currentMonth

                        Button(action: { guard !isFuture else { return }; selectedMonth = month }) {
                            VStack(spacing: 3) {
                                Text(monthAbbr(month))
                                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected
                                        ? (themeManager.current == .dark ? .black : .white)
                                        : isFuture ? themeManager.current.primaryText.opacity(0.25)
                                        : themeManager.current.primaryText)
                               
                                if isCurrentMonth && !isSelected {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 4, height: 4)
                                } else {
                                    Circle().fill(Color.clear).frame(width: 4, height: 4)
                                }
                            }
                            .frame(width: 52, height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isSelected
                                          ? (themeManager.current == .dark ? Color.white : Color.black)
                                          : isCurrentMonth ? themeManager.current.inputBackground : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isCurrentMonth && !isSelected ? Color.orange.opacity(0.35) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isFuture)
                    }
                }
            }
        }
    }

    func monthAbbr(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: date)
    }
}


struct MacroCell: View {
    @EnvironmentObject var themeManager: ThemeManager
    let icon: String
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color

    var progress: Double { guard goal > 0 else { return 0 }; return min(Double(current) / Double(goal), 1.0) }
    var remaining: Int { max(0, goal - current) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 5)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(current)\(unit)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text("\(remaining)\(unit) left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(themeManager.current.secondaryText)
                .textCase(.uppercase)
                .tracking(0.4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(themeManager.current.cardBorder, lineWidth: 1))
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
        guard let s = meal.saved_at, let d = ISO8601DateFormatter().date(from: s) else { return "" }
        if Calendar.current.isDateInToday(d) {
            let f = DateFormatter(); f.timeStyle = .short; return f.string(from: d)
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }

    var mealIcon: String {
        switch (meal.meal_type ?? "").lowercased() {
        case "breakfast": return "sun.max.fill"
        case "lunch": return "sun.min.fill"
        case "dinner": return "moon.stars.fill"
        case "evening snacks", "snacks": return "cup.and.saucer.fill"
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
                        .overlay(Image(systemName: "fork.knife")
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.5)))
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 14))

      
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.dish_prediction)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: mealIcon)
                        .font(.system(size: 10))
                        .foregroundColor(themeManager.current.secondaryText)
                    Text(meal.meal_type?.capitalized ?? "Meal")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                    Text("·").foregroundColor(themeManager.current.secondaryText.opacity(0.5))
                    Text(mealTime)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }

            Spacer()

  
            if let cal = calories {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(cal)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("kcal")
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
        }
        .padding(14)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(themeManager.current.cardBorder, lineWidth: 1))
    }
}



struct WelcomeNewUserCard: View {
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.15)).frame(width: 70, height: 70)
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 36))
                    .foregroundColor(.orange)
            }
            VStack(spacing: 8) {
                Text("Welcome to NutriSnap!")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Text("Set up your nutrition profile to get personalized recommendations")
                    .font(.subheadline).foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center)
            }
            Button(action: action) {
                HStack { Image(systemName: "arrow.right.circle.fill"); Text("Set Up Profile") }
                    .fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.orange).cornerRadius(14)
            }
        }
        .padding(24).frame(maxWidth: .infinity)
        .background(themeManager.current.cardBackground)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color.orange.opacity(0.3), lineWidth: 1.5))
    }
}

struct TodaysNutrientCircle: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let current: Int; let target: Int; let unit: String; let color: Color; let icon: String
    var progress: Double { guard target > 0 else { return 0 }; return min(Double(current) / Double(target), 1.0) }
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 8).frame(width: 70, height: 70)
                Circle().trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 70, height: 70).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.2, dampingFraction: 0.8), value: progress)
                VStack(spacing: 1) {
                    Text("\(current)").font(.system(size: 16, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                    Text("\(unit)").font(.system(size: 8)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
                Text(title).font(.caption2).foregroundColor(themeManager.current.primaryText).fontWeight(.medium)
                Text("\(target) \(unit)").font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct WeeklyNutritionOverview: View {
    let avgCalories: Int; let targetCalories: Int; let mealsLogged: Int; let streak: Int
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                WeeklyStatCircle(title: "Avg Cal", value: avgCalories, target: targetCalories, unit: "kcal", color: .orange)
                WeeklyStatCircle(title: "Meals", value: mealsLogged, target: 21, unit: "logged", color: .green)
                WeeklyStatCircle(title: "Streak", value: streak, target: 7, unit: "days", color: .purple)
            }
            if mealsLogged > 0 || streak > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    if mealsLogged > 0 {
                        HStack(spacing: 8) {
                            Circle().fill(Color.green.opacity(0.4)).frame(width: 6, height: 6)
                            Text("You've logged \(mealsLogged) meals this week")
                                .font(.caption).foregroundColor(themeManager.current.secondaryText)
                            Spacer()
                        }
                    }
                    if streak > 0 {
                        HStack(spacing: 8) {
                            Circle().fill(Color.orange.opacity(0.4)).frame(width: 6, height: 6)
                            Text("Current tracking streak: \(streak) days")
                                .font(.caption).foregroundColor(themeManager.current.secondaryText)
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.current.inputBackground))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18)
            .fill(themeManager.current.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(themeManager.current.cardBorder, lineWidth: 1)))
    }
}

struct WeeklyStatCircle: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let value: Int; let target: Int; let unit: String; let color: Color
    var progress: Double { guard target > 0 else { return 0 }; return min(Double(value) / Double(target), 1.0) }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 6).frame(width: 60, height: 60)
                Circle().trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60).rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.8), value: progress)
                Text("\(value)").font(.system(size: 14, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
            }
            VStack(spacing: 2) {
                Text(title).font(.caption2).foregroundColor(themeManager.current.primaryText).fontWeight(.medium)
                Text(unit).font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyMealsStateCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.system(size: 32))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            VStack(spacing: 4) {
                Text("No meals today").font(.system(size: 15, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                Text("Tap + to start tracking").font(.caption)
                    .foregroundColor(themeManager.current.secondaryText)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundColor(themeManager.current.cardBorder))
    }
}
