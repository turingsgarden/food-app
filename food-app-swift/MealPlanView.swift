//
//  MealPlanView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//

// MealPlanView.swift
// Health Agent — 一周饮食计划展示

import SwiftUI

struct MealPlanView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared

    @State private var weeklyPlan: WeeklyMealPlan?
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var selectedDayIndex = 0
    @State private var showCamera = false
    @State private var selectedMealForPhoto: PlannedMeal?
    @State private var showCompliance = false
    @State private var complianceResult: MealLog?
    @State private var errorMsg = ""
    @State private var showError = false
    @State private var showPlanGenerator = false
    @State private var isAnalyzing = false

    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile

    var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var todayIndex: Int {
        guard let plan = weeklyPlan else { return 0 }
        return plan.days.firstIndex(where: { $0.date == today }) ?? 0
    }

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

                // ── Analyzing overlay（跟 batch upload 一样的全屏加载）
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
            .onAppear { loadOrGeneratePlan() }
            // Camera handled by ExpandableMealCard
            .sheet(isPresented: $showCompliance) {
                if let result = complianceResult {
                    PhotoComplianceView(mealLog: result, weeklyPlan: weeklyPlan)
                        .environmentObject(themeManager)
                        .onDisappear { loadOrGeneratePlan() }
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

    // Dynamic title based on number of days
    func dietPlanTitle(_ plan: WeeklyMealPlan) -> String {
        let count = plan.days.count
        switch count {
        case 1: return "Daily Diet Plan"
        case 3: return "3-Day Diet Plan"
        case 5: return "5-Day Diet Plan"
        case 7: return "Weekly Diet Plan"
        default: return "\(count)-Day Diet Plan"
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
                // New plan button
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
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Day selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(plan.days.enumerated()), id: \.offset) { i, day in
                        let isSelected = i == selectedDayIndex
                        let isToday = day.date == today
                        Button(action: { withAnimation(.spring()) { selectedDayIndex = i } }) {
                            VStack(spacing: 4) {
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

            // Day detail
            if selectedDayIndex < plan.days.count {
                let day = plan.days[selectedDayIndex]
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Calorie summary
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
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                        // Meals
                        ForEach(day.meals) { meal in
                            plannedMealCard(meal: meal, day: day, plan: plan)
                                .padding(.horizontal, 20)
                        }
                        Spacer(minLength: 60)
                    }
                }
            }
        }
    }

    func plannedMealCard(meal: PlannedMeal, day: DayMealPlan, plan: WeeklyMealPlan) -> some View {
        ExpandableMealCard(meal: meal, day: day, plan: plan,
                           today: today, onPhotoSelected: { imageData in
            selectedMealForPhoto = meal
            analyzePhoto(imageData: imageData)
        })
        .environmentObject(themeManager)
    }

    func plannedMealCard_OLD(meal: PlannedMeal, day: DayMealPlan, plan: WeeklyMealPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                // Meal type badge
                Text(meal.mealType.capitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(mealTypeColor(meal.mealType))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(mealTypeColor(meal.mealType).opacity(0.12))
                    .cornerRadius(20)

                if let name = meal.name {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(meal.totalCalories) kcal")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
            }

            // Items
            VStack(spacing: 6) {
                ForEach(meal.items) { item in
                    HStack {
                        Text(item.food)
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.current.primaryText)
                        Spacer()
                        Text(String(format: "%.0fg", item.amountG))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(themeManager.current.secondaryText)
                        Text("·  \(item.calories) kcal")
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }
            }

            // Macro pills
            HStack(spacing: 8) {
                macroPill("P", "\(meal.totalProtein)g", Color(red: 0.93, green: 0.36, blue: 0.36))
                macroPill("C", "\(meal.totalCarbs)g", Color(red: 0.95, green: 0.61, blue: 0.20))
                macroPill("F", "\(meal.totalFat)g", Color(red: 0.35, green: 0.62, blue: 0.93))
                Spacer()

                // Camera button (only for today and future days)
                if day.date >= today {
                    Button(action: {
                        selectedMealForPhoto = meal
                        showCamera = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                            Text("Log")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(themeManager.current == .dark ? .black : .white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(themeManager.current == .dark ? Color.white : Color.black)
                        .cornerRadius(20)
                    }
                }
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func macroPill(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(color)
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(themeManager.current.secondaryText)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Empty & Generating Views

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
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { isGenerating = true; generatePlan() }) {
                Text("Generate Meal Plan")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
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
            Text("Building your 7-day meal plan…")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
            Text("This usually takes 10–20 seconds")
                .font(.system(size: 13))
                .foregroundColor(themeManager.current.secondaryText)
            Spacer()
        }
    }

    // MARK: - Logic

    func loadOrGeneratePlan() {
        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID
        isLoading = true
        HealthAPIManager.shared.fetchCurrentWeekPlan(userId: userId) { plan in
            isLoading = false
            if let plan = plan {
                weeklyPlan = plan
                selectedDayIndex = todayIndex
            }
            // else: show empty state with generate button
        }
    }

    func generatePlan() {
        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID
        HealthAPIManager.shared.generateWeeklyMealPlan(
            userId: userId,
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

    func analyzePhoto(imageData: Data) {
        guard let meal = selectedMealForPhoto,
              let plan = weeklyPlan
        else { return }

        isAnalyzing = true  // 显示加载遮罩

        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID

        let currentDay = selectedDayIndex < plan.days.count ? plan.days[selectedDayIndex] : nil
        let remaining = Array(plan.days.dropFirst(selectedDayIndex + 1))

        HealthAPIManager.shared.analyzeMealPhoto(
            imageData: imageData,
            userId: userId,
            date: currentDay?.date ?? today,
            mealType: meal.mealType,
            plannedMeal: meal,
            remainingPlan: remaining
        ) { log, err in
            isAnalyzing = false  // 隐藏加载遮罩
            if let log = log {
                complianceResult = log
                showCompliance = true
                // 通知 Dashboard 刷新（meal 已保存到 history）
                NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)
            } else {
                errorMsg = err ?? "Failed to analyse photo"
                showError = true
            }
        }
    }

    func weekStartLabel(_ plan: WeeklyMealPlan) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        if let d = DateFormatter().date(from: plan.weekStartDate) { return f.string(from: d) }
        return plan.weekStartDate
    }

    func dayNum(_ dateStr: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        if let d = f.date(from: dateStr) {
            let f2 = DateFormatter(); f2.dateFormat = "d"
            return f2.string(from: d)
        }
        return ""
    }

    func mealTypeColor(_ type: String) -> Color {
        switch type.lowercased() {
        case "breakfast": return Color(red: 0.95, green: 0.61, blue: 0.20)
        case "lunch":     return Color(red: 0.35, green: 0.62, blue: 0.93)
        case "dinner":    return Color(red: 0.55, green: 0.35, blue: 0.85)
        default:          return .gray
        }
    }
}

// MARK: - Photo Compliance View

struct PhotoComplianceView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    let mealLog: MealLog
    let weeklyPlan: WeeklyMealPlan?

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
                        // Score card
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.12), lineWidth: 12)
                                    .frame(width: 140, height: 140)
                                Circle()
                                    .trim(from: 0, to: CGFloat(mealLog.complianceScore) / 100.0)
                                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .frame(width: 140, height: 140)
                                    .rotationEffect(.degrees(-90))
                                VStack(spacing: 2) {
                                    Text("\(mealLog.complianceScore)")
                                        .font(.system(size: 42, weight: .black, design: .rounded))
                                        .foregroundColor(themeManager.current.primaryText)
                                    Text("/ 100")
                                        .font(.system(size: 14))
                                        .foregroundColor(themeManager.current.secondaryText)
                                }
                            }
                            Text("Compliance Score")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(themeManager.current.primaryText)
                            Text(mealLog.complianceFeedback)
                                .font(.system(size: 14))
                                .foregroundColor(themeManager.current.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 20)

                        // Detected vs planned comparison
                        comparisonCard

                        // AI adjustment note
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
                    Button("Done") { dismiss() }
                        .foregroundColor(themeManager.current.primaryText)
                }
            }
        }
    }

    var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Actual vs Planned")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)

            let planned = mealLog.plannedMeal
            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Actual")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(themeManager.current.secondaryText)
                    compRow("Calories", "\(mealLog.estimatedCalories) kcal")
                    compRow("Protein", "\(mealLog.estimatedProtein)g")
                    compRow("Carbs", "\(mealLog.estimatedCarbs)g")
                    compRow("Fat", "\(mealLog.estimatedFat)g")
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 120).background(themeManager.current.cardBorder)

                VStack(spacing: 8) {
                    Text("Planned")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(themeManager.current.secondaryText)
                    compRow("Calories", planned.map { "\($0.totalCalories) kcal" } ?? "—")
                    compRow("Protein", planned.map { "\($0.totalProtein)g" } ?? "—")
                    compRow("Carbs", planned.map { "\($0.totalCarbs)g" } ?? "—")
                    compRow("Fat", planned.map { "\($0.totalFat)g" } ?? "—")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func compRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(themeManager.current.secondaryText)
        }
    }

    func adjustmentCard(note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.current.primaryText)
                Text("Plan Adjusted")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
            }
            Text(note)
                .font(.system(size: 14))
                .foregroundColor(themeManager.current.secondaryText)
                .lineSpacing(4)
        }
        .padding(16)
        .background(themeManager.current.inputBackground)
        .cornerRadius(16)
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
            parent.onCapture(info[.originalImage] as? UIImage)
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCapture(nil)
            parent.dismiss()
        }
    }
}

// MARK: - Health Dashboard View (tab bar root)

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
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Today")
                }
                .tag(0)

            MealPlanView(nutritionPlan: nutritionPlan, healthProfile: healthProfile)
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "calendar.badge.checkmark" : "calendar")
                    Text("Diet Plan")
                }
                .tag(1)

            ProfileView()
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "person.fill" : "person")
                    Text("Profile")
                }
                .tag(2)
        }
        .tint(themeManager.current == .dark ? .white : .black)
        .preferredColorScheme(themeManager.current.colorScheme)
    }
}

// MARK: - Today View — 直接复用原有 DashboardView（食物记录 + 营养统计）

struct TodayView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile

    var body: some View {
        // 直接用原有的 DashboardView，完整功能：拍照记录、营养统计、每日/周/月切换
        DashboardView()
            .environmentObject(themeManager)
    }
}
