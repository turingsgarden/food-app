//  DietPlanView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/8/26.



import SwiftUI

struct DietPlanView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @State private var showMenuSheet  = false
    @State private var showShareSheet  = false
    @State private var shareItems: [Any] = []
    @State private var isRenderingPDF  = false
    @State private var healthReport: HealthReport?
    @State private var healthProfile: HealthProfile?
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
                    EditHealthProfileView(
                        existingProfile: healthProfile,
                        onComplete: { [self] profile in
                            DispatchQueue.main.async {
                                self.healthProfile = profile
                                self.generateReport(force: true)
                            }
                        }
                    )
                    .environmentObject(themeManager)
                }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $showMenuSheet) {
                menuSheet
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.hidden)
                    .environmentObject(themeManager)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }            // ✅ 7天期限提示弹窗
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
            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────────────────
                reportHeader(report: report)
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)

                // ── Score + Summary (no card border, just background fill) ──
                healthScoreSection(report: report)
                    .padding(.horizontal, 20).padding(.bottom, 24)

                // ── Nutrition (no box, just inline rows with dividers) ───────
                nutritionSection(report: report)
                    .padding(.bottom, 24)

                // ── Health Indicators (no individual boxes, unified list) ───
                if !report.attentionItems.isEmpty {
                    attentionSection(items: report.attentionItems)
                        .padding(.horizontal, 20).padding(.bottom, 24)
                }

                // ── Recommended Foods (horizontal scroll cards) ─────────────
                if !report.recommendedFoods.isEmpty {
                    recommendedFoodsSection(foods: report.recommendedFoods)
                        .padding(.bottom, 24)
                }

                // ── Foods to Limit (inline tags, no box) ────────────────────
                if !report.foodsToLimit.isEmpty {
                    foodsToLimitSection(foods: report.foodsToLimit)
                        .padding(.horizontal, 20).padding(.bottom, 24)
                }

                // ── Lifestyle Tip (subtle, no border) ───────────────────────
                lifestyleTipCard(tip: report.lifestyleTip)
                    .padding(.horizontal, 20).padding(.bottom, 20)

                // ── Update button ────────────────────────────────────────────
                Button(action: { generateReport(force: true) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Update Health Report")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(themeManager.current.secondaryText)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(themeManager.current.inputBackground)
                    .cornerRadius(20)
                }
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Health Score Section (no card border)

    func healthScoreSection(report: HealthReport) -> some View {
        HStack(spacing: 20) {
            // Score ring
            ZStack {
                Circle().stroke(Color.gray.opacity(0.1), lineWidth: 10).frame(width: 90, height: 90)
                Circle().trim(from: 0, to: CGFloat(report.healthScore) / 100.0)
                    .stroke(scoreColor(report.healthScore), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 90, height: 90).rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 1.2), value: report.healthScore)
                VStack(spacing: 1) {
                    Text("\(report.healthScore)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("/ 100").font(.system(size: 10)).foregroundColor(themeManager.current.secondaryText)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(report.statusBadge)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(scoreColor(report.healthScore))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(scoreColor(report.healthScore).opacity(0.1))
                    .cornerRadius(20)
                Text(report.healthSummary)
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.current.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(scoreColor(report.healthScore).opacity(0.2), lineWidth: 1.5))
    }

    // MARK: - Nutrition Section (clean, no inner boxes)

    func nutritionSection(report: HealthReport) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(alignment: .center) {
                Text("Daily Nutrition")
                    .padding(.leading, 20)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(report.dailyCalories)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("kcal / day")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                .padding(.trailing, 0)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)

            // Donut + legend
            HStack(spacing: 16) {
                macroDonut(
                    protein: report.proteinG,
                    carbs:   report.carbsG,
                    fat:     report.fatG,
                    total:   report.dailyCalories
                )
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 7) {
                    macroLegendRow("Protein",
                        value: "\(report.proteinG)g",
                        pct: pct(report.proteinG * 4, of: report.dailyCalories),
                        color: Color(red: 0.93, green: 0.36, blue: 0.36))
                    macroLegendRow("Carbs",
                        value: "\(report.carbsG)g",
                        pct: pct(report.carbsG * 4, of: report.dailyCalories),
                        color: Color(red: 0.95, green: 0.61, blue: 0.20))
                    macroLegendRow("Fat",
                        value: "\(report.fatG)g",
                        pct: pct(report.fatG * 9, of: report.dailyCalories),
                        color: Color(red: 0.35, green: 0.62, blue: 0.93))
                }

                Spacer()
            }
            .padding(.leading, 60)   // ← 这一行把整个 donut+legend 往右推
            .padding(.trailing, 20)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 20).padding(.bottom, 10)

            // Fiber & Sodium
            HStack(spacing: 0) {
                microRow("Fiber",  value: "\(report.fiberG)g",   color: Color(red: 0.35, green: 0.75, blue: 0.45))
                Divider().frame(height: 28)
                microRow("Sodium", value: "\(report.sodiumMg)mg", color: Color(red: 0.75, green: 0.35, blue: 0.85))
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    // Macro donut using Canvas for a clean pie chart
    func macroDonut(protein: Int, carbs: Int, fat: Int, total: Int) -> some View {
        let proteinCal = Double(protein * 4)
        let carbsCal   = Double(carbs * 4)
        let fatCal     = Double(fat * 9)
        let sum        = max(proteinCal + carbsCal + fatCal, 1)

        let proteinAngle = proteinCal / sum * 360
        let carbsAngle   = carbsCal   / sum * 360
        let fatAngle     = fatCal     / sum * 360

        let segments: [(Double, Color)] = [
            (proteinAngle, Color(red: 0.93, green: 0.36, blue: 0.36)),
            (carbsAngle,   Color(red: 0.95, green: 0.61, blue: 0.20)),
            (fatAngle,     Color(red: 0.35, green: 0.62, blue: 0.93)),
        ]

        return ZStack {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                let start = segments[..<idx].reduce(0) { $0 + $1.0 }
                Circle()
                    .trim(from: start / 360, to: (start + seg.0) / 360)
                    .stroke(seg.1, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text("\(total)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text("kcal").font(.system(size: 9)).foregroundColor(themeManager.current.secondaryText)
            }
        }
    }

    func pct(_ numeratorCal: Int, of total: Int) -> String {
        guard total > 0 else { return "—" }
        return "\(Int(round(Double(numeratorCal) / Double(total) * 100)))%"
    }

    func macroLegendRow(_ name: String, value: String, pct: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(name).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
            Text(pct).font(.system(size: 11)).foregroundColor(themeManager.current.secondaryText).frame(width: 34, alignment: .trailing)
        }
    }

    func microRow(_ name: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 12)
    }

    // MARK: - Attention Section (unified card, no individual boxes)

    func attentionSection(items: [AttentionItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Health Indicators")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let color: Color = item.status == "normal" ? .green
                        : item.status == "borderline" ? .orange : .red
                    HStack(spacing: 12) {
                        // Status dot
                        Circle().fill(color).frame(width: 8, height: 8)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.metric)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(themeManager.current.primaryText)
                                Spacer()
                                Text(item.currentValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(color)
                            }
                            Text(item.advice)
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.current.secondaryText)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 12)

                    if idx < items.count - 1 {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(themeManager.current.cardBackground)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Recommended Foods (horizontal scroll, expandable cards)

    func recommendedFoodsSection(foods: [RecommendedFood]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recommended Foods")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("Personalised for your health profile")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                Text("\(foods.count) foods")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(themeManager.current.inputBackground).cornerRadius(8)
            }
            .padding(.horizontal, 20)

            // AI source banner (slim)
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)
                Text("Based on your meal history tracking and health profile")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.current.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.purple.opacity(0.06))
            .cornerRadius(10)
            .padding(.horizontal, 20)

            // Horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(foods.enumerated()), id: \.offset) { idx, food in
                        expandableFoodCard(food: food, idx: idx)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }

    func expandableFoodCard(food: RecommendedFood, idx: Int) -> some View {
        let isExpanded = expandedFoodIndex == idx
        let cardWidth: CGFloat = 180

        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expandedFoodIndex = isExpanded ? nil : idx
                }
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    // Emoji tile + basis badge
                    HStack(alignment: .top) {
                        Text(foodEmoji(food.food))
                            .font(.system(size: 28))
                            .frame(width: 50, height: 50)
                            .background(themeManager.current.inputBackground)
                            .cornerRadius(12)
                        Spacer()
                        if let basis = food.analysisBasis {
                            basisBadge(basis)
                        }
                    }

                    // Food name
                    Text(food.food)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Reason — collapsed: 3 lines; expanded: full text
                    Text(food.reason)
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.current.secondaryText)
                        .lineSpacing(2)
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    // Expand hint
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide dishes" : "Try these")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expanded: dish ideas
            if isExpanded {
                Divider().background(themeManager.current.cardBorder).padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 8) {
                    Text("TRY THESE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(themeManager.current.secondaryText)
                        .tracking(0.5)
                    ForEach(food.dishes, id: \.self) { dish in
                        HStack(spacing: 7) {
                            Circle().fill(Color.green.opacity(0.6)).frame(width: 5, height: 5)
                            Text(dish)
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.current.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        }
        .frame(width: cardWidth)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
    }

    // Analysis basis badge
    @ViewBuilder
    func basisBadge(_ basis: String) -> some View {
        let config: (String, Color) = {
            switch basis {
            case "meal_history_pattern": return ("🍽 Meals", .blue)
            case "clinical_marker":      return ("❤️ Health", .red)
            case "dietary_preference":   return ("🌿 Pref", .green)
            default:                     return ("✨", .gray)
            }
        }()
        Text(config.0)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(config.1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(config.1.opacity(0.1))
            .cornerRadius(6)
    }

    // MARK: - Foods to Limit (no box, just inline section)

    func foodsToLimitSection(foods: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("🚫")
                Text("Foods to Limit")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
            }
            FlowLayout(items: foods) { food in
                Text(food)
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.orange.opacity(0.15), lineWidth: 1))
            }
        }
    }

    func reportHeader(report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行
            HStack(alignment: .top) {
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

                // 右上角按钮组
                HStack(spacing: 8) {
                    // Edit Profile
                    Button(action: { showProfileSetup = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Edit")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(themeManager.current == .dark ? .black : .white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(themeManager.current == .dark ? Color.white : Color.black)
                        .cornerRadius(20)
                    }

                    // "..." Menu
                    Menu {
                        Button(action: {
                            if let r = healthReport {
                                shareItems = [buildShareText(r)]
                                showShareSheet = true
                            }
                        }) {
                            Label("Share as Text", systemImage: "square.and.arrow.up")
                        }

                        Button(action: {
                            exportReportAsPDF(report: report)
                        }) {
                            Label("Export as PDF", systemImage: "arrow.down.doc.fill")
                        }

                        Divider()

                        Button(action: { generateReport(force: true) }) {
                            Label("Generate New Plan", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(themeManager.current.primaryText)
                            .frame(width: 34, height: 34)
                            .background(themeManager.current.inputBackground)
                            .cornerRadius(10)
                    }
                }
            }
        }
    }
    var menuSheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 16)
            Text("Health Report")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
                .padding(.bottom, 20)
            VStack(spacing: 10) {
                menuRow(icon: "square.and.arrow.up", iconColor: .blue,
                        title: "Share Report", subtitle: "Send as text summary") {
                    showMenuSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if let r = healthReport { shareItems = [buildShareText(r)]; showShareSheet = true }
                    }
                }
                menuRow(icon: "arrow.clockwise.circle.fill", iconColor: .orange,
                        title: "Generate New Plan", subtitle: "Refresh with your latest profile") {
                    showMenuSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { generateReport(force: true) }
                }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 40)
        }
        .background(themeManager.current.cardBackground)
    }

    func menuRow(icon: String, iconColor: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(iconColor.opacity(0.12)).frame(width: 42, height: 42)
                    Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                    Text(subtitle).font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText.opacity(0.5))
            }
            .padding(14).background(themeManager.current.inputBackground).cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
    
    
    
    @MainActor
    func exportReportAsPDF(report: HealthReport) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        // 渲染整个 report 为图片
        let renderer = ImageRenderer(
            content: reportView(report: report)
                .frame(width: 390)
                .environmentObject(themeManager)
        )
        renderer.scale = UIScreen.main.scale

        guard let uiImage = renderer.uiImage else { return }

        // 图片转 PDF data
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: uiImage.size))
        let pdfData = pdfRenderer.pdfData { ctx in
            ctx.beginPage()
            uiImage.draw(at: .zero)
        }

        // 存临时文件
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthReport.pdf")
        try? pdfData.write(to: tmpURL)

        shareItems = [tmpURL]
        showShareSheet = true
    }
    func buildShareText(_ report: HealthReport) -> String {
        var t = "📊 My Health Report\nUpdated: \(report.createdAt.map { formatDate($0) } ?? "Today")\n\n"
        t += "Score: \(report.healthScore)/100 — \(report.statusBadge)\n\(report.healthSummary)\n\n"
        t += "Daily Nutrition: \(report.dailyCalories) kcal | P: \(report.proteinG)g | C: \(report.carbsG)g | F: \(report.fatG)g\n\n"
        if !report.recommendedFoods.isEmpty {
            t += "✅ Eat more: " + report.recommendedFoods.prefix(4).map { $0.food }.joined(separator: ", ") + "\n"
        }
        if !report.foodsToLimit.isEmpty {
            t += "🚫 Limit: " + report.foodsToLimit.prefix(4).joined(separator: ", ") + "\n"
        }
        t += "\n💡 \(report.lifestyleTip)\n\n— NutriSnap"
        return t
    }
    
    func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    func foodEmoji(_ food: String) -> String {
        let lower = food.lowercased()
        if lower.contains("salmon") || lower.contains("fish")         { return "🐟" }
        if lower.contains("chicken") || lower.contains("turkey")      { return "🍗" }
        if lower.contains("beef") || lower.contains("meat")           { return "🥩" }
        if lower.contains("egg")                                       { return "🥚" }
        if lower.contains("tofu") || lower.contains("soy")            { return "🫘" }
        if lower.contains("broccoli")                                  { return "🥦" }
        if lower.contains("spinach") || lower.contains("kale")        { return "🥬" }
        if lower.contains("avocado")                                   { return "🥑" }
        if lower.contains("quinoa") || lower.contains("oat")          { return "🌾" }
        if lower.contains("blueberry") || lower.contains("berry")     { return "🫐" }
        if lower.contains("apple")                                     { return "🍎" }
        if lower.contains("banana")                                    { return "🍌" }
        if lower.contains("almond") || lower.contains("nut")          { return "🥜" }
        if lower.contains("yogurt") || lower.contains("milk")         { return "🥛" }
        if lower.contains("lentil") || lower.contains("bean")         { return "🫘" }
        if lower.contains("sweet potato") || lower.contains("potato") { return "🍠" }
        if lower.contains("rice")                                      { return "🍚" }
        if lower.contains("olive")                                     { return "🫒" }
        return "🥗"
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
