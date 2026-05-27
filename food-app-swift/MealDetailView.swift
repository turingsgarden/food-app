
//  MealDetailView.swift
//  food-app-swift

import SwiftUI

// MARK: - AI Insight Models

struct NutrientInsight: Codable {
    var status: String
    var insight: String
    var suggestion: String
}

struct MealInsight: Codable {
    var mealId: String?
    var macroScore: MacroScore?
    var highlights: [IngredientHighlight]
    var warnings: [NutrientWarning]
    var tip: String
    var generatedAt: String?
    var nutrientInsights: [String: NutrientInsight]?

    enum CodingKeys: String, CodingKey {
        case mealId         = "meal_id"
        case macroScore     = "macro_score"
        case highlights, warnings, tip
        case generatedAt    = "generated_at"
        case nutrientInsights = "nutrient_insights"
    }

    func insight(for nutrientName: String) -> NutrientInsight? {
        guard let map = nutrientInsights else { return nil }
        let n = nutrientName.lowercased()
        if n.contains("calorie") || n.contains("energy") { return map["calories"] }
        if n.contains("protein")                          { return map["protein"] }
        if n.contains("fat")                              { return map["fat"] }
        if n.contains("carb")                             { return map["carbs"] }
        if n.contains("fiber") || n.contains("fibre")     { return map["fiber"] }
        if n.contains("sugar")                            { return map["sugar"] }
        if n.contains("sodium")                           { return map["sodium"] }
        return nil
    }
}

struct MacroScore: Codable {
    var rating: String
    var color: String
    var summary: String
}

struct IngredientHighlight: Codable, Identifiable {
    var id: String { ingredient }
    var ingredient: String
    var badge: String
    var note: String
}

struct NutrientWarning: Codable, Identifiable {
    var id: String { nutrient }
    var nutrient: String
    var value: String
    var note: String
}

// MARK: - Emoji Helper

func ingredientEmoji(for name: String) -> String {
    let n = name.lowercased()
    if n.contains("spinach")||n.contains("kale")||n.contains("lettuce")||n.contains("arugula") { return "🥬" }
    if n.contains("broccoli")   { return "🥦" }
    if n.contains("carrot")     { return "🥕" }
    if n.contains("tomato")     { return "🍅" }
    if n.contains("avocado")    { return "🥑" }
    if n.contains("egg")        { return "🥚" }
    if n.contains("chicken")    { return "🍗" }
    if n.contains("beef")||n.contains("steak") { return "🥩" }
    if n.contains("fish")||n.contains("salmon")||n.contains("tuna") { return "🐟" }
    if n.contains("shrimp")||n.contains("prawn") { return "🍤" }
    if n.contains("cheese")     { return "🧀" }
    if n.contains("milk")||n.contains("yogurt") { return "🥛" }
    if n.contains("butter")     { return "🧈" }
    if n.contains("olive oil")||n.contains("oil") { return "🫒" }
    if n.contains("garlic")     { return "🧄" }
    if n.contains("onion")      { return "🧅" }
    if n.contains("lemon")||n.contains("lime") { return "🍋" }
    if n.contains("mushroom")   { return "🍄" }
    if n.contains("rice")       { return "🍚" }
    if n.contains("pasta")||n.contains("noodle") { return "🍝" }
    if n.contains("bread")      { return "🍞" }
    if n.contains("potato")     { return "🥔" }
    if n.contains("pepper")||n.contains("chili") { return "🌶️" }
    if n.contains("cucumber")   { return "🥒" }
    if n.contains("nut")||n.contains("almond") { return "🥜" }
    if n.contains("salt")       { return "🧂" }
    if n.contains("sauce")||n.contains("vinegar") { return "🫙" }
    if n.contains("herb")||n.contains("basil")||n.contains("parsley") { return "🌿" }
    return "🥗"
}

// MARK: - InsightWaveBar

struct InsightWaveBar: View {
    let height: CGFloat
    let delay: Double
    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.orange)
            .frame(width: 2.5, height: animating ? max(3, height * 0.3) : height)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        animating = true
                    }
                }
            }
    }
}

// MARK: - InsightLoadingRow

struct InsightLoadingRow: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach([6, 12, 9, 15, 7].indices, id: \.self) { i in
                    InsightWaveBar(height: CGFloat([6, 12, 9, 15, 7][i]), delay: Double(i) * 0.1)
                }
            }.frame(height: 18)
            Text("AI is analysing this meal…")
                .font(.system(size: 13))
                .foregroundColor(themeManager.current.secondaryText)
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - CollapsibleInsightPanel

struct CollapsibleInsightPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    let insight: MealInsight
    @State private var isExpanded = false

    var ratingColor: Color {
        switch insight.macroScore?.color {
        case "green": return .green
        case "red":   return .red
        default:      return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach([6,12,9,15,7].indices, id: \.self) { i in
                            InsightWaveBar(height: CGFloat([6,12,9,15,7][i]), delay: Double(i)*0.1)
                        }
                    }.frame(height: 18)

                    Text("AI Analysis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(red: 0.76, green: 0.32, blue: 0.04))

                    Spacer()

                    if let score = insight.macroScore {
                        Text(score.rating)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ratingColor)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(ratingColor.opacity(0.10))
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20)
                                .stroke(ratingColor.opacity(0.25), lineWidth: 0.5))
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.76, green: 0.32, blue: 0.04).opacity(0.6))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    if let summary = insight.macroScore?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.current.secondaryText)
                            .lineSpacing(3)
                            .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 14)
                    }
                    highlightsSection
                    warningsSection
                    tipSection
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.orange.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var highlightsSection: some View {
        if !insight.highlights.isEmpty {
            Divider().background(Color.orange.opacity(0.12))
            HStack(spacing: 5) {
                Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.green)
                Text("What you ate well").font(.system(size: 11, weight: .bold)).foregroundColor(.green)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            ForEach(insight.highlights) { h in
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.10)).frame(width: 38, height: 38)
                        Text(ingredientEmoji(for: h.ingredient)).font(.system(size: 18))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(h.badge)
                                .font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.10)).cornerRadius(4)
                            Text(h.ingredient)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(themeManager.current.primaryText)
                        }
                        Text(h.note)
                            .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if !insight.warnings.isEmpty {
            Divider().background(Color.orange.opacity(0.12))
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundColor(.orange)
                Text("Watch out for").font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            ForEach(insight.warnings) { w in
                HStack(alignment: .top, spacing: 10) {
                    Text(w.value)
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.10)).cornerRadius(8).fixedSize()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.nutrient)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(themeManager.current.primaryText)
                        Text(w.note)
                            .font(.system(size: 12)).foregroundColor(themeManager.current.secondaryText)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    @ViewBuilder
    private var tipSection: some View {
        if !insight.tip.isEmpty {
            Divider().background(Color.orange.opacity(0.12))
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red:0.95,green:0.75,blue:0.20).opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red:0.95,green:0.75,blue:0.20))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT TIME")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red:0.75,green:0.55,blue:0.0)).kerning(0.4)
                    Text(insight.tip)
                        .font(.system(size: 13)).foregroundColor(themeManager.current.primaryText)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
    }
}

// MARK: - MealDetailView

struct MealDetailView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State var meal: Meal
    @State private var isEditing = false
    @State private var editedDishName: String = ""
    @State private var editedVisibleIngredients: [EditableIngredient] = []
    @State private var editedHiddenIngredients: [EditableIngredient] = []
    @State private var quantityInputs: [String: String] = [:]
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var isSaving = false
    @State private var isRecalculatingNutrition = false
    @State private var showShareSheet = false
    @State private var updatedNutritionInfo: String = ""
    @State private var showSuccessToast = false
    @State private var toastMessage = ""
    @State private var insight: MealInsight? = nil
    @State private var isLoadingInsight = false
    @State private var showTraceButton = false
    @State private var showTraceSheet = false
    @State private var traceSteps: [TraceStep] = []
    @State private var isLoadingTrace = false

    @Environment(\.dismiss) var dismiss

    var allEditedIngredients: [EditableIngredient] { editedVisibleIngredients + editedHiddenIngredients }
    var allDisplayIngredients: [EditableIngredient] {
        let visible = parseIngredientsToEditableFiltered(from: meal.image_description)
        let hidden  = parseIngredientsToEditableFiltered(from: meal.hidden_ingredients ?? "")
        return visible + hidden
    }

    var body: some View {
        ZStack {
            themeManager.current.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    heroImage
                    VStack(alignment: .leading, spacing: 20) {
                        titleAndMeta
                        BeautifulNutritionView(
                            nutritionText: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo,
                            mealInsight: insight
                        )
                        .environmentObject(themeManager)
                        ingredientsSection
                        aiInsightSection
                        traceAnalysisSection
                        actionButtons
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 50)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(themeManager.current.background)
                }
                .frame(maxWidth: .infinity)
                .background(themeManager.current.background)
            }
            .ignoresSafeArea(edges: .top)

            if showSuccessToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.white)
                        Text(toastMessage).foregroundColor(.white).font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .background(Color.green).cornerRadius(20).padding(.bottom, 20)
                    .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(), value: showSuccessToast)
            }
        }
        .preferredColorScheme(themeManager.current.colorScheme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .alert("Delete Meal", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteMeal() }
        } message: { Text("Are you sure you want to delete this meal? This action cannot be undone.") }
        .sheet(isPresented: $showShareSheet) { ShareSheet(items: [generateShareText()]) }
        .sheet(isPresented: $showTraceSheet) {
            TraceStepsSheet(steps: traceSteps)
                .environmentObject(themeManager)
        }
        .onAppear {
            loadInsight()
            checkTraceAvailability()
        }
    }

    @ViewBuilder
    var traceAnalysisSection: some View {
        if showTraceButton {
            Button(action: { showTraceSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle")
                    Text("View Analysis Steps")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(themeManager.current.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(themeManager.current.cardBackground)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(themeManager.current.cardBorder, lineWidth: 1))
            }
            .disabled(isLoadingTrace)
        }
    }

    func checkTraceAvailability() {
        guard let requestId = meal.request_id, !requestId.isEmpty else {
            showTraceButton = false
            return
        }
        isLoadingTrace = true
        HealthAPIManager.shared.fetchTrace(requestId: requestId) { result in
            isLoadingTrace = false
            switch result {
            case .success(let steps) where !steps.isEmpty:
                traceSteps = steps
                showTraceButton = true
            default:
                showTraceButton = false
            }
        }
    }

    @ViewBuilder
    var aiInsightSection: some View {
        if isLoadingInsight {
            InsightLoadingRow().environmentObject(themeManager)
        } else if let insight = insight {
            CollapsibleInsightPanel(insight: insight).environmentObject(themeManager)
        }
    }

    func loadInsight() {
        if let existing = meal.aiInsight {
            self.insight = existing
            return
        }
        guard let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/meal-insight")
        else { return }

        isLoadingInsight = true
        let ingredientStr = allDisplayIngredients
            .map { "\($0.name) | \($0.quantity) | \($0.unit)" }
            .joined(separator: "\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "meal_id":        meal._id,
            "nutrition_info": meal.nutrition_info,
            "dish_name":      meal.dish_prediction,
            "ingredients":    ingredientStr
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isLoadingInsight = false
                guard let data = data, error == nil,
                      let decoded = try? JSONDecoder().decode(MealInsight.self, from: data)
                else { return }
                withAnimation(.easeIn(duration: 0.3)) { self.insight = decoded }
            }
        }.resume()
    }

    var heroImage: some View {
        GeometryReader { geo in
            let width = geo.size.width > 0 ? geo.size.width : UIScreen.main.bounds.width
            ZStack(alignment: .bottom) {
                if let base64 = meal.image_full, let uiImage = decodeBase64ToUIImage(base64) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                        .frame(width: width, height: 300).clipped()
                } else {
                    Rectangle().fill(themeManager.current.inputBackground)
                        .frame(width: width, height: 300)
                        .overlay(Image(systemName: "photo").font(.system(size: 48))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.3)))
                }
                LinearGradient(
                    gradient: Gradient(colors: [.clear, themeManager.current.background.opacity(0.6), themeManager.current.background]),
                    startPoint: .top, endPoint: .bottom
                ).frame(width: width, height: 120)
            }
            .frame(width: width, height: 300)
            .overlay(alignment: .topTrailing) {
                Button(action: { showShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.black.opacity(0.45)))
                }
                .padding(.trailing, 16).padding(.top, 56)
            }
        }
        .frame(height: 300)
    }

    var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                TextField("Dish name", text: $editedDishName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                    .padding(14).background(themeManager.current.inputBackground).cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            } else {
                Text(meal.dish_prediction).font(.system(size: 22, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let savedAt = meal.saved_at, let date = ISO8601DateFormatter().date(from: savedAt) {
                        MetaPill(icon: "calendar", text: formatDate(date),
                                 bg: themeManager.current.inputBackground, fg: themeManager.current.secondaryText)
                    }
                    if let mealType = meal.meal_type {
                        MetaPill(icon: "fork.knife", text: mealType.capitalized,
                                 bg: themeManager.current == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                                 fg: themeManager.current.primaryText)
                    }
                    if let calories = extractCalories(from: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo) {
                        MetaPill(icon: "flame.fill", text: "\(calories) kcal", bg: Color.orange.opacity(0.12), fg: .orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var ingredientsSection: some View {
        if isEditing {
            editingIngredientsView
        } else {
            if !allDisplayIngredients.isEmpty {
                IngredientTable(ingredients: allDisplayIngredients, themeManager: themeManager)
            }
        }
    }

    var editingIngredientsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !editedVisibleIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("VISIBLE").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.7)).kerning(2)
                    ForEach(editedVisibleIngredients, id: \.id) { ing in ingredientInputRow(ing: ing) }
                }
            }
            if !editedHiddenIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HIDDEN").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.5)).kerning(2)
                    ForEach(editedHiddenIngredients, id: \.id) { ing in ingredientInputRow(ing: ing) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption).foregroundColor(.orange.opacity(0.8))
                Text("Only quantities can be edited").font(.caption).foregroundColor(themeManager.current.secondaryText)
                Spacer()
            }
        }
        .padding(16).background(themeManager.current.cardBackground).cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func ingredientInputRow(ing: EditableIngredient) -> some View {
        HStack(spacing: 10) {
            Text(ing.name).font(.system(size: 14, weight: .medium)).foregroundColor(themeManager.current.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(themeManager.current.inputBackground).cornerRadius(10)
            TextField("0", text: Binding(
                get: { quantityInputs[ing.id] ?? ing.quantity },
                set: { quantityInputs[ing.id] = $0 }
            ))
            .font(.system(size: 14)).foregroundColor(themeManager.current.primaryText)
            .multilineTextAlignment(.center).frame(width: 60)
            .padding(.horizontal, 8).padding(.vertical, 10)
            .background(Color.orange.opacity(0.08)).cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
            .keyboardType(.decimalPad)
            Text(displayUnit(for: ing)).font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
                .frame(width: 48).padding(.horizontal, 6).padding(.vertical, 10)
                .background(themeManager.current.inputBackground).cornerRadius(10)
        }
    }

    @ViewBuilder
    var actionButtons: some View {
        if isEditing {
            HStack(spacing: 12) {
                Button(action: cancelEditing) {
                    Text("Cancel").font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(themeManager.current.inputBackground).cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
                }.disabled(isSaving || isRecalculatingNutrition)
                Button(action: saveChanges) {
                    HStack(spacing: 6) {
                        if isSaving || isRecalculatingNutrition {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.85)
                            Text(isRecalculatingNutrition ? "Calculating..." : "Saving...")
                        } else {
                            Image(systemName: "checkmark"); Text("Save")
                        }
                    }
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.green).cornerRadius(16)
                }.disabled(isSaving || isRecalculatingNutrition)
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: startEditing) {
                        HStack(spacing: 6) { Image(systemName: "sparkles"); Text("Fix Issue") }
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(themeManager.current.primaryText)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(themeManager.current.cardBackground).cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1.5))
                    }
                    Button(action: { dismiss() }) {
                        Text("Done").font(.system(size: 15, weight: .bold))
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(themeManager.current == .dark ? Color.white : Color.black).cornerRadius(16)
                    }
                }
                Button(action: { showDeleteAlert = true }) {
                    HStack(spacing: 6) {
                        if isDeleting {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .red)).scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(isDeleting ? "Deleting..." : "Delete Meal")
                    }
                    .font(.system(size: 14, weight: .medium)).foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }.disabled(isDeleting)
            }
        }
    }

    func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
    }

    func startEditing() {
        isEditing = true
        editedDishName = meal.dish_prediction
        editedVisibleIngredients = parseIngredientsToEditableFiltered(from: meal.image_description)
        editedHiddenIngredients  = parseIngredientsToEditableFiltered(from: meal.hidden_ingredients ?? "")
        updatedNutritionInfo = meal.nutrition_info
        quantityInputs = [:]
        for ing in editedVisibleIngredients + editedHiddenIngredients { quantityInputs[ing.id] = ing.quantity }
    }

    func cancelEditing() {
        isEditing = false; editedDishName = ""
        editedVisibleIngredients = []; editedHiddenIngredients = []; quantityInputs = [:]; updatedNutritionInfo = ""
    }

    func saveChanges() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        executeSave()
    }

    private func executeSave() {
        let ingredientsList = (editedVisibleIngredients + editedHiddenIngredients).map { ing in
            "\(ing.name) | \(quantityInputs[ing.id] ?? ing.quantity) | \(displayUnit(for: ing))"
        }.joined(separator: "\n")

        meal.dish_prediction = editedDishName
        meal.image_description = editedVisibleIngredients.map { ing in
            "\(ing.name) | \(quantityInputs[ing.id] ?? ing.quantity) | \(displayUnit(for: ing)) | User edited"
        }.joined(separator: "\n")
        let hiddenStr = editedHiddenIngredients.map { ing in
            "\(ing.name) | \(quantityInputs[ing.id] ?? ing.quantity) | \(displayUnit(for: ing)) | User edited"
        }.joined(separator: "\n")
        meal.hidden_ingredients = hiddenStr

        let mealDataForUpdate: [String: Any] = [
            "meal_id": meal._id, "dish_prediction": meal.dish_prediction,
            "image_description": meal.image_description, "hidden_ingredients": hiddenStr,
            "nutrition_info": meal.nutrition_info, "meal_type": meal.meal_type ?? "LUNCH"
        ]
        isEditing = false; dismiss()
        RecalculationManager.shared.startRecalculation(
            mealId: meal._id, ingredients: ingredientsList, mealData: mealDataForUpdate
        ) { _ in
            NotificationCenter.default.post(name: Notification.Name("MealUpdated"), object: nil)
            NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)
        }
    }

    func deleteMeal() {
        isDeleting = true
        NetworkManager.shared.deleteMeal(mealId: meal._id) { success in
            self.isDeleting = false
            if success {
                NotificationCenter.default.post(name: Notification.Name("MealDeleted"), object: nil)
                NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)
                self.dismiss()
            }
        }
    }

    func decodeBase64ToUIImage(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data) else { return nil }
        return image
    }

    func filteredIngredientLines(from text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.lowercased() != "ingredient | quantity number | unit" else { return nil }
            let parts = t.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count >= 1 && !parts[0].isEmpty ? String(t) : nil
        }
    }

    func parseIngredientsToEditableFiltered(from text: String) -> [EditableIngredient] {
        filteredIngredientLines(from: text).compactMap { line in
            let clean = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
            let parts = clean.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { return nil }
            let name = parts[0]; let quantity = parts[1]
            var unit = ""
            for i in 2..<parts.count {
                let p = parts[i]
                if p.lowercased() == "user edited" || Double(p) != nil { continue }
                unit = p; break
            }
            if unit.isEmpty { unit = guessIngredientUnit(for: name) }
            guard !name.isEmpty else { return nil }
            return EditableIngredient(id: name, name: name, quantity: quantity, unit: unit)
        }
    }

    func guessIngredientUnit(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("oil")||n.contains("sauce")||n.contains("milk")||n.contains("water")||n.contains("vinegar") { return "ml" }
        if n.contains("salt")||n.contains("pepper")||n.contains("spice")||n.contains("powder") { return "tsp" }
        if n.contains("bread")||n.contains("egg")||n.contains("slice")||n.contains("piece") { return "pcs" }
        return "g"
    }

    func extractCalories(from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calories") { return Int(parts[1]) }
        }
        return nil
    }

    func displayUnit(for ing: EditableIngredient) -> String {
        let u = ing.unit.trimmingCharacters(in: .whitespaces)
        if Double(u) != nil || u.isEmpty { return guessUnit(for: ing.name) }
        return u
    }

    func guessUnit(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("bread")||n.contains("egg")||n.contains("slice") { return "pcs" }
        if n.contains("salt")||n.contains("pepper")||n.contains("spice") { return "tsp" }
        if n.contains("oil")||n.contains("sauce")||n.contains("milk") { return "ml" }
        return "g"
    }

    func generateShareText() -> String {
        var text = "Check out my meal: \(meal.dish_prediction)\n\nIngredients:\n"
        for ing in allDisplayIngredients { text += "• \(ing.name) – \(ing.quantity) \(ing.unit)\n" }
        if let calories = extractCalories(from: meal.nutrition_info) { text += "\nCalories: \(calories) kcal\n" }
        text += "\nTracked with NutriSnap 🎯"
        return text
    }
}

// MARK: - IngredientTable

struct IngredientTable: View {
    let ingredients: [EditableIngredient]
    let themeManager: ThemeManager
    private let initialRows = 6
    @State private var showAll = false
    private var displayed: [EditableIngredient] { showAll ? ingredients : Array(ingredients.prefix(initialRows)) }
    private var hiddenCount: Int { max(0, ingredients.count - initialRows) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(themeManager.current.primaryText.opacity(0.25))
                    .frame(width: 3, height: 16).cornerRadius(2).padding(.trailing, 8)
                Text("INGREDIENTS").font(.system(size: 11, weight: .bold))
                    .foregroundColor(themeManager.current.secondaryText).tracking(1.2)
                Spacer()
                Text("\(ingredients.count) items").font(.system(size: 12))
                    .foregroundColor(themeManager.current.secondaryText)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            HStack(spacing: 0) {
                Color.clear.frame(width: 36).padding(.leading, 14)
                Text("NAME").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText.opacity(0.55)).tracking(0.8)
                Spacer()
                Text("QTY").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText.opacity(0.55)).tracking(0.8)
                    .frame(width: 56, alignment: .trailing)
                Text("UNIT").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText.opacity(0.55)).tracking(0.8)
                    .frame(width: 44, alignment: .trailing).padding(.trailing, 14)
            }.padding(.bottom, 6)

            Divider().background(themeManager.current.cardBorder)

            ForEach(Array(displayed.enumerated()), id: \.element.id) { idx, ing in
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("\(idx + 1)").font(.system(size: 12))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.4))
                            .frame(width: 22, alignment: .leading).padding(.leading, 14)
                        Text(ing.name).font(.system(size: 14, weight: .medium))
                            .foregroundColor(themeManager.current.primaryText).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
                        Text(ing.quantity).font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                            .frame(width: 56, alignment: .trailing)
                        Text(ing.unit.isEmpty ? "—" : ing.unit).font(.system(size: 13))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.5))
                            .frame(width: 44, alignment: .trailing).padding(.trailing, 14)
                    }.frame(height: 46)
                    let isLast = idx == displayed.count - 1
                    if !isLast || (isLast && ingredients.count > initialRows) {
                        Divider().background(themeManager.current.cardBorder.opacity(0.6)).padding(.leading, 36)
                    }
                }
            }

            if ingredients.count > initialRows {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showAll.toggle() }
                }) {
                    HStack(spacing: 5) {
                        Text(showAll ? "Show less" : "Show \(hiddenCount) more")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(themeManager.current.secondaryText)
                        Image(systemName: showAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.7))
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.plain)
            }
        }
        .background(themeManager.current.cardBackground).cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }
}

// MARK: - Supporting Components

struct MetaPill: View {
    let icon: String; let text: String; let bg: Color; let fg: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(fg).padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 20).fill(bg))
    }
}

struct ActionButton: View {
    let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundColor(.white)
                .frame(width: 40, height: 40).background(Circle().fill(Color.black.opacity(0.45)))
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Trace Steps Sheet

struct TraceStepsSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    let steps: [TraceStep]

    var body: some View {
        NavigationStack {
            List(steps) { step in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(step.name.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(step.duration_ms) ms")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(step.status == "ok" ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(step.status.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                    if let summary = step.output_summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.current.secondaryText)
                            .lineLimit(3)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(themeManager.current.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(themeManager.current.background)
            .navigationTitle("Analysis Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(themeManager.current.colorScheme)
    }
}
