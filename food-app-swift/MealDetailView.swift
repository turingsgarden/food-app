//
//  MealDetailView.swift
//  food-app-swift
//
//  Created by Helen Tu on 3/17/26.
//
//
//  MealDetailView.swift
//  food-app-swift — v2: AI Meal Insight card
//
import SwiftUI

// MARK: - AI Insight Models

struct MealInsight: Codable {
    var mealId: String?
    var macroScore: MacroScore?
    var highlights: [IngredientHighlight]
    var warnings: [NutrientWarning]
    var tip: String
    var generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case macroScore = "macro_score"
        case highlights, warnings, tip
        case generatedAt = "generated_at"
    }
}

struct MacroScore: Codable {
    var rating: String   // "Balanced" / "High Sodium" / "Good" etc.
    var color: String    // "green" / "orange" / "red"
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

// MARK: - AI Insight Card View

struct MealInsightCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let insight: MealInsight

    var ratingColor: Color {
        switch insight.macroScore?.color {
        case "green":  return .green
        case "orange": return .orange
        case "red":    return .red
        default:       return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 8) {
                // Animated waveform icon
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach([6, 12, 9, 15, 7].indices, id: \.self) { i in
                        InsightWaveBar(height: CGFloat([6, 12, 9, 15, 7][i]),
                                       delay: Double(i) * 0.1)
                    }
                }
                .frame(height: 18)

                Text("AI Analysis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.76, green: 0.32, blue: 0.04))

                Spacer()

                // Macro score badge
                if let score = insight.macroScore {
                    Text(score.rating)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ratingColor)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(ratingColor.opacity(0.10))
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20)
                            .stroke(ratingColor.opacity(0.25), lineWidth: 1))
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            // ── Macro summary ────────────────────────────────────────────────
            if let summary = insight.macroScore?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.current.secondaryText)
                    .lineSpacing(3)
                    .padding(.horizontal, 14).padding(.bottom, 12)
            }

            // ── Highlights ───────────────────────────────────────────────────
            if !insight.highlights.isEmpty {
                Divider().background(themeManager.current.cardBorder)
                VStack(alignment: .leading, spacing: 8) {
                    Label("What you ate well", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.bottom, 2)

                    ForEach(insight.highlights) { h in
                        HStack(alignment: .top, spacing: 10) {
                            // Green badge
                            Text(h.badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.green.opacity(0.10))
                                .cornerRadius(8)
                                .fixedSize()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.ingredient)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text(h.note)
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.current.secondaryText)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }

            // ── Warnings ─────────────────────────────────────────────────────
            if !insight.warnings.isEmpty {
                Divider().background(themeManager.current.cardBorder)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Watch out for", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.bottom, 2)

                    ForEach(insight.warnings) { w in
                        HStack(alignment: .top, spacing: 10) {
                            // Value pill
                            Text(w.value)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.10))
                                .cornerRadius(8)
                                .fixedSize()

                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.nutrient)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text(w.note)
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.current.secondaryText)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }

            // ── Personalised tip ─────────────────────────────────────────────
            if !insight.tip.isEmpty {
                Divider().background(themeManager.current.cardBorder)
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red:0.95,green:0.75,blue:0.20).opacity(0.15))
                            .frame(width: 30, height: 30)
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red:0.95,green:0.75,blue:0.20))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next time")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red:0.75,green:0.55,blue:0.0))
                            .textCase(.uppercase).tracking(0.4)
                        Text(insight.tip)
                            .font(.system(size: 13))
                            .foregroundColor(themeManager.current.primaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .background(Color.orange.opacity(0.04))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.orange.opacity(0.18), lineWidth: 1))
    }
}

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
                    withAnimation(Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        animating = true
                    }
                }
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

    // AI insight
    @State private var insight: MealInsight? = nil
    @State private var isLoadingInsight = false

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
                        BeautifulNutritionView(nutritionText: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo)
                            .environmentObject(themeManager)

                        // AI Insight card — shown between nutrition and ingredients
                        insightSection

                        ingredientsSection
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
        .onAppear { loadInsight() }
    }

    // MARK: - AI Insight Section

    @ViewBuilder
    var insightSection: some View {
        if isLoadingInsight {
            // Skeleton loader
            HStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach([6, 12, 9, 15, 7].indices, id: \.self) { i in
                        InsightWaveBar(height: CGFloat([6, 12, 9, 15, 7][i]),
                                       delay: Double(i) * 0.1)
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
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1))
        } else if let insight = insight {
            MealInsightCard(insight: insight).environmentObject(themeManager)
        }
        // If nil and not loading, show nothing (e.g. network failed silently)
    }

    // MARK: - Load Insight

    func loadInsight() {
        // 1. Check if insight already saved in meal object
        if let existing = meal.aiInsight {
            self.insight = existing
            return
        }
        // 2. Otherwise fetch/generate from backend
        guard let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/meal-insight")
        else { return }

        isLoadingInsight = true

        // Build ingredients string
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
                withAnimation(.easeIn(duration: 0.3)) {
                    self.insight = decoded
                }
            }
        }.resume()
    }

    // MARK: - Hero Image

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

    // MARK: - Title & Meta

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
                        MetaPill(icon: "calendar", text: formatDate(date), bg: themeManager.current.inputBackground, fg: themeManager.current.secondaryText)
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

    // MARK: - Ingredients Section

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

    // MARK: - Editing View

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

    // MARK: - Action Buttons

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
                        } else { Image(systemName: "checkmark"); Text("Save") }
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
                        if isDeleting { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .red)).scaleEffect(0.8) }
                        else { Image(systemName: "trash") }
                        Text(isDeleting ? "Deleting..." : "Delete Meal")
                    }
                    .font(.system(size: 14, weight: .medium)).foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }.disabled(isDeleting)
            }
        }
    }

    // MARK: - Helpers

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
                Button(action: { withAnimation(.spring(response:0.3,dampingFraction:0.8)) { showAll.toggle() } }) {
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

struct InfoPill: View {
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.caption).fontWeight(.medium)
        }
        .foregroundColor(color).padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12))
            .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1)))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
