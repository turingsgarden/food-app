
//  BeautifulNutritionView.swift
//  food-app-swift — v2
//
//  MealInsight, InsightWaveBar, MacroPieChart, DonutSlice, CollapsibleInsightPanel
//  are all defined in MealDetailView.swift — NOT repeated here.

import SwiftUI

struct BeautifulNutritionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionText: String
    @State private var nutritionItems: [NutritionItem] = []
    @State private var hasInitialized = false
    @State private var selectedItem: NutritionItem? = nil

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
                Text("tap for range")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.current.secondaryText)
                    .kerning(1)
            }
            .padding(.bottom, 16)

            if hasValidNutrition {
                if let cal = caloriesItem {
                    CaloriesBigRow(item: cal, onTap: { selectedItem = cal })
                        .environmentObject(themeManager)
                        .padding(.bottom, 20)
                }
                if !gridItems.isEmpty {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(gridItems) { item in
                            NutrientFlatCell(item: item, onTap: { selectedItem = item })
                                .environmentObject(themeManager)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
        .background(Color.clear)
        .onAppear {
            if !hasInitialized { hasInitialized = true; parseNutrition() }
        }
        .onChange(of: nutritionText) { _, _ in parseNutrition() }
        .overlay {
            if let item = selectedItem {
                NutrientRangePopup(item: item, onDismiss: { selectedItem = nil })
                    .environmentObject(themeManager)
            }
        }
    }

    var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.bar").font(.system(size: 32))
                    .foregroundColor(themeManager.current.secondaryText)
                Text("No nutrition data").font(.caption)
                    .foregroundColor(themeManager.current.secondaryText)
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

// MARK: - Range Popup


struct NutrientRangePopup: View {
    @EnvironmentObject var themeManager: ThemeManager
    let item: NutritionItem
    let onDismiss: () -> Void

    @State private var appeared = false

    var displayUnit: String {
        if Double(item.unit) != nil || item.unit.isEmpty {
            let n = item.name.lowercased()
            if n.contains("calorie") || n.contains("energy") { return "kcal" }
            if n.contains("sodium") { return "mg" }
            return "g"
        }
        return item.unit
    }

    var label: String {
        let n = item.name.lowercased()
        if n.contains("calorie")  { return "Calories" }
        if n.contains("protein")  { return "Protein" }
        if n.contains("fat")      { return "Fat" }
        if n.contains("carb")     { return "Carbohydrates" }
        if n.contains("fiber")    { return "Fiber" }
        if n.contains("sugar")    { return "Sugar" }
        if n.contains("sodium")   { return "Sodium" }
        return item.name
    }

    var accentColor: Color {
        let n = item.name.lowercased()
        if n.contains("calorie")  { return .orange }
        if n.contains("protein")  { return Color(red: 0.3, green: 0.7, blue: 1.0) }
        if n.contains("fat")      { return Color(red: 1.0, green: 0.75, blue: 0.3) }
        if n.contains("carb")     { return Color(red: 0.4, green: 0.9, blue: 0.5) }
        if n.contains("fiber")    { return Color(red: 0.6, green: 0.4, blue: 0.9) }
        if n.contains("sugar")    { return Color(red: 1.0, green: 0.4, blue: 0.6) }
        if n.contains("sodium")   { return Color(red: 1.0, green: 0.5, blue: 0.4) }
        return .gray
    }

    var rangeValues: (low: String, mid: String, high: String) {
        guard let val = Double(item.value) else { return ("—", item.value, "—") }
        let delta: Double = item.name.lowercased().contains("calorie") ? val * 0.05
                          : item.name.lowercased().contains("sodium")  ? val * 0.05
                          : 5.0
        let low  = max(0, val - delta)
        let high = val + delta
        let fmt: (Double) -> String = { v in
            if item.name.lowercased().contains("calorie") || item.name.lowercased().contains("sodium") {
                return String(Int(v.rounded()))
            }
            return String(format: "%.1f", v)
        }
        return (fmt(low), fmt(val), fmt(high))
    }

    var healthNote: String {
        guard let val = Double(item.value) else { return "" }
        let n = item.name.lowercased()
        if n.contains("protein") { return val >= 20 ? "✦ Good protein source" : "Low protein" }
        if n.contains("sodium") { return val > 1500 ? "⚠ High sodium" : val < 600 ? "✦ Low sodium" : "Moderate sodium" }
        if n.contains("fiber") { return val >= 5 ? "✦ Good fiber content" : "Low fiber" }
        if n.contains("sugar") { return val > 20 ? "⚠ High sugar" : "✦ Low sugar" }
        if n.contains("fat") { return val > 30 ? "⚠ High fat" : "✦ Moderate fat" }
        if n.contains("calorie") { return val > 800 ? "⚠ High calorie meal" : val < 300 ? "✦ Light meal" : "Balanced meal" }
        return ""
    }

    var body: some View {
        ZStack {
            // ── 背景蒙层：淡入 ─────────────────────────────────────────────
            Color.black
                .opacity(appeared ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // ── 弹窗主体：从下方弹入 ────────────────────────────────────────
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(accentColor).kerning(2)
                        Text("Estimated Range")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill").font(.title3)
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

                Divider().background(themeManager.current.cardBorder)

                // MIN / EST / MAX
                HStack(alignment: .bottom, spacing: 0) {
                    VStack(spacing: 4) {
                        Text("MIN").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.current.secondaryText).kerning(1)
                        Text(rangeValues.low).font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.secondaryText)
                        Text(displayUnit).font(.system(size: 10, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText)
                    }.frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        Text("EST.").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(accentColor).kerning(1)
                        Text(rangeValues.mid).font(.system(size: 32, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .foregroundColor(themeManager.current.primaryText)
                        Text(displayUnit).font(.system(size: 11, weight: .semibold)).foregroundColor(accentColor)
                    }.frame(maxWidth: .infinity)

                    VStack(spacing: 4) {
                        Text("MAX").font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(themeManager.current.secondaryText).kerning(1)
                        Text(rangeValues.high).font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.secondaryText)
                        Text(displayUnit).font(.system(size: 10, weight: .medium))
                            .foregroundColor(themeManager.current.secondaryText)
                    }.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20).padding(.vertical, 20)

                // Track
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(themeManager.current.inputBackground).frame(height: 6)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [accentColor.opacity(0.4), accentColor],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * 0.6, height: 6).offset(x: geo.size.width * 0.2)
                        Circle().fill(accentColor).frame(width: 12, height: 12).offset(x: geo.size.width * 0.5 - 6)
                    }
                }
                .frame(height: 12).padding(.horizontal, 20)

                if !healthNote.isEmpty {
                    HStack(spacing: 6) {
                        Text(healthNote).font(.system(size: 11, weight: .medium))
                            .foregroundColor(healthNote.contains("⚠") ? .orange : accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 12)
                }

                Text("Range is ±5% estimate based on typical preparation variation")
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(themeManager.current == .dark ?
                          Color(red: 0.12, green: 0.12, blue: 0.16) :
                          themeManager.current.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 24)
                        .stroke(themeManager.current == .dark ?
                                Color.white.opacity(0.08) :
                                themeManager.current.cardBorder, lineWidth: 1))
            )
            .padding(.horizontal, 28)
            // 进场：从下方滑入 + 轻微缩放 + 淡入
            .offset(y: appeared ? 0 : 60)
            .scaleEffect(appeared ? 1 : 0.94, anchor: .bottom)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            appeared = false
        }
        // 等动画结束再回调
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            onDismiss()
        }
    }
}



struct CaloriesBigRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let item: NutritionItem
    var onTap: (() -> Void)? = nil

    var displayUnit: String {
        Double(item.unit) != nil || item.unit.isEmpty ? "kcal" : item.unit
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.value)
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    HStack(spacing: 4) {
                        Text(displayUnit.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange).kerning(2)
                        Text("·").foregroundColor(themeManager.current.secondaryText)
                        Text("CALORIES")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(themeManager.current.secondaryText).kerning(1)
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 10)).foregroundColor(.orange.opacity(0.5))
                    }
                }
                Spacer()
                Image(systemName: "flame.fill").font(.system(size: 36))
                    .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .bottom, endPoint: .top))
                    .opacity(0.6)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}


struct NutrientFlatCell: View {
    @EnvironmentObject var themeManager: ThemeManager
    let item: NutritionItem
    var onTap: (() -> Void)? = nil

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
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor).kerning(0.5)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 7)).foregroundColor(accentColor.opacity(0.5))
                }
                HStack(alignment: .bottom, spacing: 2) {
                    Text(item.value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                        .minimumScaleFactor(0.7).lineLimit(1)
                    Text(displayUnit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(themeManager.current.secondaryText)
                        .padding(.bottom, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}



struct CaloriesHighlightCard: View {
    let item: NutritionItem
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.red.opacity(0.3), .orange.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 60, height: 60)
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
        .background(RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [.red.opacity(0.1), .orange.opacity(0.05)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.2), lineWidth: 1)))
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
        .background(RoundedRectangle(cornerRadius: 12).fill(item.color.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(item.color.opacity(0.2), lineWidth: 1)))
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
