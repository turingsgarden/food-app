//  DietPlanView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/8/26.
//
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
                if isLoading          { loadingView }
                else if isGenerating  { generatingView }
                else if healthProfile == nil { noProfileView }
                else if let report = healthReport { reportView(report: report) }
                else                  { generatePromptView }
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
            .alert("Update Your Health Plan?", isPresented: $showRefreshPrompt) {
                Button("Yes, Regenerate") { generateReport(force: true) }
                Button("Keep Current Plan", role: .cancel) {}
            } message: {
                Text("It's been over 7 days since your health plan was last generated. Would you like to refresh it with your latest profile?")
            }
        }
    }

    // MARK: - Data

    func loadData() {
        guard healthReport == nil, !isLoading, !isGenerating else { return }
        isLoading = true
        HealthAPIManager.shared.fetchHealthProfile(userId: currentUserId) { profile in
            self.healthProfile = profile
            guard profile != nil else { self.isLoading = false; return }
            HealthAPIManager.shared.fetchHealthReport { report in
                self.isLoading = false
                if let report = report {
                    self.healthReport = report
                    self.checkReportAge(report: report)
                } else {
                    self.generateReport(force: false)
                }
            }
        }
    }

    func checkReportAge(report: HealthReport) {
        guard let str = report.createdAt else { return }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        guard let date = f1.date(from: str) ?? f2.date(from: str) else { return }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days >= 7 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showRefreshPrompt = true } }
    }

    func generateReport(force: Bool) {
        isGenerating = true
        HealthAPIManager.shared.generateHealthReport(goals: [], force: force) { report, err in
            self.isGenerating = false
            if let report = report { self.healthReport = report }
            else { self.errorMsg = err ?? "Failed to generate report"; self.showError = true }
        }
    }

    // MARK: - Report View

    func reportView(report: HealthReport) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {

                // ── Page header ────────────────────────────────────────────
                pageHeader(report: report)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                // ── 1. Score hero ──────────────────────────────────────────
                scoreHeroCard(report: report)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // ── 2. Profile completeness nudge ──────────────────────────
                profileCompletenessCard(report: report)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // ── 3. Daily nutrition goals ───────────────────────────────
                nutritionGoalsCard(report: report)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // ── 4. Health indicators ───────────────────────────────────
                if !report.attentionItems.isEmpty {
                    healthIndicatorsSection(items: report.attentionItems)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                // ── 5. Recommended foods — redesigned ─────────────────────
                if !report.recommendedFoods.isEmpty {
                    recommendedFoodsSection(foods: report.recommendedFoods)
                        .padding(.bottom, 16)
                }

                // ── 6. Foods to limit ──────────────────────────────────────
                if !report.foodsToLimit.isEmpty {
                    foodsToLimitCard(foods: report.foodsToLimit)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                // ── 7. Lifestyle tip ───────────────────────────────────────
                lifestyleTipCard(tip: report.lifestyleTip)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                // ── Refresh button ─────────────────────────────────────────
                Button(action: { generateReport(force: true) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                        Text("Regenerate Report").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(themeManager.current.secondaryText)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(themeManager.current.inputBackground).cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(themeManager.current.cardBorder, lineWidth: 1))
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Page Header

    func pageHeader(report: HealthReport) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Health Report")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                if let date = report.createdAt {
                    Text("Updated \(formatDate(date))")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }
            Spacer()
            // Edit profile button — more prominent than before
            Button(action: { showProfileSetup = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "pencil").font(.system(size: 12, weight: .semibold))
                    Text("Edit Profile").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(themeManager.current == .dark ? .black : .white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(themeManager.current == .dark ? Color.white : Color.black)
                .cornerRadius(20)
            }
        }
    }

    // MARK: - Score Hero (redesigned)

    func scoreHeroCard(report: HealthReport) -> some View {
        let color = scoreColor(report.healthScore)
        return VStack(spacing: 0) {
            // Top: score + badge + summary
            HStack(spacing: 20) {
                // Score ring — larger, more prominent
                ZStack {
                    Circle().stroke(color.opacity(0.12), lineWidth: 12).frame(width: 110, height: 110)
                    Circle()
                        .trim(from: 0, to: CGFloat(report.healthScore) / 100.0)
                        .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 110, height: 110).rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 1.2), value: report.healthScore)
                    VStack(spacing: 1) {
                        Text("\(report.healthScore)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                        Text("/ 100")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    // Status badge
                    Text(report.statusBadge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(color.opacity(0.10)).cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.25), lineWidth: 1))

                    Text(report.healthSummary)
                        .font(.system(size: 13)).lineSpacing(3)
                        .foregroundColor(themeManager.current.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .background(themeManager.current.cardBackground).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.15), lineWidth: 1.5))
    }

    func scoreColor(_ score: Int) -> Color {
        score >= 80 ? .green : score >= 60 ? .orange : .red
    }

    // MARK: - Profile Completeness Nudge (NEW)
    // Shows how many optional clinical fields are filled,
    // with a direct CTA to add more for a better report.

    func profileCompletenessCard(report: HealthReport) -> some View {
        let filledCount = attentionItemsFilledCount(report: report)
        let totalCount = 4  // BP, blood sugar, cholesterol, triglycerides
        let pct = Double(filledCount) / Double(totalCount)
        let isComplete = filledCount == totalCount

        return Button(action: { showProfileSetup = true }) {
            HStack(spacing: 14) {
                // Mini progress ring
                ZStack {
                    Circle().stroke(themeManager.current.cardBorder, lineWidth: 5).frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: pct)
                        .stroke(isComplete ? Color.green : Color.orange,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 44, height: 44).rotationEffect(.degrees(-90))
                    Text("\(filledCount)/\(totalCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isComplete ? "Profile complete" : "Add more data for a better report")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text(isComplete
                         ? "All clinical markers filled — your report is fully personalised"
                         : "Blood pressure, glucose, cholesterol & triglycerides improve accuracy")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                if !isComplete {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(themeManager.current.secondaryText.opacity(0.5))
                }
            }
            .padding(14)
            .background(isComplete
                        ? Color.green.opacity(0.04)
                        : Color.orange.opacity(0.04))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isComplete ? Color.green.opacity(0.15) : Color.orange.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // Count how many clinical markers are present in the attention items
    func attentionItemsFilledCount(report: HealthReport) -> Int {
        let markers = ["Blood Pressure", "Blood Sugar", "Glucose", "Cholesterol", "Triglycerides"]
        let found = report.attentionItems.filter { item in
            markers.contains { item.metric.localizedCaseInsensitiveContains($0) }
        }.count
        return min(found, 4)
    }

    // MARK: - Nutrition Goals (improved layout)

    func nutritionGoalsCard(report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack(alignment: .lastTextBaseline) {
                Text("Daily Nutrition Goals")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(report.dailyCalories)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("kcal / day")
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.current.secondaryText)
                }
            }

            // Macro summary pills
            HStack(spacing: 8) {
                macroPill("P", value: "\(report.proteinG)g", color: Color(red: 0.93, green: 0.36, blue: 0.36))
                macroPill("C", value: "\(report.carbsG)g", color: Color(red: 0.95, green: 0.61, blue: 0.20))
                macroPill("F", value: "\(report.fatG)g", color: Color(red: 0.35, green: 0.62, blue: 0.93))
                macroPill("Fi", value: "\(report.fiberG)g", color: Color(red: 0.35, green: 0.75, blue: 0.45))
            }

            Divider().background(themeManager.current.cardBorder)

            // Detailed bars
            VStack(spacing: 12) {
                nutrientBar("Protein",       value: report.proteinG,  maxValue: 200, unit: "g",  color: Color(red: 0.93, green: 0.36, blue: 0.36))
                nutrientBar("Carbohydrates", value: report.carbsG,    maxValue: 400, unit: "g",  color: Color(red: 0.95, green: 0.61, blue: 0.20))
                nutrientBar("Fat",           value: report.fatG,      maxValue: 100, unit: "g",  color: Color(red: 0.35, green: 0.62, blue: 0.93))
                nutrientBar("Fiber",         value: report.fiberG,    maxValue: 50,  unit: "g",  color: Color(red: 0.35, green: 0.75, blue: 0.45))
                nutrientBar("Sodium",        value: report.sodiumMg,  maxValue: 3000, unit: "mg", color: Color(red: 0.75, green: 0.35, blue: 0.85))
            }

            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText)
                Text("Weekly total: \(report.weeklyCalories) kcal")
                    .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
            }
        }
        .padding(18).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func macroPill(_ letter: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(letter)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.current.primaryText)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.08)).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(color.opacity(0.15), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    func nutrientBar(_ name: String, value: Int, maxValue: Int, unit: String, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(name).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text("\(value) \(unit)").font(.system(size: 13, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.10)).frame(height: 7)
                    RoundedRectangle(cornerRadius: 4).fill(color)
                        .frame(width: geo.size.width * min(Double(value) / Double(maxValue), 1.0), height: 7)
                }
            }
            .frame(height: 7)
        }
    }

    // MARK: - Health Indicators (cleaner cards)

    func healthIndicatorsSection(items: [AttentionItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Indicators")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)

            ForEach(items) { item in
                let color: Color = item.status == "normal" ? .green : item.status == "borderline" ? .orange : .red
                let icon = item.status == "normal" ? "checkmark.circle.fill" : item.status == "borderline" ? "exclamationmark.triangle.fill" : "xmark.circle.fill"

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                        .frame(width: 28, height: 28)
                        .background(color.opacity(0.08))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.metric)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.current.primaryText)
                            Spacer()
                            Text(item.currentValue)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(color)
                        }
                        Text(item.advice)
                            .font(.system(size: 12)).lineSpacing(2)
                            .foregroundColor(themeManager.current.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(color.opacity(0.04)).cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
            }
        }
    }

    // MARK: - Recommended Foods (completely redesigned)
    // Horizontal scroll of food cards with benefit tags + dish chips below

    func recommendedFoodsSection(foods: [RecommendedFood]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended Foods")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("Personalised for your health profile")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                Text("\(foods.count) foods")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(themeManager.current.inputBackground).cornerRadius(12)
            }
            .padding(.horizontal, 20)

            // Horizontal card scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(foods.enumerated()), id: \.offset) { _, food in
                        foodCard(food: food)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    func foodCard(food: RecommendedFood) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Emoji header
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(themeManager.current.inputBackground)
                    .frame(height: 80)
                Text(foodEmoji(food.food))
                    .font(.system(size: 40))
            }
            .padding(.bottom, 10)

            // Food name
            Text(food.food)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
                .lineLimit(1)
                .padding(.bottom, 4)

            // Reason
            Text(food.reason)
                .font(.system(size: 12)).lineSpacing(2)
                .foregroundColor(themeManager.current.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Divider().background(themeManager.current.cardBorder).padding(.bottom, 10)

            // Dish chips
            VStack(alignment: .leading, spacing: 4) {
                Text("Try these")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(themeManager.current.secondaryText)
                    .textCase(.uppercase).tracking(0.4)
                    .padding(.bottom, 2)

                ForEach(food.dishes.prefix(3), id: \.self) { dish in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green.opacity(0.5))
                            .frame(width: 5, height: 5)
                        Text(dish)
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.current.primaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 200)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(Color.green.opacity(0.15), lineWidth: 1))
    }

    func foodEmoji(_ food: String) -> String {
        let l = food.lowercased()
        if l.contains("salmon") || l.contains("fish") { return "🐟" }
        if l.contains("chicken") || l.contains("turkey") { return "🍗" }
        if l.contains("beef") || l.contains("meat") { return "🥩" }
        if l.contains("egg") { return "🥚" }
        if l.contains("tofu") || l.contains("soy") { return "🫘" }
        if l.contains("broccoli") { return "🥦" }
        if l.contains("spinach") || l.contains("kale") { return "🥬" }
        if l.contains("avocado") { return "🥑" }
        if l.contains("quinoa") || l.contains("oat") { return "🌾" }
        if l.contains("blueberry") || l.contains("berry") { return "🫐" }
        if l.contains("apple") { return "🍎" }
        if l.contains("banana") { return "🍌" }
        if l.contains("almond") || l.contains("nut") { return "🥜" }
        if l.contains("yogurt") || l.contains("milk") { return "🥛" }
        if l.contains("lentil") || l.contains("bean") { return "🫘" }
        if l.contains("sweet potato") || l.contains("potato") { return "🍠" }
        if l.contains("rice") { return "🍚" }
        if l.contains("olive") { return "🫒" }
        return "🥗"
    }

    // MARK: - Foods to Limit

    func foodsToLimitCard(foods: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13)).foregroundColor(.orange)
                Text("Foods to Limit")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
            }
            Text("Reducing these will support your health goals")
                .font(.system(size: 12))
                .foregroundColor(themeManager.current.secondaryText)

            FlowLayout(items: foods) { food in
                HStack(spacing: 5) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(food)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.orange.opacity(0.07)).cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.orange.opacity(0.18), lineWidth: 1))
            }
        }
        .padding(16).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.orange.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Lifestyle Tip

    func lifestyleTipCard(tip: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.20))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Daily Habit Tip")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.75, green: 0.55, blue: 0.0))
                    .textCase(.uppercase).tracking(0.4)
                Text(tip)
                    .font(.system(size: 14)).lineSpacing(3)
                    .foregroundColor(themeManager.current.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.07)).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.18), lineWidth: 1))
    }

    // MARK: - State Views (unchanged logic, cleaner copy)

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText))
                .scaleEffect(1.3)
            Text("Loading your health report…")
                .font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
        }
    }

    var generatingView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().stroke(themeManager.current.cardBorder, lineWidth: 3).frame(width: 80, height: 80)
                Image(systemName: "waveform.path.ecg").font(.system(size: 32)).foregroundColor(themeManager.current.secondaryText)
            }
            VStack(spacing: 8) {
                Text("Generating your report…")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                Text("This usually takes 10–20 seconds")
                    .font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
            }
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText))
            Spacer()
        }
    }

    var noProfileView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60)).foregroundColor(themeManager.current.secondaryText.opacity(0.35))
            VStack(spacing: 8) {
                Text("Set Up Your Health Profile")
                    .font(.system(size: 20, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Text("We'll create a personalised nutrition plan based on your body metrics and health data.")
                    .font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Button(action: { showProfileSetup = true }) {
                Text("Set Up Profile")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(themeManager.current == .dark ? .black : .white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(themeManager.current == .dark ? Color.white : Color.black).cornerRadius(16)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    var generatePromptView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 56)).foregroundColor(themeManager.current.secondaryText.opacity(0.35))
            VStack(spacing: 8) {
                Text("Generate Your Health Report")
                    .font(.system(size: 20, weight: .bold)).foregroundColor(themeManager.current.primaryText)
                Text("Get AI-powered analysis with personalised food recommendations based on your profile.")
                    .font(.system(size: 14)).foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Button(action: { generateReport(force: true) }) {
                Text("Generate Report")
                    .font(.system(size: 16, weight: .bold))
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

// MARK: - FlowLayout (unchanged)

struct FlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]; let content: (Item) -> Content
    @State private var totalHeight: CGFloat = .zero
    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) { self.items = items; self.content = content }
    var body: some View { GeometryReader { geo in generateContent(in: geo) }.frame(height: totalHeight) }
    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero; var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item).padding(.trailing, 8).padding(.bottom, 8)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width { width = 0; height -= d.height }
                        let result = width; if item == items.last { width = 0 } else { width -= d.width }; return result
                    }
                    .alignmentGuide(.top) { _ in let result = height; if item == items.last { height = 0 }; return result }
            }
        }
        .background(GeometryReader { geo in
            Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
        })
        .onPreferenceChange(HeightPreferenceKey.self) { totalHeight = $0 }
    }
}
private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - HealthDashboardView & TodayView (unchanged)

struct HealthDashboardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView().environmentObject(themeManager).tabItem {
                Image(systemName: selectedTab == 0 ? "house.fill" : "house"); Text("Today")
            }.tag(0)
            DietPlanView().environmentObject(themeManager).tabItem {
                Image(systemName: selectedTab == 1 ? "heart.text.square.fill" : "heart.text.square"); Text("Health")
            }.tag(1)
            ProfileView().environmentObject(themeManager).tabItem {
                Image(systemName: selectedTab == 2 ? "person.fill" : "person"); Text("Profile")
            }.tag(2)
        }
        .tint(themeManager.current == .dark ? .white : .black)
        .preferredColorScheme(themeManager.current.colorScheme)
    }
}

struct TodayView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile
    var body: some View { DashboardView().environmentObject(themeManager) }
}
