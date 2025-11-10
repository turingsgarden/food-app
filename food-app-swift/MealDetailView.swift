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
    @State private var showSuccessToast = false
    @State private var toastMessage = ""
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
                        
                        // Beautiful Nutrition Overview Card
                        BeautifulNutritionView(nutritionText: updatedNutritionInfo.isEmpty ? meal.nutrition_info : updatedNutritionInfo)
                        
                        // Visible Ingredients Section
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeader(
                                title: "Visible Ingredients",
                                icon: "leaf.fill",
                                color: Color.green,
                                action: nil,
                                actionIcon: nil
                            )
                            
                            if isEditing {
                                VStack(spacing: 12) {
                                    ForEach($editedVisibleIngredients) { $ingredient in
                                        QuantityOnlyIngredientRow(
                                            ingredient: $ingredient,
                                            onDelete: nil
                                        )
                                    }
                                    
                                    // Info message
                                    HStack {
                                        Image(systemName: "info.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange.opacity(0.8))
                                        
                                        Text("Only quantities can be edited")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 4)
                                }
                            } else {
                                VStack(spacing: 8) {
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
                                action: nil,
                                actionIcon: nil
                            )
                            
                            if isEditing {
                                if !editedHiddenIngredients.isEmpty {
                                    VStack(spacing: 12) {
                                        ForEach($editedHiddenIngredients) { $ingredient in
                                            QuantityOnlyIngredientRow(
                                                ingredient: $ingredient,
                                                onDelete: nil
                                            )
                                        }
                                        
                                        // Info message
                                        HStack {
                                            Image(systemName: "info.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(.orange.opacity(0.8))
                                            
                                            Text("Nutrition will be recalculated automatically")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                } else {
                                    HStack {
                                        Circle()
                                            .fill(Color.pink.opacity(0.2))
                                            .frame(width: 8, height: 8)
                                        
                                        Text("No hidden ingredients to edit")
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
                            } else {
                                VStack(spacing: 8) {
                                    if let hidden = meal.hidden_ingredients, !hidden.isEmpty {
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
                                .disabled(isSaving || isRecalculatingNutrition)
                                
                                Button(action: saveChanges) {
                                    HStack {
                                        if isSaving || isRecalculatingNutrition {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.9)
                                            Text(isRecalculatingNutrition ? "Calculating..." : "Saving...")
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
                                .disabled(isSaving || isRecalculatingNutrition)
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
            
            // Success Toast
            if showSuccessToast {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                        Text(toastMessage)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
                    .padding()
                    .transition(.move(edge: .bottom))
                }
                .animation(.spring(), value: showSuccessToast)
            }
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
    
    // MARK: - Filter Function for Ingredient Lines
    
    func filteredIngredientLines(from text: String) -> [String] {
        return text.split(separator: "\n").compactMap { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.isEmpty { return nil }
            if trimmedLine.lowercased() == "ingredient | quantity number | unit" {
                return nil
            }
            
            let parts = trimmedLine.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            
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
        
        text += "Visible Ingredients:\n"
        for line in filteredIngredientLines(from: meal.image_description) {
            let cleanLine = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
            text += "• \(cleanLine)\n"
        }
        
        if let hidden = meal.hidden_ingredients, !hidden.isEmpty {
            text += "\nHidden Ingredients:\n"
            for line in filteredIngredientLines(from: hidden) {
                let cleanLine = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
                text += "• \(cleanLine)\n"
            }
        }
        
        if let calories = extractCalories(from: meal.nutrition_info) {
            text += "\nCalories: \(calories) kcal\n"
        }
        
        text += "\nTracked with NutriSnap 🎯"
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
    
    func saveChanges() {
        isSaving = true
        isRecalculatingNutrition = true
        
        // First, recalculate nutrition with the new quantities
        let allIngredients = editedVisibleIngredients + editedHiddenIngredients
        let ingredientsList = allIngredients.map { "\($0.name) | \($0.quantity) | \($0.unit)" }.joined(separator: "\n")
        
        print("📊 Recalculating nutrition for edited meal...")
        print("📊 Ingredients list:\n\(ingredientsList)")
        
        NetworkManager.shared.recalculateNutrition(
            ingredients: ingredientsList
        ) { result in
            self.isRecalculatingNutrition = false
            
            switch result {
            case .success(let nutritionData):
                print("✅ Nutrition recalculated successfully")
                print("📊 New nutrition: \(nutritionData.nutrition_info)")
                
                // Update the nutrition info with recalculated values
                self.updatedNutritionInfo = nutritionData.nutrition_info
                
                // Update the meal object immediately with new nutrition
                self.meal.nutrition_info = nutritionData.nutrition_info
                
                // Now save everything with the new nutrition
                self.performSave()
                
            case .failure(let error):
                print("❌ Nutrition recalculation failed: \(error)")
                // Save with existing nutrition if recalculation fails
                self.performSave()
            }
        }
    }
    
    private func performSave() {
        // Update meal data
        meal.dish_prediction = editedDishName
        meal.image_description = editedVisibleIngredients.map {
            "\($0.name) | \($0.quantity) | \($0.unit) | User edited"
        }.joined(separator: "\n")
        
        // Update hidden ingredients
        let hiddenIngredientsString = editedHiddenIngredients.map {
            "\($0.name) | \($0.quantity) | \($0.unit) | User edited"
        }.joined(separator: "\n")
        
        meal.hidden_ingredients = hiddenIngredientsString
        
        // Make sure we have the updated nutrition
        if !updatedNutritionInfo.isEmpty {
            meal.nutrition_info = updatedNutritionInfo
        }
        
        print("📊 Saving meal with updated nutrition: \(meal.nutrition_info.prefix(100))...")
        
        updateMealInBackend(hiddenIngredients: hiddenIngredientsString)
    }
    
    func updateMealInBackend(hiddenIngredients: String) {
        // Get JWT token
        guard let token = SessionManager.shared.getAuthToken() else {
            self.isSaving = false
            print("❌ No auth token available")
            return
        }
        
        // Create payload with all updated data including the new nutrition
        let payload: [String: Any] = [
            "meal_id": meal._id,
            "dish_prediction": meal.dish_prediction,
            "image_description": meal.image_description,
            "hidden_ingredients": hiddenIngredients,
            "nutrition_info": meal.nutrition_info,  // This now contains the updated nutrition
            "meal_type": meal.meal_type ?? "Lunch"
        ]
        
        print("📤 Sending update with nutrition: \(meal.nutrition_info.prefix(100))...")
        
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/update-meal"),
              let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            self.isSaving = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSaving = false
                
                if let error = error {
                    print("❌ Update error: \(error)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("✅ Meal updated successfully")
                    
                    // Update is complete, nutrition is already in the meal object
                    self.isEditing = false
                    
                    // Show success toast
                    self.toastMessage = "Meal updated successfully!"
                    self.showSuccessToast = true
                    
                    // Hide toast after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showSuccessToast = false
                    }
                    
                    // Post notifications to refresh all views
                    NotificationCenter.default.post(name: Notification.Name("MealUpdated"), object: nil)
                    NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)
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
                NotificationCenter.default.post(name: Notification.Name("MealSaved"), object: nil)
                self.dismiss()
            }
        }
    }

    func decodeBase64ToUIImage(_ base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    func parseIngredientsToEditableFiltered(from text: String) -> [EditableIngredient] {
        return filteredIngredientLines(from: text).compactMap { line in
            let cleanLine = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
            let parts = cleanLine.split(separator: "|").map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
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

// MARK: - Supporting Views (keep existing)

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
