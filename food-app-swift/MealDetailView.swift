 
import SwiftUI

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
    @Environment(\.dismiss) var dismiss

    var allEditedIngredients: [EditableIngredient] { editedVisibleIngredients + editedHiddenIngredients }
    var allDisplayIngredients: [EditableIngredient] {
        let visible = parseIngredientsToEditableFiltered(from: meal.image_description)
        let hidden = parseIngredientsToEditableFiltered(from: meal.hidden_ingredients ?? "")
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

            // Toast
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
    }

    // MARK: - Hero Image（改：渐变底部改为 theme.background）

    var heroImage: some View {
        GeometryReader { geo in
            let width = geo.size.width > 0 ? geo.size.width : UIScreen.main.bounds.width
            ZStack(alignment: .bottom) {
                if let base64 = meal.image_full, let uiImage = decodeBase64ToUIImage(base64) {
                    Image(uiImage: uiImage)
                        .resizable().scaledToFill()
                        .frame(width: width, height: 300).clipped()
                } else {
                    Rectangle()
                        .fill(themeManager.current.inputBackground)
                        .frame(width: width, height: 300)
                        .overlay(Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(themeManager.current.secondaryText.opacity(0.3)))
                }
                // 底部渐变：黑→theme背景色（避免 dark/light 不匹配）
                LinearGradient(
                    gradient: Gradient(colors: [.clear, themeManager.current.background.opacity(0.6), themeManager.current.background]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width, height: 120)
            }
            .frame(width: width, height: 300)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    Button(action: { showShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.45)))
                    }
                }
                .padding(.trailing, 16).padding(.top, 56)
            }
        }
        .frame(height: 300)
    }

    // MARK: - Title & Meta（Cal AI 风格）

    var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                TextField("Dish name", text: $editedDishName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                    .padding(14)
                    .background(themeManager.current.inputBackground)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1))
            } else {
                Text(meal.dish_prediction)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
            }

            // Meta 胶囊行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let savedAt = meal.saved_at, let date = ISO8601DateFormatter().date(from: savedAt) {
                        MetaPill(icon: "calendar", text: formatDate(date),
                                 bg: themeManager.current.inputBackground,
                                 fg: themeManager.current.secondaryText)
                    }
                    if let mealType = meal.meal_type {
                        MetaPill(icon: "fork.knife", text: mealType.capitalized,
                                 bg: themeManager.current == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06),
                                 fg: themeManager.current.primaryText)
                    }
                    if let calories = extractCalories(from: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo) {
                        MetaPill(icon: "flame.fill", text: "\(calories) kcal",
                                 bg: Color.orange.opacity(0.12),
                                 fg: .orange)
                    }
                }
            }
        }
    }

    // MARK: - Ingredients Section（保持原逻辑，改样式）

    @ViewBuilder
    var ingredientsSection: some View {
        if isEditing {
            editingIngredientsView
        } else {
            if !allDisplayIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ingredients")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                    VStack(spacing: 10) {
                        ForEach(allDisplayIngredients, id: \.id) { ing in
                            HStack {
                                Text(ing.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(themeManager.current.primaryText)
                                Spacer()
                                Text(ing.quantity + (!ing.unit.isEmpty ? " " + ing.unit : ""))
                                    .font(.system(size: 13))
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(themeManager.current.cardBackground)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(themeManager.current.cardBorder, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    var editingIngredientsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !editedVisibleIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("VISIBLE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.7)).kerning(2)
                    ForEach(editedVisibleIngredients, id: \.id) { ing in ingredientInputRow(ing: ing) }
                }
            }
            if !editedHiddenIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HIDDEN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.5)).kerning(2)
                    ForEach(editedHiddenIngredients, id: \.id) { ing in ingredientInputRow(ing: ing) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption).foregroundColor(.orange.opacity(0.8))
                Text("Only quantities can be edited").font(.caption)
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func ingredientInputRow(ing: EditableIngredient) -> some View {
        HStack(spacing: 10) {
            Text(ing.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.current.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(themeManager.current.inputBackground)
                .cornerRadius(10)

            TextField("0", text: Binding(
                get: { quantityInputs[ing.id] ?? ing.quantity },
                set: { quantityInputs[ing.id] = $0 }
            ))
            .font(.system(size: 14)).foregroundColor(themeManager.current.primaryText)
            .multilineTextAlignment(.center).frame(width: 60)
            .padding(.horizontal, 8).padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25), lineWidth: 1))
            .keyboardType(.decimalPad)

            Text(displayUnit(for: ing))
                .font(.system(size: 13)).foregroundColor(themeManager.current.secondaryText)
                .frame(width: 48).padding(.horizontal, 6).padding(.vertical, 10)
                .background(themeManager.current.inputBackground).cornerRadius(10)
        }
    }

    // MARK: - Action Buttons（Cal AI 风格：Fix Issue + Done）

    @ViewBuilder
    var actionButtons: some View {
        if isEditing {
            HStack(spacing: 12) {
                Button(action: cancelEditing) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
                }
                .disabled(isSaving || isRecalculatingNutrition)

                Button(action: saveChanges) {
                    HStack(spacing: 6) {
                        if isSaving || isRecalculatingNutrition {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.85)
                            Text(isRecalculatingNutrition ? "Calculating..." : "Saving...")
                        } else {
                            Image(systemName: "checkmark")
                            Text("Save")
                        }
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.green).cornerRadius(16)
                }
                .disabled(isSaving || isRecalculatingNutrition)
            }
        } else {
            // Cal AI 风格：Fix Issue（左，outlined）+ Done / Delete（右，filled）
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    // Fix Issue = Edit 功能
                    Button(action: startEditing) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Fix Issue")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(themeManager.current.cardBackground)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .stroke(themeManager.current.cardBorder, lineWidth: 1.5))
                    }

                    // Done 按钮
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(themeManager.current == .dark ? Color.white : Color.black)
                            .cornerRadius(16)
                    }
                }

                // 删除按钮（单独一行，弱化）
                Button(action: { showDeleteAlert = true }) {
                    HStack(spacing: 6) {
                        if isDeleting {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .red)).scaleEffect(0.8)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(isDeleting ? "Deleting..." : "Delete Meal")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .disabled(isDeleting)
            }
        }
    }

    // MARK: - 原有逻辑（完整保留）

    func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
    }

    func startEditing() {
        isEditing = true
        editedDishName = meal.dish_prediction
        editedVisibleIngredients = parseIngredientsToEditableFiltered(from: meal.image_description)
        editedHiddenIngredients = parseIngredientsToEditableFiltered(from: meal.hidden_ingredients ?? "")
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
            let qty = quantityInputs[ing.id] ?? ing.quantity
            let unit = displayUnit(for: ing)
            return "\(ing.name) | \(qty) | \(unit)"
        }.joined(separator: "\n")

        meal.dish_prediction = editedDishName
        meal.image_description = editedVisibleIngredients.map { ing in
            let qty = quantityInputs[ing.id] ?? ing.quantity
            let unit = displayUnit(for: ing)
            return "\(ing.name) | \(qty) | \(unit) | User edited"
        }.joined(separator: "\n")

        let hiddenStr = editedHiddenIngredients.map { ing in
            let qty = quantityInputs[ing.id] ?? ing.quantity
            let unit = displayUnit(for: ing)
            return "\(ing.name) | \(qty) | \(unit) | User edited"
        }.joined(separator: "\n")
        meal.hidden_ingredients = hiddenStr

        let mealDataForUpdate: [String: Any] = [
            "meal_id": meal._id,
            "dish_prediction": meal.dish_prediction,
            "image_description": meal.image_description,
            "hidden_ingredients": hiddenStr,
            "nutrition_info": meal.nutrition_info,
            "meal_type": meal.meal_type ?? "LUNCH"
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
                if p.lowercased() == "user edited" { continue }
                if Double(p) != nil { continue }  // ✅ 跳过数字字段
                unit = p; break
            }
            // ✅ 如果 unit 仍然为空，推断单位
            if unit.isEmpty { unit = guessIngredientUnit(for: name) }
            guard !name.isEmpty else { return nil }
            return EditableIngredient(id: name, name: name, quantity: quantity, unit: unit)
        }
    }

    func guessIngredientUnit(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("oil") || n.contains("sauce") || n.contains("milk") || n.contains("water") || n.contains("vinegar") { return "ml" }
        if n.contains("salt") || n.contains("pepper") || n.contains("spice") || n.contains("powder") { return "tsp" }
        if n.contains("bread") || n.contains("egg") || n.contains("slice") || n.contains("piece") { return "pcs" }
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
        if n.contains("bread") || n.contains("egg") || n.contains("slice") { return "pcs" }
        if n.contains("salt") || n.contains("pepper") || n.contains("spice") { return "tsp" }
        if n.contains("oil") || n.contains("sauce") || n.contains("milk") { return "ml" }
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

// MARK: - 新组件

// Meta 胶囊（新版 InfoPill）
struct MetaPill: View {
    let icon: String; let text: String; let bg: Color; let fg: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(fg)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 20).fill(bg))
    }
}

// 保留原有 ActionButton / InfoPill / ShareSheet
struct ActionButton: View {
    let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.black.opacity(0.45)))
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
        .foregroundColor(color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.12))
            .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1)))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
