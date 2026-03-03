import SwiftUI

struct BeautifulNutritionView: View {
    let nutritionText: String
    @State private var nutritionItems: [NutritionItem] = []
    @State private var hasInitialized = false

    var caloriesItem: NutritionItem? {
        nutritionItems.first { $0.name.lowercased().contains("calorie") }
    }

    var gridItems: [NutritionItem] {
        let order = ["protein", "fat", "carb", "fiber", "sugar", "sodium"]
        return order.compactMap { keyword in
            nutritionItems.first { $0.name.lowercased().contains(keyword) }
        }
    }

    var hasValidNutrition: Bool {
        nutritionItems.contains { Double($0.value) ?? 0 > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(Color.orange).frame(width: 3, height: 18).cornerRadius(2)
                Text("NUTRITION")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(.orange).kerning(3)
                Spacer()
            }
            .padding(.bottom, 16)

            if hasValidNutrition {
                if let cal = caloriesItem {
                    CaloriesBigRow(item: cal).padding(.bottom, 20)
                }
                if !gridItems.isEmpty {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(gridItems) { item in
                            NutrientFlatCell(item: item)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 4)
        .onAppear {
            if !hasInitialized { hasInitialized = true; parseNutrition() }
        }
        .onChange(of: nutritionText) { _, _ in parseNutrition() }
    }

    var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.bar").font(.system(size: 32)).foregroundColor(.white.opacity(0.15))
                Text("No nutrition data").font(.caption).foregroundColor(.white.opacity(0.3))
            }
            Spacer()
        }
        .padding(.vertical, 32)
    }

    private func parseNutrition() {
        var items: [NutritionItem] = []
        for line in nutritionText.components(separatedBy: CharacterSet.newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.contains("|") else { continue }
            let parts = trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 2 else { continue }
            let name = parts[0].replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            let valueStr = parts[1].replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            // ✅ 修复：第三列是数字（参考值）时忽略，改用默认单位
            let rawUnit = parts.count >= 3 ? parts[2] : ""
            let unit = (Double(rawUnit) != nil || rawUnit.isEmpty) ? guessUnit(for: name) : rawUnit
            guard isValidNutrient(name), Double(valueStr) != nil else { continue }
            items.append(NutritionItem(name: name, value: valueStr, unit: unit, reasoning: nil))
        }
        if items.isEmpty { items = defaultNutrition() }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.3)) { self.nutritionItems = items }
        }
    }

    private func isValidNutrient(_ name: String) -> Bool {
        let keywords = ["calorie", "protein", "fat", "carb", "fiber", "fibre", "sugar", "sodium", "salt", "energy", "kcal"]
        return keywords.contains { name.lowercased().contains($0) }
    }

    private func guessUnit(for name: String) -> String {
        let l = name.lowercased()
        if l.contains("calorie") || l.contains("energy") { return "kcal" }
        if l.contains("sodium") { return "mg" }
        return "g"
    }

    private func defaultNutrition() -> [NutritionItem] {
        [
            NutritionItem(name: "Calories",      value: "0", unit: "kcal", reasoning: nil),
            NutritionItem(name: "Protein",       value: "0", unit: "g",    reasoning: nil),
            NutritionItem(name: "Fat",           value: "0", unit: "g",    reasoning: nil),
            NutritionItem(name: "Carbohydrates", value: "0", unit: "g",    reasoning: nil),
            NutritionItem(name: "Fiber",         value: "0", unit: "g",    reasoning: nil),
            NutritionItem(name: "Sugar",         value: "0", unit: "g",    reasoning: nil),
            NutritionItem(name: "Sodium",        value: "0", unit: "mg",   reasoning: nil),
        ]
    }
}

// MARK: - 卡路里大数字

struct CaloriesBigRow: View {
    let item: NutritionItem

    var displayUnit: String {
        Double(item.unit) != nil || item.unit.isEmpty ? "kcal" : item.unit
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.value)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Text(displayUnit.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange).kerning(2)
                    Text("·").foregroundColor(.white.opacity(0.2))
                    Text("CALORIES")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4)).kerning(1)
                }
            }
            Spacer()
            Image(systemName: "flame.fill").font(.system(size: 36))
                .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .bottom, endPoint: .top))
                .opacity(0.6)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 无框营养素格子

struct NutrientFlatCell: View {
    let item: NutritionItem

    var label: String {
        let n = item.name.lowercased()
        if n.contains("protein")                      { return "Protein" }
        if n.contains("fat")                          { return "Fat" }
        if n.contains("carb")                         { return "Carbs" }
        if n.contains("fiber") || n.contains("fibre") { return "Fiber" }
        if n.contains("sugar")                        { return "Sugar" }
        if n.contains("sodium")                       { return "Sodium" }
        return item.name
    }

    var accentColor: Color {
        let n = item.name.lowercased()
        if n.contains("protein") { return Color(red: 0.3, green: 0.7, blue: 1.0) }
        if n.contains("fat")     { return Color(red: 1.0, green: 0.75, blue: 0.3) }
        if n.contains("carb")    { return Color(red: 0.4, green: 0.9, blue: 0.5) }
        if n.contains("fiber")   { return Color(red: 0.6, green: 0.4, blue: 0.9) }
        if n.contains("sugar")   { return Color(red: 1.0, green: 0.4, blue: 0.6) }
        if n.contains("sodium")  { return Color(red: 1.0, green: 0.5, blue: 0.4) }
        return .gray
    }

    var displayUnit: String {
        if Double(item.unit) != nil || item.unit.isEmpty {
            let n = item.name.lowercased()
            if n.contains("calorie") || n.contains("energy") { return "kcal" }
            if n.contains("sodium") { return "mg" }
            return "g"
        }
        return item.unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(accentColor)
                .kerning(0.5)
            HStack(alignment: .bottom, spacing: 2) {
                Text(item.value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(displayUnit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 旧版组件保留（兼容）

struct CaloriesHighlightCard: View {
    let item: NutritionItem
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.red.opacity(0.3), .orange.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 60, height: 60)
                Image(systemName: "flame.fill").font(.title2).foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    Text(item.value).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text(item.unit).font(.title3).foregroundColor(.gray).padding(.bottom, 4)
                }
                Text(item.name).font(.subheadline).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [.red.opacity(0.1), .orange.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.2), lineWidth: 1)))
    }
}

struct NutrientCard: View {
    let item: NutritionItem
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: item.icon).font(.title2).foregroundColor(item.color)
            VStack(spacing: 2) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text(item.value).font(.title3.bold()).foregroundColor(.white)
                    Text(item.unit).font(.caption).foregroundColor(.gray)
                }
                Text(item.name).font(.caption).foregroundColor(.gray).multilineTextAlignment(.center).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(item.color.opacity(0.1)).overlay(RoundedRectangle(cornerRadius: 12).stroke(item.color.opacity(0.2), lineWidth: 1)))
    }
}

struct MacroProgressRow: View {
    let item: NutritionItem
    let animate: Bool
    var body: some View { EmptyView() }
}

struct MicroNutrientCell: View {
    let item: NutritionItem
    var body: some View { EmptyView() }
}

struct UnifiedNutrientRow: View {
    let item: NutritionItem
    let animate: Bool
    let progress: Double?
    let accentColor: Color
    let label: String
    let subtitle: String?
    var body: some View { EmptyView() }
}
