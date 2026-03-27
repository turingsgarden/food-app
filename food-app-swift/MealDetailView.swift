import SwiftUI

struct MealDetailView: View {
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

    var allEditedIngredients: [EditableIngredient] {
        editedVisibleIngredients + editedHiddenIngredients
    }

    var allDisplayIngredients: [EditableIngredient] {
        let visible = parseIngredientsToEditableFiltered(from: meal.image_description)
        let hidden = parseIngredientsToEditableFiltered(from: meal.hidden_ingredients ?? "")
        return visible + hidden
    }

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.black.opacity(0.95), Color(red: 0.1, green: 0.1, blue: 0.15)]),
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroImage
                    VStack(alignment: .leading, spacing: 24) {
                        titleAndMeta
                        BeautifulNutritionView(nutritionText: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo)
                        ingredientsSection
                        actionButtons
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(edges: .top)

            if showSuccessToast {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.white)
                        Text(toastMessage).foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.green).cornerRadius(10).padding()
                    .transition(.move(edge: .bottom))
                }
                .animation(.spring(), value: showSuccessToast)
            }
        }
        .preferredColorScheme(.dark)
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
        } message: {
            Text("Are you sure you want to delete this meal? This action cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareText()])
        }
    }

    // MARK: - Hero Image

    var heroImage: some View {
        GeometryReader { geo in
            let width = geo.size.width > 0 ? geo.size.width : UIScreen.main.bounds.width
            ZStack(alignment: .bottom) {
                if let base64 = meal.image_full, let uiImage = decodeBase64ToUIImage(base64) {
                    Image(uiImage: uiImage)
                        .resizable().scaledToFill()
                        .frame(width: width, height: 350).clipped()
                } else {
                    Rectangle()
                        .fill(LinearGradient(gradient: Gradient(colors: [.orange.opacity(0.4), .orange.opacity(0.2)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: width, height: 350)
                        .overlay(Image(systemName: "photo").font(.system(size: 60)).foregroundColor(.white.opacity(0.5)))
                }
                LinearGradient(gradient: Gradient(colors: [.clear, .black.opacity(0.7), .black.opacity(0.9)]), startPoint: .top, endPoint: .bottom)
                    .frame(width: width, height: 150)
            }
            .frame(width: width, height: 350)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    ActionButton(icon: "square.and.arrow.up") { showShareSheet = true }
                    ActionButton(icon: "heart") {}
                }
                .padding().padding(.top, 50)
            }
        }
        .frame(height: 350)
    }

    // MARK: - Title and Meta

    var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                TextField("Dish name", text: $editedDishName)
                    .font(.title2.bold()).foregroundColor(.white).padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1)))
            } else {
                Text(meal.dish_prediction).font(.title2.bold()).foregroundColor(.white)
            }
            HStack(spacing: 12) {
                if let savedAt = meal.saved_at, let date = ISO8601DateFormatter().date(from: savedAt) {
                    InfoPill(icon: "calendar", text: formatDate(date), color: .blue)
                }
                if let mealType = meal.meal_type {
                    InfoPill(icon: "fork.knife", text: mealType, color: .purple)
                }
                if let calories = extractCalories(from: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo) {
                    InfoPill(icon: "flame.fill", text: "\(calories) kcal", color: .orange)
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
                IngredientTableView(ingredients: allDisplayIngredients)
            }
        }
    }

    // MARK: - Editing Ingredients View
    // ✅ TextField 直接绑定 quantityInputs 字典，完全绕开子 view binding 问题

    var editingIngredientsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !editedVisibleIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("VISIBLE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7)).kerning(2)
                    ForEach(editedVisibleIngredients, id: \.id) { ing in
                        ingredientInputRow(ing: ing)
                    }
                }
            }
            if !editedHiddenIngredients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("HIDDEN")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.pink.opacity(0.7)).kerning(2)
                    ForEach(editedHiddenIngredients, id: \.id) { ing in
                        ingredientInputRow(ing: ing)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption).foregroundColor(.orange.opacity(0.8))
                Text("Only quantities can be edited").font(.caption).foregroundColor(.gray)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07), lineWidth: 1)))
    }

    // ✅ 每行的 UI，TextField 直接读写 quantityInputs[ing.id]
    func ingredientInputRow(ing: EditableIngredient) -> some View {
        HStack(spacing: 12) {
            // Name (read-only)
            HStack {
                Text(ing.name)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            )

            // ✅ 直接绑定 quantityInputs 字典，没有任何子 view 传递
            TextField("0", text: Binding(
                get: { quantityInputs[ing.id] ?? ing.quantity },
                set: { quantityInputs[ing.id] = $0 }
            ))
            .font(.subheadline)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .frame(width: 70)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            )
            .keyboardType(.decimalPad)

            // Unit (read-only)
            Text(displayUnit(for: ing))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 60)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                )
        }
    }

    func displayUnit(for ing: EditableIngredient) -> String {
        let u = ing.unit.trimmingCharacters(in: .whitespaces)
        if Double(u) != nil || u.isEmpty { return guessUnit(for: ing.name) }
        return u
    }

    func guessUnit(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("bread") || n.contains("egg") || n.contains("slice") { return "pcs" }
        if n.contains("salt") || n.contains("pepper") || n.contains("spice") || n.contains("powder") { return "tsp" }
        if n.contains("oil") || n.contains("sauce") || n.contains("milk") { return "ml" }
        return "g"
    }

    // MARK: - Action Buttons

    @ViewBuilder
    var actionButtons: some View {
        if isEditing {
            HStack(spacing: 12) {
                Button(action: cancelEditing) {
                    Text("Cancel").fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1)))
                }
                .disabled(isSaving || isRecalculatingNutrition)

                Button(action: saveChanges) {
                    HStack {
                        if isSaving || isRecalculatingNutrition {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.9)
                            Text(isRecalculatingNutrition ? "Calculating..." : "Saving...")
                        } else {
                            Image(systemName: "checkmark")
                            Text("Save")
                        }
                    }
                    .fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(LinearGradient(gradient: Gradient(colors: [.green, .green.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(12)
                }
                .disabled(isSaving || isRecalculatingNutrition)
            }
        } else {
            HStack(spacing: 12) {
                Button(action: startEditing) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(12)
                }
                Button(action: { showDeleteAlert = true }) {
                    HStack {
                        if isDeleting {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                    }
                    .fontWeight(.semibold).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(LinearGradient(gradient: Gradient(colors: [.red, .red.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .cornerRadius(12)
                }
                .disabled(isDeleting)
            }
        }
    }

    // MARK: - Logic

    func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
    }

    func startEditing() {
        print("🔍 RAW image_description:\n\(meal.image_description)")
        print("🔍 RAW hidden:\n\(meal.hidden_ingredients ?? "nil")")
        isEditing = true
        editedDishName = meal.dish_prediction
        editedVisibleIngredients = parseIngredientsToEditableFiltered(from: meal.image_description)
        editedHiddenIngredients = parseIngredientsToEditableFiltered(from: meal.hidden_ingredients ?? "")
        updatedNutritionInfo = meal.nutrition_info
        // ✅ 初始化 quantityInputs
        quantityInputs = [:]
        for ing in editedVisibleIngredients + editedHiddenIngredients {
            quantityInputs[ing.id] = ing.quantity
        }
    }

    func cancelEditing() {
        isEditing = false
        editedDishName = ""
        editedVisibleIngredients = []
        editedHiddenIngredients = []
        quantityInputs = [:]
        updatedNutritionInfo = ""
    }

    func saveChanges() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        executeSave()
    }

    private func executeSave() {
        let ingredientsList = (editedVisibleIngredients + editedHiddenIngredients)
            .map { ing in
                let qty = quantityInputs[ing.id] ?? ing.quantity
                let unit = displayUnit(for: ing)  // ✅
                return "\(ing.name) | \(qty) | \(unit)"
            }
            .joined(separator: "\n")

        print("💾 saveChanges called")
        print("📝 ingredientsList: \(ingredientsList)")
        print("🥘 mealId: \(meal._id)")

        meal.dish_prediction = editedDishName
        // visible — 用 displayUnit 函数确保存的是真实单位
        meal.image_description = editedVisibleIngredients
            .map { ing in
                let qty = quantityInputs[ing.id] ?? ing.quantity
                let unit = displayUnit(for: ing)  // ✅ 用已有的 displayUnit 函数
                return "\(ing.name) | \(qty) | \(unit) | User edited"
            }
            .joined(separator: "\n")

        let hiddenStr = editedHiddenIngredients
            .map { ing in
                let qty = quantityInputs[ing.id] ?? ing.quantity
                let unit = displayUnit(for: ing)  // ✅ 同上
                return "\(ing.name) | \(qty) | \(unit) | User edited"
            }
            .joined(separator: "\n")
        let mealDataForUpdate: [String: Any] = [
            "meal_id": meal._id,
            "dish_prediction": meal.dish_prediction,
            "image_description": meal.image_description,
            "hidden_ingredients": hiddenStr,
            "nutrition_info": meal.nutrition_info,
            "meal_type": meal.meal_type ?? "LUNCH"
        ]

        isEditing = false
        dismiss()

        RecalculationManager.shared.startRecalculation(
            mealId: meal._id,
            ingredients: ingredientsList,
            mealData: mealDataForUpdate
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

            let name = parts[0]
            let quantity = parts[1]

            // ✅ 找第一个不是数字、不是"User edited"的部分作为unit
            var unit = ""
            for i in 2..<parts.count {
                let p = parts[i]
                if p.lowercased() == "user edited" { continue }
                if Double(p) != nil { continue }  // 跳过纯数字
                unit = p
                break
            }

            guard !name.isEmpty else { return nil }
            return EditableIngredient(id: name, name: name, quantity: quantity, unit: unit)
        }
    }

    func extractCalories(from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calories") { return Int(parts[1]) }
        }
        return nil
    }

    func generateShareText() -> String {
        var text = "Check out my meal: \(meal.dish_prediction)\n\nIngredients:\n"
        for ing in allDisplayIngredients {
            text += "• \(ing.name) – \(ing.quantity) \(ing.unit)\n"
        }
        if let calories = extractCalories(from: meal.nutrition_info) { text += "\nCalories: \(calories) kcal\n" }
        text += "\nTracked with NutriSnap 🎯"
        return text
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.5)).blur(radius: 10))
        }
    }
}

struct InfoPill: View {
    let icon: String
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.caption).fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.2)).overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1)))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
