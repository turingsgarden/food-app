import SwiftUI

struct BeautifulNutritionView: View {
    let nutritionText: String
    @State private var nutritionItems: [NutritionItem] = []
    @State private var hasInitialized = false
    
    var caloriesItem: NutritionItem? {
        nutritionItems.first { $0.name.lowercased().contains("calorie") }
    }
    
    var otherItems: [NutritionItem] {
        nutritionItems.filter { !$0.name.lowercased().contains("calorie") }
    }
    
    var hasValidNutrition: Bool {
        !nutritionItems.isEmpty && nutritionItems.contains { item in
            return valueIsPositive(item.value)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                Text("Nutrition Facts")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            if hasValidNutrition {
                // Calories Highlight (if available)
                if let calories = caloriesItem {
                    CaloriesHighlightCard(item: calories)
                }
                
                // Other Nutrients Grid
                if !otherItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Detailed Breakdown")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(otherItems.prefix(6)) { item in
                                NutrientCard(item: item)
                            }
                        }
                    }
                }
            } else {
                // Loading or empty state
                VStack(spacing: 16) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 40))
                        .foregroundColor(.orange.opacity(0.6))
                    
                    Text("Nutrition data unavailable")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Processing nutrition information...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .orange.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            if !hasInitialized {
                hasInitialized = true
                parseNutritionSimple()
            }
        }
        .onChange(of: nutritionText) { oldValue, newValue in
            if newValue != oldValue {
                parseNutritionSimple()
            }
        }
    }
    
    // MARK: - Enhanced Nutrition Parsing
    
    private func parseNutritionSimple() {
        var items: [NutritionItem] = []
        
        // Handle both \n and \r\n line endings
        let lines = nutritionText.components(separatedBy: CharacterSet.newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }
            
            // Try to parse lines with | separator
            if trimmed.contains("|") {
                let parts = trimmed.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                
                if parts.count >= 3 {
                    let name = cleanNutrientName(parts[0])
                    var valueStr = ""
                    var unit = ""

                    if parts.count >= 4 {
                        // name | min | max | unit  -> normalize to min-max
                        let minStr = cleanValueString(parts[1])
                        let maxStr = cleanValueString(parts[2])
                        unit = parts[3]
                        if !minStr.isEmpty && !maxStr.isEmpty {
                            valueStr = "\(minStr)-\(maxStr)"
                        }
                    } else {
                        // parts.count == 3 -> name | value | unit
                        let rawVal = parts[1]
                        unit = parts[2]
                        valueStr = cleanValueString(rawVal)
                    }

                    if isValidNutrientName(name) && !valueStr.isEmpty && isNumericOrRange(valueStr) {
                        let item = NutritionItem(
                            name: name,
                            value: valueStr,
                            unit: unit,
                            reasoning: nil
                        )
                        items.append(item)
                    }
                }
            }
        }
        
        // If we got valid items, use them
        if !items.isEmpty {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.nutritionItems = items
                }
            }
        } else {
            // Use default nutrition with zero values
            items = getDefaultNutrition()
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.nutritionItems = items
                }
            }
        }
    }
    
    private func isValidNutrientName(_ name: String) -> Bool {
        let validNutrients = ["calorie", "protein", "fat", "carb", "fiber", "fibre", "sugar", "sodium", "salt", "energy", "kcal"]
        let lowercased = name.lowercased()
        
        // Check if name contains any valid nutrient word
        for nutrient in validNutrients {
            if lowercased.contains(nutrient) {
                return true
            }
        }
        
        // Reject if it looks like an ID or random text
        if lowercased.contains("id") || Int(name) != nil {
            return false
        }
        
        return false
    }
    
    private func cleanNutrientName(_ name: String) -> String {
        // Clean up nutrient names
        return name
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanValueString(_ value: String) -> String {
        // Clean up value strings - remove commas, spaces, etc.
        return value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func guessUnit(for nutrient: String) -> String {
        let lowercased = nutrient.lowercased()
        if lowercased.contains("calorie") || lowercased.contains("energy") {
            return "kcal"
        } else if lowercased.contains("sodium") {
            return "mg"
        } else {
            return "g"
        }
    }
    
    private func getDefaultNutrition() -> [NutritionItem] {
        return [
            NutritionItem(name: "Calories", value: "0", unit: "kcal", reasoning: nil),
            NutritionItem(name: "Protein", value: "0", unit: "g", reasoning: nil),
            NutritionItem(name: "Fat", value: "0", unit: "g", reasoning: nil),
            NutritionItem(name: "Carbohydrates", value: "0", unit: "g", reasoning: nil),
            NutritionItem(name: "Fiber", value: "0", unit: "g", reasoning: nil),
            NutritionItem(name: "Sugar", value: "0", unit: "g", reasoning: nil),
            NutritionItem(name: "Sodium", value: "0", unit: "mg", reasoning: nil)
        ]
    }

    // MARK: - Range Helpers

    private func isNumericOrRange(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if Double(trimmed) != nil { return true }

        let pattern = "^\\d+(?:\\.\\d+)?-\\d+(?:\\.\\d+)?$"
        if let _ = trimmed.range(of: pattern, options: .regularExpression) {
            return true
        }
        return false
    }

    private func valueIsPositive(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Double(trimmed) {
            return v > 0
        }

        // range
        let parts = trimmed.split(separator: "-").map { String($0) }
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]) {
            return (a + b) / 2.0 > 0
        }

        return false
    }
}

// MARK: - Supporting Views (keep existing)

struct CaloriesHighlightCard: View {
    let item: NutritionItem
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.3), .orange.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(item.value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(item.unit)
                        .font(.title3)
                        .foregroundColor(.gray)
                        .padding(.bottom, 4)
                }
                
                Text(item.name)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [.red.opacity(0.1), .orange.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct NutrientCard: View {
    let item: NutritionItem
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: item.icon)
                .font(.title2)
                .foregroundColor(item.color)
            
            // Value
            VStack(spacing: 2) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text(item.value)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    
                    Text(item.unit)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Text(item.name)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(item.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(item.color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
