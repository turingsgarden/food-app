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
            if let value = Int(item.value), value > 0 {
                return true
            }
            return false
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
                            ForEach(otherItems) { item in
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
                    
                    if !nutritionText.isEmpty {
                        Text("Processing nutrition information...")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
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
            print("📊 BeautifulNutritionView - nutrition text changed")
            print("📊 Old length: \(oldValue.count), New length: \(newValue.count)")
            if newValue != oldValue {
                parseNutritionSimple()
            }
        }
    }
    
    // MARK: - Enhanced Nutrition Parsing
    
    private func parseNutritionSimple() {
        var items: [NutritionItem] = []
        
        print("🔍 BeautifulNutritionView - Starting nutrition parse")
        print("📊 Raw text: '\(nutritionText)'")
        print("📊 Text length: \(nutritionText.count)")
        
        // Handle both \n and \r\n line endings
        let lines = nutritionText.components(separatedBy: CharacterSet.newlines)
        print("📊 Found \(lines.count) lines to parse")
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }
            
            print("📊 Processing line \(index): '\(trimmed)'")
            
            // Try to parse lines with | separator
            if trimmed.contains("|") {
                let parts = trimmed.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                
                print("📊 Parts found: \(parts)")
                
                if parts.count >= 3 {
                    let name = cleanNutrientName(parts[0])
                    let valueStr = cleanValueString(parts[1])
                    let unit = parts[2]
                    
                    print("📊 Parsed: name='\(name)', value='\(valueStr)', unit='\(unit)'")
                    
                    // Validate that value is numeric
                    if !valueStr.isEmpty && (Double(valueStr) != nil || Int(valueStr) != nil) {
                        let item = NutritionItem(
                            name: name,
                            value: valueStr,
                            unit: unit,
                            reasoning: nil
                        )
                        items.append(item)
                        print("✅ Added nutrition item: \(name) = \(valueStr) \(unit)")
                    } else {
                        print("⚠️ Invalid value '\(valueStr)' for nutrient '\(name)'")
                    }
                } else if parts.count == 2 {
                    // Handle format without unit (e.g., "Calories|450")
                    let name = cleanNutrientName(parts[0])
                    let valueStr = cleanValueString(parts[1])
                    
                    if !valueStr.isEmpty && (Double(valueStr) != nil || Int(valueStr) != nil) {
                        let unit = guessUnit(for: name)
                        let item = NutritionItem(
                            name: name,
                            value: valueStr,
                            unit: unit,
                            reasoning: nil
                        )
                        items.append(item)
                        print("✅ Added nutrition item (guessed unit): \(name) = \(valueStr) \(unit)")
                    }
                }
            } else {
                print("📊 No pipe separator, trying alternative format")
                if let item = parseAlternativeFormat(trimmed) {
                    items.append(item)
                    print("✅ Added from alt format: \(item.name) = \(item.value) \(item.unit)")
                }
            }
        }
        
        // If we got valid items, use them
        if !items.isEmpty {
            print("✅ Successfully parsed \(items.count) nutrition items")
            for item in items {
                print("  - \(item.name): \(item.value) \(item.unit)")
            }
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.nutritionItems = items
                }
            }
        } else {
            print("⚠️ No nutrition items found, using defaults")
            items = getDefaultNutrition()
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.nutritionItems = items
                }
            }
        }
    }
    
    private func cleanNutrientName(_ name: String) -> String {
        // Clean up nutrient names
        return name
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanValueString(_ value: String) -> String {
        // Clean up value strings - remove commas, extra spaces, etc.
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
    
    private func parseAlternativeFormat(_ line: String) -> NutritionItem? {
        // Common patterns: "Calories: 500 kcal" or "Protein - 20g"
        let patterns = [
            #"(\w+)\s*:\s*(\d+\.?\d*)\s*(\w+)"#,
            #"(\w+)\s*-\s*(\d+\.?\d*)\s*(\w+)"#,
            #"(\w+)\s+(\d+\.?\d*)\s*(\w+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
                
                if let nameRange = Range(match.range(at: 1), in: line),
                   let valueRange = Range(match.range(at: 2), in: line),
                   let unitRange = Range(match.range(at: 3), in: line) {
                    
                    return NutritionItem(
                        name: String(line[nameRange]),
                        value: String(line[valueRange]),
                        unit: String(line[unitRange]),
                        reasoning: nil
                    )
                }
            }
        }
        
        return nil
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
