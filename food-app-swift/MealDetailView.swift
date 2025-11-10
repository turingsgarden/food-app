import SwiftUI

struct MealDetailView: View {
    @State var meal: Meal
    @State private var isEditing = false
    @State private var editedDishName: String = ""
    @State private var editedVisibleIngredients: [EditableIngredient] = []
    @State private var editedHiddenIngredients: [EditableIngredient] = []
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var isSaving = false
    @State private var isRecalculatingNutrition = false
    @State private var showShareSheet = false
    @State private var updatedNutritionInfo: String = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black,
                    Color.black.opacity(0.95),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Image Section
                    ZStack(alignment: .bottom) {
                        if let base64 = meal.image_full, let uiImage = decodeBase64ToUIImage(base64) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 350)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.orange.opacity(0.4), .orange.opacity(0.2)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 350)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                        
                        // Gradient overlay
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.black.opacity(0.7),
                                Color.black.opacity(0.9)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 150)
                    }
                    .overlay(alignment: .topTrailing) {
                        // Action buttons
                        HStack(spacing: 12) {
                            ActionButton(icon: "square.and.arrow.up") {
                                showShareSheet = true
                            }
                            
                            ActionButton(icon: "heart") {
                                // Favorite action
                            }
                        }
                        .padding()
                        .padding(.top, 50)
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 24) {
                        // Title and Meta
                        VStack(alignment: .leading, spacing: 12) {
                            if isEditing {
                                TextField("Dish name", text: $editedDishName)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.08))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                            } else {
                                Text(meal.dish_prediction)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            }
                            
                            HStack(spacing: 20) {
                                if let savedAt = meal.saved_at,
                                   let date = ISO8601DateFormatter().date(from: savedAt) {
                                    InfoPill(
                                        icon: "calendar",
                                        text: formatDate(date),
                                        color: .blue
                                    )
                                }
                                
                                if let mealType = meal.meal_type {
                                    InfoPill(
                                        icon: "fork.knife",
                                        text: mealType,
                                        color: .purple
                                    )
                                }
                                
                                if let calories = extractCalories(from: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo) {
                                    InfoPill(
                                        icon: "flame.fill",
                                        text: "\(calories) kcal",
                                        color: .orange
                                    )
                                }
                            }
                        }
                        
                        // Beautiful Nutrition Overview Card (Updated)
                        BeautifulNutritionView(nutritionText: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo)
                        
                        // Visible Ingredients Section
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(
                                title: "Visible Ingredients",
                                icon: "leaf.fill",
                                color: Color.green,
                                action: isEditing ? addNewVisibleIngredient : nil,
                                actionIcon: isEditing ? "plus.circle" : nil
                            )
                            
                            if isEditing {
                                VStack(spacing: 12) {
                                    ForEach($editedVisibleIngredients) { $ingredient in
                                        EditableIngredientRow(
                                            ingredient: $ingredient,
                                            onDelete: { removeVisibleIngredient(id: ingredient.id) }
                                        )
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    // FIXED: Filter out dashed lines when displaying
                                    ForEach(filteredIngredientLines(from: meal.image_description), id: \.self) { line in
                                        IngredientDisplay(text: String(line))
                                    }
                                }
                            }
                        }
                        
                        // Hidden Ingredients Section
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(
                                title: "Hidden Ingredients",
                                icon: "eye.slash.fill",
                                color: Color.pink,
                                action: isEditing ? addNewHiddenIngredient : nil,
                                actionIcon: isEditing ? "plus.circle" : nil
                            )
                            
                            if isEditing {
                                VStack(spacing: 12) {
                                    ForEach($editedHiddenIngredients) { $ingredient in
                                        EditableIngredientRow(
                                            ingredient: $ingredient,
                                            onDelete: { removeHiddenIngredient(id: ingredient.id) }
                                        )
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    if let hidden = meal.hidden_ingredients, !hidden.isEmpty {
                                        // FIXED: Filter out dashed lines when displaying
                                        ForEach(filteredIngredientLines(from: hidden), id: \.self) { line in
                                            IngredientDisplay(text: String(line), isHidden: true)
                                        }
                                    } else {
                                        HStack {
                                            Circle()
                                                .fill(Color.pink.opacity(0.2))
                                                .frame(width: 8, height: 8)
                                            
                                            Text("No hidden ingredients identified")
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.6))
                                                .italic()
                                            
                                            Spacer()
                                        }
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Recalculate Nutrition Button (only when editing)
                        if isEditing {
                            Button(action: recalculateNutrition) {
                                HStack {
                                    if isRecalculatingNutrition {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text("Recalculate Nutrition")
                                }
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.purple, .purple.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                            .disabled(isRecalculatingNutrition)
                        }
                        
                        // Action Buttons
                        if isEditing {
                            HStack(spacing: 12) {
                                Button(action: cancelEditing) {
                                    Text("Cancel")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                }
                                
                                Button(action: saveChanges) {
                                    HStack {
                                        if isSaving {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "checkmark")
                                            Text("Save")
                                        }
                                    }
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.green, .green.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(12)
                                }
                                .disabled(isSaving)
                            }
                        } else {
                            HStack(spacing: 12) {
                                Button(action: startEditing) {
                                    HStack {
                                        Image(systemName: "pencil")
                                        Text("Edit")
                                    }
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(12)
                                }
                                
                                Button(action: { showDeleteAlert = true }) {
                                    HStack {
                                        if isDeleting {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "trash")
                                            Text("Delete")
                                        }
                                    }
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [.red, .red.opacity(0.8)]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(12)
                                }
                                .disabled(isDeleting)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 40)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Meal", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteMeal()
            }
        } message: {
            Text("Are you sure you want to delete this meal? This action cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareText()])
        }
    }
    
    // MARK: - NEW: Filter Function for Ingredient Lines
    
    func filteredIngredientLines(from text: String) -> [String] {
        return text.split(separator: "\n").compactMap { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip only truly empty lines
            if trimmedLine.isEmpty { return nil }
            
            // Skip only obvious header lines
            if trimmedLine.lowercased() == "ingredient | quantity number | unit" {
                return nil
            }
            
            // DON'T skip lines with dashes or other content
            // The Pydantic model ensures clean data, so we don't need aggressive filtering
            
            let parts = trimmedLine.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            
            // Accept any line with at least one part (ingredient name)
            if parts.count >= 1 && !parts[0].isEmpty {
                return String(trimmedLine)
            }
            
            return nil
        }
    }
    
    // MARK: - Helper Functions
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    func generateShareText() -> String {
        var text = "Check out my meal: \(meal.dish_prediction)\n\n"
        
        // Add visible ingredients (filtered)
        text += "Visible Ingredients:\n"
        for line in filteredIngredientLines(from: meal.image_description) {
            text += "• \(line)\n"
        }
        
        // Add hidden ingredients if they exist (filtered)
        if let hidden = meal.hidden_ingredients, !hidden.isEmpty {
            text += "\nHidden Ingredients:\n"
            for line in filteredIngredientLines(from: hidden) {
                text += "• \(line)\n"
            }
        }
        
        // Add nutrition info
        if let calories = extractCalories(from: meal.nutrition_info) {
            text += "\nCalories: \(calories) kcal\n"
        }
        
        text += "\nTracked with NutriSnap 🍎"
        return text
    }
    
    func startEditing() {
        isEditing = true
        editedDishName = meal.dish_prediction
        editedVisibleIngredients = parseIngredientsToEditableFiltered(from: meal.image_description)
        editedHiddenIngredients = parseIngredientsToEditableFiltered(from: meal.hidden_ingredients ?? "")
        updatedNutritionInfo = meal.nutrition_info
    }
    
    func cancelEditing() {
        isEditing = false
        editedDishName = ""
        editedVisibleIngredients = []
        editedHiddenIngredients = []
        updatedNutritionInfo = ""
    }
    
    func addNewVisibleIngredient() {
        editedVisibleIngredients.append(EditableIngredient(
            id: UUID().uuidString,
            name: "New Ingredient",
            quantity: "1",
            unit: "piece"
        ))
    }
    
    func addNewHiddenIngredient() {
        editedHiddenIngredients.append(EditableIngredient(
            id: UUID().uuidString,
            name: "New Hidden Ingredient",
            quantity: "1",
            unit: "tsp"
        ))
    }
    
    func removeVisibleIngredient(id: String) {
        editedVisibleIngredients.removeAll { $0.id == id }
    }
    
    func removeHiddenIngredient(id: String) {
        editedHiddenIngredients.removeAll { $0.id == id }
    }
    
    func recalculateNutrition() {
        isRecalculatingNutrition = true
        
        // Combine visible and hidden ingredients
        let allIngredients = editedVisibleIngredients + editedHiddenIngredients
        let ingredientsList = allIngredients.map { "\($0.name) | \($0.quantity) | \($0.unit)" }.joined(separator: "\n")
        
        NetworkManager.shared.recalculateNutrition(
            ingredients: ingredientsList
        ) { result in
            self.isRecalculatingNutrition = false
            
            switch result {
            case .success(let nutritionData):
                // Update the nutrition info for Beautiful Nutrition View
                self.updatedNutritionInfo = nutritionData.nutrition_info
                
            case .failure(let error):
                print("❌ Nutrition recalculation failed: \(error)")
                // Keep existing nutrition info if recalculation fails
            }
        }
    }
    
    func saveChanges() {
        isSaving = true
        
        // Update meal data
        meal.dish_prediction = editedDishName
        meal.image_description = editedVisibleIngredients.map {
            "\($0.name) | \($0.quantity) | \($0.unit) | User edited"
        }.joined(separator: "\n")
        
        // Update hidden ingredients
        let hiddenIngredientsString = editedHiddenIngredients.map {
            "\($0.name) | \($0.quantity) | \($0.unit) | User edited"
        }.joined(separator: "\n")
        
        // Update nutrition if recalculated
        if !updatedNutritionInfo.isEmpty {
            meal.nutrition_info = updatedNutritionInfo
        }
        
        updateMealInBackend(hiddenIngredients: hiddenIngredientsString)
    }
    
    func updateMealInBackend(hiddenIngredients: String) {
        // Create payload with all updated data
        let payload: [String: Any] = [
            "meal_id": meal._id,
            "dish_prediction": meal.dish_prediction,
            "image_description": meal.image_description,
            "hidden_ingredients": hiddenIngredients,
            "nutrition_info": updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo,
            "meal_type": meal.meal_type ?? "Lunch"
        ]
        
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/update-meal"),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            self.isSaving = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSaving = false
                
                if let error = error {
                    print("❌ Update error: \(error)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Update the meal object with hidden ingredients
                    self.meal.hidden_ingredients = hiddenIngredients
                    self.isEditing = false
                    NotificationCenter.default.post(name: Notification.Name("MealUpdated"), object: nil)
                } else {
                    print("❌ Update failed with status code")
                }
            }
        }.resume()
    }
    
    func deleteMeal() {
        isDeleting = true
        
        NetworkManager.shared.deleteMeal(mealId: meal._id) { success in
            self.isDeleting = false
            if success {
                NotificationCenter.default.post(name: Notification.Name("MealDeleted"), object: nil)
                self.dismiss()
            }
        }
    }

    func decodeBase64ToUIImage(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    // UPDATED: Filter out dashed lines when parsing for editing
    func parseIngredientsToEditableFiltered(from text: String) -> [EditableIngredient] {
        return filteredIngredientLines(from: text).compactMap { line in
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
            guard parts.count >= 3 else { return nil }
            return EditableIngredient(
                id: UUID().uuidString,
                name: parts[0],
                quantity: parts[1],
                unit: parts[2]
            )
        }
    }
    
    func extractCalories(from text: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "|").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
            if parts.count >= 2, parts[0].lowercased().contains("calories") {
                return Int(parts[1])
            }
        }
        return nil
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .blur(radius: 10)
                )
        }
    }
}

struct InfoPill: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.2))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
