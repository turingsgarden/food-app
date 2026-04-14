// DietPlanView.swift
// 新增：7天后弹出"要重新生成计划吗"的提示

import SwiftUI

struct DietPlanView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared

    @State private var healthProfile: HealthProfile?
    @State private var healthReport: HealthReport?
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var errorMsg = ""
    @State private var showError = false
    @State private var showProfileSetup = false
    @State private var expandedFoodIndex: Int? = nil
    // ✅ 7天更新提示
    @State private var showRefreshPrompt = false

    var currentUserId: String {
        session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if isGenerating {
                    generatingView
                } else if healthProfile == nil {
                    noProfileView
                } else if let report = healthReport {
                    reportView(report: report)
                } else {
                    generatePromptView
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .onAppear { loadData() }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMsg) }
            .sheet(isPresented: $showProfileSetup) {
                HealthProfileView { profile in
                    self.healthProfile = profile
                    HealthAPIManager.shared.saveHealthProfile(profile) { _, _ in }
                    generateReport(force: true)
                }
                .environmentObject(themeManager)
            }
            // ✅ 7天期限提示弹窗
            .alert("Update Your Health Plan?", isPresented: $showRefreshPrompt) {
                Button("Yes, Regenerate") { generateReport(force: true) }
                Button("Keep Current Plan", role: .cancel) {}
            } message: {
                Text("It's been over 7 days since your health plan was last generated. Would you like to refresh it with your latest profile?")
            }
        }
    }

    // MARK: - Load Data

    func loadData() {
        if healthReport != nil { return }
        if isLoading || isGenerating { return }

        isLoading = true

        HealthAPIManager.shared.fetchHealthProfile(userId: currentUserId) { profile in
            self.healthProfile = profile

            if profile == nil {
                self.isLoading = false
                return
            }

            HealthAPIManager.shared.fetchHealthReport { report in
                self.isLoading = false
                if let report = report {
                    self.healthReport = report
                    // ✅ 检查是否超过7天
                    self.checkReportAge(report: report)
                } else {
                    self.generateReport(force: false)
                }
            }
        }
    }

    // ✅ 检查报告是否超过7天
    func checkReportAge(report: HealthReport) {
        guard let createdAtStr = report.createdAt else { return }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        let createdAt = f1.date(from: createdAtStr) ?? f2.date(from: createdAtStr)
        guard let createdAt = createdAt else { return }
        let daysSince = Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
        if daysSince >= 7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showRefreshPrompt = true
            }
        }
    }

    func generateReport(force: Bool) {
        isGenerating = true
        HealthAPIManager.shared.generateHealthReport(goals: [], force: force) { report, err in
            self.isGenerating = false
            if let report = report {
                self.healthReport = report
            } else {
                self.errorMsg = err ?? "Failed to generate report"
                self.showError = true
            }
        }
    }

    // MARK: - Report View

    func reportView(report: HealthReport) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                reportHeader(report: report).padding(.horizontal, 20).padding(.top, 16)
                healthScoreCard(report: report).padding(.horizontal, 20)
                nutritionTargetsCard(report: report).padding(.horizontal, 20)
                if !report.attentionItems.isEmpty {
                    attentionSection(items: report.attentionItems).padding(.horizontal, 20)
                }
                if !report.recommendedFoods.isEmpty {
                    recommendedFoodsSection(foods: report.recommendedFoods).padding(.horizontal, 20)
                }
                if !report.foodsToLimit.isEmpty {
                    foodsToLimitCard(foods: report.foodsToLimit).padding(.horizontal, 20)
                }
                lifestyleTipCard(tip: report.lifestyleTip).padding(.horizontal, 20)

                Button(action: { generateReport(force: true) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                        Text("Update Health Report").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(themeManager.current.secondaryText)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(themeManager.current.inputBackground).cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(themeManager.current.cardBorder, lineWidth: 1))
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 80)
            }
        }
    }

    func reportHeader(report: HealthReport) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Health Report")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                if let date = report.createdAt {
                    Text("Updated \(formatDate(date))")
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }
            Spacer()
            Button(action: { showProfileSetup = true }) {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                    .frame(width: 36, height: 36)
                    .background(themeManager.current.inputBackground)
                    .cornerRadius(10)
            }
        }
    }

    func healthScoreCard(report: HealthReport) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.12), lineWidth: 10).frame(width: 100, height: 100)
                Circle().trim(from: 0, to: CGFloat(report.healthScore) / 100.0)
                    .stroke(scoreColor(report.healthScore), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 100, height: 100).rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: report.healthScore)
                VStack(spacing: 2) {
                    Text("\(report.healthScore)").font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("/ 100").font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(report.statusBadge).font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(scoreColor(report.healthScore)).cornerRadius(20)
                Text(report.healthSummary).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20).background(themeManager.current.cardBackground).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    func nutritionTargetsCard(report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Daily Nutrition Goals").font(.system(size: 15, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Spacer()
                Text("\(report.dailyCalories) kcal/day").font(.system(size: 13, weight: .semibold)).foregroundColor(themeManager.current.secondaryText)
            }
            VStack(spacing: 10) {
                nutrientBar("Protein",       value: report.proteinG,  unit: "g",  color: Color(red: 0.93, green: 0.36, blue: 0.36))
                nutrientBar("Carbohydrates", value: report.carbsG,    unit: "g",  color: Color(red: 0.95, green: 0.61, blue: 0.20))
                nutrientBar("Fat",           value: report.fatG,      unit: "g",  color: Color(red: 0.35, green: 0.62, blue: 0.93))
                nutrientBar("Fiber",         value: report.fiberG,    unit: "g",  color: Color(red: 0.35, green: 0.75, blue: 0.45))
                nutrientBar("Sodium",        value: report.sodiumMg,  unit: "mg", color: Color(red: 0.75, green: 0.35, blue: 0.85))
            }
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                Text("Weekly total: \(report.weeklyCalories) kcal").font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .padding(16).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func nutrientBar(_ name: String, value: Int, unit: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText).frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.12)).frame(height: 8)
                    RoundedRectangle(cornerRadius: 4).fill(color)
                        .frame(width: barWidth(geo.size.width, name: name, value: value), height: 8)
                }
            }
            .frame(height: 8)
            Text("\(value)\(unit)").font(.system(size: 13, weight: .semibold)).foregroundColor(themeManager.current.primaryText).frame(width: 60, alignment: .trailing)
        }
    }

    func barWidth(_ totalWidth: CGFloat, name: String, value: Int) -> CGFloat {
        let maxValues: [String: Int] = ["Protein": 200, "Carbohydrates": 400, "Fat": 100, "Fiber": 50, "Sodium": 3000]
        let maxVal = Double(maxValues[name] ?? 200)
        let ratio = min(Double(value) / maxVal, 1.0)
        return totalWidth * ratio
    }

    func attentionSection(items: [AttentionItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Indicators").font(.system(size: 15, weight: .bold)).foregroundColor(themeManager.current.primaryText)
            ForEach(items) { item in
                let color: Color = item.status == "normal" ? .green : item.status == "borderline" ? .orange : .red
                HStack(spacing: 14) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.metric).font(.system(size: 14, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                            Spacer()
                            Text(item.currentValue).font(.system(size: 13, weight: .medium)).foregroundColor(color)
                        }
                        Text(item.advice).font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14).background(color.opacity(0.05)).cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
            }
        }
    }

    func recommendedFoodsSection(foods: [RecommendedFood]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recommended Foods").font(.system(size: 15, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Text("Tap each food to see dish ideas").font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
            }
            ForEach(Array(foods.enumerated()), id: \.offset) { idx, food in
                let isExpanded = expandedFoodIndex == idx
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            expandedFoodIndex = isExpanded ? nil : idx
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text(foodEmoji(food.food)).font(.system(size: 26))
                                .frame(width: 44, height: 44).background(themeManager.current.inputBackground).cornerRadius(12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(food.food).font(.system(size: 15, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                                Text(food.reason).font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                                    .lineLimit(isExpanded ? nil : 1).fixedSize(horizontal: false, vertical: isExpanded)
                            }
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(themeManager.current.secondaryText)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                    if isExpanded {
                        Divider().background(themeManager.current.cardBorder).padding(.horizontal, 14)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dish Ideas").font(.system(size: 11, weight: .semibold))
                                .foregroundColor(themeManager.current.secondaryText).textCase(.uppercase).tracking(0.5)
                            ForEach(food.dishes, id: \.self) { dish in
                                HStack(spacing: 8) {
                                    Image(systemName: "fork.knife").font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
                                    Text(dish).font(.system(size: 13)).foregroundColor(themeManager.current.primaryText)
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
                .background(themeManager.current.cardBackground).cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
            }
        }
    }

    func foodEmoji(_ food: String) -> String {
        let lower = food.lowercased()
        if lower.contains("salmon") || lower.contains("fish") { return "🐟" }
        if lower.contains("chicken") || lower.contains("turkey") { return "🍗" }
        if lower.contains("beef") || lower.contains("meat") { return "🥩" }
        if lower.contains("egg") { return "🥚" }
        if lower.contains("tofu") || lower.contains("soy") { return "🫘" }
        if lower.contains("broccoli") { return "🥦" }
        if lower.contains("spinach") || lower.contains("kale") { return "🥬" }
        if lower.contains("avocado") { return "🥑" }
        if lower.contains("quinoa") || lower.contains("oat") { return "🌾" }
        if lower.contains("blueberry") || lower.contains("berry") { return "🫐" }
        if lower.contains("apple") { return "🍎" }
        if lower.contains("banana") { return "🍌" }
        if lower.contains("almond") || lower.contains("nut") { return "🥜" }
        if lower.contains("yogurt") || lower.contains("milk") { return "🥛" }
        if lower.contains("lentil") || lower.contains("bean") { return "🫘" }
        if lower.contains("sweet potato") || lower.contains("potato") { return "🍠" }
        if lower.contains("rice") { return "🍚" }
        if lower.contains("olive") { return "🫒" }
        return "🥗"
    }

    func foodsToLimitCard(foods: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13)).foregroundColor(.orange)
                Text("Foods to Limit").font(.system(size: 15, weight: .bold)).foregroundColor(themeManager.current.primaryText)
            }
            FlowLayout(items: foods) { food in
                Text(food).font(.system(size: 13)).foregroundColor(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.08)).cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.orange.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(16).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func lifestyleTipCard(tip: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "lightbulb.fill").font(.system(size: 20))
                .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.20))
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Habit Tip").font(.system(size: 12, weight: .bold)).foregroundColor(themeManager.current.secondaryText)
                    .textCase(.uppercase).tracking(0.4)
                Text(tip).font(.system(size: 14)).foregroundColor(themeManager.current.primaryText)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).background(Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.08)).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.2), lineWidth: 1))
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText)).scaleEffect(1.3)
            Text("Loading your health report…").font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
        }
    }

    var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText)).scaleEffect(1.5)
            VStack(spacing: 8) {
                Text("Analysing your health profile…").font(.system(size: 17, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                Text("This usually takes 10–20 seconds").font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
            }
            Spacer()
        }
    }

    var noProfileView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 60))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            VStack(spacing: 8) {
                Text("Set Up Your Health Profile").font(.system(size: 20, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Text("We'll analyze your health data and create a personalized nutrition and food plan")
                    .font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Button(action: { showProfileSetup = true }) {
                Text("Set Up Profile").font(.system(size: 16, weight: .bold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(themeManager.current == .dark ? Color.white : Color.black).cornerRadius(16)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    var generatePromptView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.path.ecg.rectangle").font(.system(size: 56))
                .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
            VStack(spacing: 8) {
                Text("Generate Your Health Report").font(.system(size: 20, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Text("Get AI-powered analysis of your health profile with personalized food recommendations")
                    .font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Button(action: { generateReport(force: true) }) {
                Text("Generate Report").font(.system(size: 16, weight: .bold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(themeManager.current == .dark ? Color.white : Color.black).cornerRadius(16)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    func formatDate(_ str: String) -> String {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: str) { let out = DateFormatter(); out.dateFormat = "MMM d, yyyy"; return out.string(from: d) }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: str) { let out = DateFormatter(); out.dateFormat = "MMM d, yyyy"; return out.string(from: d) }
        return str
    }
}

// MARK: - Flow Layout

struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    @State private var totalHeight: CGFloat = .zero

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items; self.content = content
    }

    var body: some View {
        GeometryReader { geo in generateContent(in: geo) }.frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero; var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item).padding(.trailing, 8).padding(.bottom, 8)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width { width = 0; height -= d.height }
                        let result = width
                        if item == items.last { width = 0 } else { width -= d.width }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last { height = 0 }
                        return result
                    }
            }
        }
        .background(heightReader($totalHeight))
    }

    private func heightReader(_ height: Binding<CGFloat>) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
        }
        .onPreferenceChange(HeightPreferenceKey.self) { height.wrappedValue = $0 }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
// HealthDashboardView.swift 内容追加到 DietPlanView.swift 末尾

struct HealthDashboardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Today")
                }
                .tag(0)

            DietPlanView()
                .environmentObject(themeManager)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "heart.text.square.fill" : "heart.text.square")
                    Text("Health")
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

struct TodayView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile
    var body: some View {
        DashboardView().environmentObject(themeManager)
    }
}
