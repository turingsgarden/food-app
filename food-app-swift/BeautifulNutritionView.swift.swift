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
        !nutritionItems.isEmpty
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
                // Error state - but still try to show something
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange.opacity(0.6))
                    
                    Text("Processing nutrition data...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    
                    // DEBUG: Show raw text
                    if !nutritionText.isEmpty {
                        Text("Raw data: \(nutritionText.prefix(50))...")
                            .font(.caption2)
                            .foregroundColor(.gray)
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
    
    // MARK: - Simple Nutrition Parsing (Works with backend format)
    
    private func parseNutritionSimple() {
        var items: [NutritionItem] = []
        
        print("🔍 BeautifulNutritionView - Parsing nutrition text: \(nutritionText)")
        print("🔍 Text length: \(nutritionText.count)")
        
        // Handle both \n and \r\n line endings
        let lines = nutritionText.components(separatedBy: CharacterSet.newlines)
        print("📊 Found \(lines.count) lines")
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines
            if trimmed.isEmpty {
                print("⏭️ Line \(index): Empty, skipping")
                continue
            }
            
            print("📊 Line \(index): '\(trimmed)'")
            
            // Try to parse lines with | separator
            if trimmed.contains("|") {
                let parts = trimmed.components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                
                print("📊 Parts count: \(parts.count), Parts: \(parts)")
                
                if parts.count >= 3 {
                    let name = parts[0]
                    let value = parts[1]
                    let unit = parts[2]
                    
                    // Validate that value is numeric
                    if !value.isEmpty && (Double(value) != nil || Int(value) != nil) {
                        // Create nutrition item
                        let item = NutritionItem(
                            name: name,
                            value: value,
                            unit: unit,
                            reasoning: nil
                        )
                        items.append(item)
                        
                        print("✅ Added nutrition item: \(name) = \(value) \(unit)")
                    } else {
                        print("⚠️ Invalid value '\(value)' for nutrient '\(name)'")
                    }
                } else {
                    print("⚠️ Invalid parts count: \(parts.count) for line: '\(trimmed)'")
                }
            } else {
                print("📊 No pipe separator, trying alternative format")
                // Try to parse other formats (e.g., "Calories: 500 kcal")
                if let item = parseAlternativeFormat(trimmed) {
                    items.append(item)
                    print("✅ Added nutrition item from alt format: \(item.name) = \(item.value) \(item.unit)")
                } else {
                    print("⚠️ Could not parse line: '\(trimmed)'")
                }
            }
        }
        
        // If no items found, add defaults
        if items.isEmpty {
            print("⚠️ No nutrition items found, using defaults")
            items = getDefaultNutrition()
        } else {
            print("✅ Total nutrition items parsed: \(items.count)")
            for item in items {
                print("  - \(item.name): \(item.value) \(item.unit)")
            }
        }
        
        // Use main queue to update state
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.nutritionItems = items
            }
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
            NutritionItem(name: "Calories", value: "---", unit: "kcal", reasoning: nil),
            NutritionItem(name: "Protein", value: "---", unit: "g", reasoning: nil),
            NutritionItem(name: "Fat", value: "---", unit: "g", reasoning: nil),
            NutritionItem(name: "Carbohydrates", value: "---", unit: "g", reasoning: nil),
            NutritionItem(name: "Fiber", value: "---", unit: "g", reasoning: nil),
            NutritionItem(name: "Sugar", value: "---", unit: "g", reasoning: nil),
            NutritionItem(name: "Sodium", value: "---", unit: "mg", reasoning: nil)
        ]
    }
}

// MARK: - Supporting Views

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

// MARK: - Preview
struct BeautifulNutritionView_Previews: PreviewProvider {
    static var previews: some View {
        BeautifulNutritionView(nutritionText: """
            Calories|450|kcal
            Protein|25|g
            Fat|12|g
            Carbohydrates|60|g
            Fiber|8|g
            Sugar|5|g
            Sodium|800|mg
            """)
        .preferredColorScheme(.dark)
        .padding()
        .background(Color.black)
    }
}
