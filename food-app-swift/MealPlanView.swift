//
//  MealPlanView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//
// MealPlanView.swift — 彻底修复版
// 核心修复：
// 1. loggedMeals 直接存入 UserDefaults（key: "loggedMeals_<userId>"）
// 2. analyzePhoto 成功后立即更新内存 + 持久化，不依赖 sheet dismiss
// 3. onAppear 每次切回 Tab 都重新读取，确保状态最新
// 4. 日期选择器上已 log 的天显示小绿点

import SwiftUI

struct MealPlanView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared

    @State private var weeklyPlan: WeeklyMealPlan?
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var selectedDayIndex = 0
    @State private var selectedMealForPhoto: PlannedMeal?
    @State private var showCompliance = false
    @State private var complianceResult: MealLog?
    @State private var errorMsg = ""
    @State private var showError = false
    @State private var showPlanGenerator = false
    @State private var isAnalyzing = false

    // ✅ key = "date_mealType"，持久化到 UserDefaults
    @State private var loggedMeals: [String: Int] = [:]
    @State private var savedMealLogs: [String: MealLog] = [:]

    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile

    // MARK: - Keys

    var currentUserId: String {
        session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? "unknown"
            : session.userID
    }

    var loggedMealsUDKey: String { "loggedMeals_\(currentUserId)" }
    var savedMealLogsUDKey: String { "savedMealLogs_\(currentUserId)" }

    var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var todayIndex: Int {
        guard let plan = weeklyPlan else { return 0 }
        return plan.days.firstIndex(where: { $0.date == today }) ?? 0
    }

    func logKey(date: String, mealType: String) -> String {
        "\(date)_\(mealType.lowercased())"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                if isGenerating {
                    generatingView
                } else if let plan = weeklyPlan {
                    planView(plan: plan)
                } else {
                    emptyView
                }

                if isAnalyzing {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Analysing your meal…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text("This usually takes 15–30 seconds")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(32)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .onAppear {
                loadAllPersisted()   // ✅ 每次切回 Tab 重新读取
                loadOrGeneratePlan()
            }
            .sheet(isPresented: $showCompliance) {
                if let result = complianceResult {
                    PhotoComplianceView(
                        mealLog: result,
                        weeklyPlan: weeklyPlan,
                        plannedMeal: selectedMealForPhoto
                    )
                    .environmentObject(themeManager)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMsg) }
            .sheet(isPresented: $showPlanGenerator) {
                PlanGeneratorView(nutritionPlan: nutritionPlan, healthProfile: healthProfile) { newPlan in
                    weeklyPlan = newPlan
                    selectedDayIndex = 0
                }
                .environmentObject(themeManager)
            }
        }
    }

    // MARK: - Plan View

    func dietPlanTitle(_ plan: WeeklyMealPlan) -> String {
        switch plan.days.count {
        case 1: return "Daily Diet Plan"
        case 3: return "3-Day Diet Plan"
        case 5: return "5-Day Diet Plan"
        case 7: return "Weekly Diet Plan"
        default: return "\(plan.days.count)-Day Diet Plan"
        }
    }

    func planView(plan: WeeklyMealPlan) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dietPlanTitle(plan))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("From \(weekStartLabel(plan))")
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                Button(action: { showPlanGenerator = true }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(width: 36, height: 36)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(10)
                }
                Button(action: { isGenerating = true; generatePlan() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(width: 36, height: 36)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)

            // Day selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(plan.days.enumerated()), id: \.offset) { i, day in
                        let isSelected = i == selectedDayIndex
                        let isToday = day.date == today
                        let dayHasLog = day.meals.contains {
                            loggedMeals[logKey(date: day.date, mealType: $0.mealType)] != nil
                        }

                        Button(action: { withAnimation(.spring()) { selectedDayIndex = i } }) {
                            VStack(spacing: 4) {
                                // ✅ 已 log 的日期显示小绿点
                                Circle()
                                    .fill(dayHasLog && !isSelected ? Color.green : Color.clear)
                                    .frame(width: 5, height: 5)

                                Text(String(day.dayName.prefix(3)))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(isSelected
                                        ? (themeManager.current == .dark ? .black : .white)
                                        : themeManager.current.secondaryText)
                                Text(dayNum(day.date))
                                    .font(.system(size: 16, weight: isSelected ? .black : .semibold))
                                    .foregroundColor(isSelected
                                        ? (themeManager.current == .dark ? .black : .white)
                                        : themeManager.current.primaryText)
                            }
                            .frame(width: 48)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected
                                      ? (themeManager.current == .dark ? Color.white : Color.black)
                                      : (isToday ? themeManager.current.inputBackground : Color.clear)))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(isToday && !isSelected ? themeManager.current.cardBorder : Color.clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)

            Divider().background(themeManager.current.cardBorder)

            if selectedDayIndex < plan.days.count {
                let day = plan.days[selectedDayIndex]
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.dayName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text("\(day.totalCalories) kcal planned")
                                    .font(.system(size: 13))
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                            Spacer()
                            if day.date == today {
                                Text("Today")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(themeManager.current == .dark ? Color.white : Color.black)
                                    .cornerRadius(20)
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 16)

                        ForEach(day.meals) { meal in
                            let key = logKey(date: day.date, mealType: meal.mealType)
                            ExpandableMealCard(
                                meal: meal,
                                day: day,
                                plan: plan,
                                today: today,
                                complianceScore: loggedMeals[key],
                                onViewResult: loggedMeals[key] != nil ? {
                                    selectedMealForPhoto = meal
                                    complianceResult = savedMealLogs[key]
                                    showCompliance = true
                                } : nil,
                                onPhotoSelected: { imageData in
                                    selectedMealForPhoto = meal
                                    analyzePhoto(imageData: imageData, day: day)
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                        Spacer(minLength: 60)
                    }
                }
            }
        }
    }

    // MARK: - Empty & Generating

    var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 56))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            Text("No meal plan yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
            Text("Generate a personalised week of meals based on your health goals")
                .font(.system(size: 14))
                .foregroundColor(themeManager.current.secondaryText)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button(action: { isGenerating = true; generatePlan() }) {
                Text("Generate Meal Plan")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(themeManager.current == .dark ? Color.white : Color.black)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText))
                .scaleEffect(1.5)
            Text("Building your meal plan…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
            Text("This usually takes 10–20 seconds")
                .font(.system(size: 13))
                .foregroundColor(themeManager.current.secondaryText)
            Spacer()
        }
    }

    // MARK: - Network

    func loadOrGeneratePlan() {
        isLoading = true
        HealthAPIManager.shared.fetchCurrentWeekPlan(userId: currentUserId) { plan in
            isLoading = false
            if let plan = plan {
                weeklyPlan = plan
                selectedDayIndex = todayIndex
            }
        }
    }

    func generatePlan() {
        HealthAPIManager.shared.generateWeeklyMealPlan(
            userId: currentUserId,
            nutritionPlan: nutritionPlan,
            healthProfile: healthProfile
        ) { plan, err in
            isGenerating = false
            if let plan = plan {
                weeklyPlan = plan
                selectedDayIndex = todayIndex
            } else {
                errorMsg = err ?? "Failed to generate plan"
                showError = true
            }
        }
    }

    // MARK: - Analyze Photo

    func analyzePhoto(imageData: Data, day: DayMealPlan) {
        guard let meal = selectedMealForPhoto,
              let plan = weeklyPlan else { return }

        isAnalyzing = true
        let dateStr = day.date   // 捕获，防止后续变化
        let remaining = Array(plan.days.dropFirst(selectedDayIndex + 1))

        HealthAPIManager.shared.analyzeMealPhoto(
            imageData: imageData,
            userId: currentUserId,
            date: dateStr,
            mealType: meal.mealType,
            plannedMeal: meal,
            remainingPlan: remaining
        ) { log, err in
            DispatchQueue.main.async {
                self.isAnalyzing = false

                if let log = log {
                    let key = self.logKey(date: dateStr, mealType: meal.mealType)

                    // ✅ 立即更新内存
                    self.loggedMeals[key] = log.complianceScore
                    self.savedMealLogs[key] = log
                    self.complianceResult = log

                    // ✅ 立即持久化（synchronize 强制写入）
                    self.persistLoggedMeals()
                    self.persistSavedMealLogs()

                    // ✅ 显示对比结果
                    self.showCompliance = true

                    // ✅ 通知其他页面刷新
                    NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)

                } else {
                    self.errorMsg = err ?? "Failed to analyse photo"
                    self.showError = true
                }
            }
        }
    }

    // MARK: - Persistence

    func loadAllPersisted() {
        if let data = UserDefaults.standard.data(forKey: loggedMealsUDKey),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            loggedMeals = dict
        }
        if let data = UserDefaults.standard.data(forKey: savedMealLogsUDKey),
           let dict = try? JSONDecoder().decode([String: MealLog].self, from: data) {
            savedMealLogs = dict
        }
    }

    func persistLoggedMeals() {
        if let data = try? JSONEncoder().encode(loggedMeals) {
            UserDefaults.standard.set(data, forKey: loggedMealsUDKey)
            UserDefaults.standard.synchronize()
        }
    }

    func persistSavedMealLogs() {
        if let data = try? JSONEncoder().encode(savedMealLogs) {
            UserDefaults.standard.set(data, forKey: savedMealLogsUDKey)
        }
    }

    // MARK: - Helpers

    func weekStartLabel(_ plan: WeeklyMealPlan) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let f2 = DateFormatter(); f2.dateFormat = "yyyy-MM-dd"
        if let d = f2.date(from: plan.weekStartDate) { return f.string(from: d) }
        return plan.weekStartDate
    }

    func dayNum(_ dateStr: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: dateStr) {
            let f2 = DateFormatter(); f2.dateFormat = "d"; return f2.string(from: d)
        }
        return ""
    }
}

// MARK: - Array safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - PhotoComplianceView

struct PhotoComplianceView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    let mealLog: MealLog
    let weeklyPlan: WeeklyMealPlan?
    var plannedMeal: PlannedMeal? = nil

    var scoreColor: Color {
        switch mealLog.complianceScore {
        case 80...100: return .green
        case 60..<80:  return .orange
        default:       return .red
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle().stroke(Color.gray.opacity(0.12), lineWidth: 12).frame(width: 140, height: 140)
                                Circle()
                                    .trim(from: 0, to: CGFloat(mealLog.complianceScore) / 100.0)
                                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .frame(width: 140, height: 140).rotationEffect(.degrees(-90))
                                VStack(spacing: 2) {
                                    Text("\(mealLog.complianceScore)")
                                        .font(.system(size: 42, weight: .black, design: .rounded))
                                        .foregroundColor(themeManager.current.primaryText)
                                    Text("/ 100").font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
                                }
                            }
                            Text("Compliance Score").font(.system(size: 16, weight: .bold))
                                .foregroundColor(themeManager.current.primaryText)
                            Text(mealLog.complianceFeedback).font(.system(size: 14))
                                .foregroundColor(themeManager.current.secondaryText)
                                .multilineTextAlignment(.center).padding(.horizontal, 20)
                        }
                        .padding(.top, 20)

                        comparisonCard

                        if let note = mealLog.planAdjustmentNote, !note.isEmpty {
                            adjustmentCard(note: note)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationTitle("Meal Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(themeManager.current.primaryText)
                }
            }
        }
    }

    var comparisonCard: some View {
        let planned = plannedMeal ?? mealLog.plannedMeal
        return VStack(alignment: .leading, spacing: 14) {
            Text("Actual vs Planned")
                .font(.system(size: 15, weight: .bold)).foregroundColor(themeManager.current.primaryText)
            Text("✓ within ±25%  ⚠ outside range")
                .font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)

            HStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text("Actual").font(.system(size: 12, weight: .bold)).foregroundColor(themeManager.current.secondaryText)
                    compRow("Calories", "\(mealLog.estimatedCalories) kcal", planned.map { within(mealLog.estimatedCalories, $0.totalCalories) })
                    compRow("Protein",  "\(mealLog.estimatedProtein)g",  planned.map { within(mealLog.estimatedProtein,  $0.totalProtein) })
                    compRow("Carbs",    "\(mealLog.estimatedCarbs)g",    planned.map { within(mealLog.estimatedCarbs,    $0.totalCarbs) })
                    compRow("Fat",      "\(mealLog.estimatedFat)g",      planned.map { within(mealLog.estimatedFat,      $0.totalFat) })
                }.frame(maxWidth: .infinity)

                Divider().frame(height: 160).background(themeManager.current.cardBorder)

                VStack(spacing: 10) {
                    Text("Planned").font(.system(size: 12, weight: .bold)).foregroundColor(themeManager.current.secondaryText)
                    compRow("Calories", planned.map { "\($0.totalCalories) kcal" } ?? "—", nil)
                    compRow("Protein",  planned.map { "\($0.totalProtein)g" } ?? "—",  nil)
                    compRow("Carbs",    planned.map { "\($0.totalCarbs)g" } ?? "—",    nil)
                    compRow("Fat",      planned.map { "\($0.totalFat)g" } ?? "—",      nil)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(16).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func within(_ actual: Int, _ target: Int) -> Bool {
        guard target > 0 else { return true }
        return abs(actual - target) <= target / 4
    }

    func compRow(_ label: String, _ value: String, _ ok: Bool?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Text(value).font(.system(size: 14, weight: .bold))
                    .foregroundColor(ok == nil ? themeManager.current.primaryText : ok! ? .green : .orange)
                if let ok = ok {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 10)).foregroundColor(ok ? .green : .orange)
                }
            }
            Text(label).font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    func adjustmentCard(note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14)).foregroundColor(themeManager.current.primaryText)
                Text("Plan Adjusted").font(.system(size: 15, weight: .bold)).foregroundColor(themeManager.current.primaryText)
            }
            Text(note).font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText).lineSpacing(4)
        }
        .padding(16).background(themeManager.current.inputBackground).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }
}

// MARK: - Camera Picker

struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void
    @Environment(\.dismiss) var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onCapture(info[.originalImage] as? UIImage); parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCapture(nil); parent.dismiss() }
    }
}

// MARK: - HealthDashboardView + TodayView

struct HealthDashboardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(nutritionPlan: nutritionPlan, healthProfile: healthProfile)
                .environmentObject(themeManager)
                .tabItem { Image(systemName: selectedTab == 0 ? "house.fill" : "house"); Text("Today") }
                .tag(0)
            MealPlanView(nutritionPlan: nutritionPlan, healthProfile: healthProfile)
                .environmentObject(themeManager)
                .tabItem { Image(systemName: selectedTab == 1 ? "calendar.badge.checkmark" : "calendar"); Text("Diet Plan") }
                .tag(1)
            ProfileView()
                .environmentObject(themeManager)
                .tabItem { Image(systemName: selectedTab == 2 ? "person.fill" : "person"); Text("Profile") }
                .tag(2)
        }
        .tint(themeManager.current == .dark ? .white : .black)
        .preferredColorScheme(themeManager.current.colorScheme)
    }
}

struct TodayView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile
    var body: some View {
        DashboardView().environmentObject(themeManager)
    }
}
