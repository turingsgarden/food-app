//
//  PlanGeneratorView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/12/26.
//


import SwiftUI

struct PlanGeneratorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let nutritionPlan: NutritionPlan
    let healthProfile: HealthProfile
    var onGenerated: ((WeeklyMealPlan) -> Void)?

    @State private var selectedDays: Int = 7
    @State private var selectedMeals: Int = 3
    @State private var isGenerating = false
    @State private var generatingText = "Starting…"
    @State private var errorMsg = ""
    @State private var showError = false
    @Environment(\.dismiss) var dismiss

    let dayOptions = [1, 3, 5, 7]
    let mealOptions = [1, 2, 3]

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                if isGenerating {
                    generatingView
                } else {
                    settingsView
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMsg) }
        }
    }

    // MARK: - Settings

    var settingsView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                        .frame(width: 34, height: 34)
                        .background(themeManager.current.inputBackground)
                        .cornerRadius(10)
                }
                Spacer()
                Text("New Meal Plan")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Spacer()
                Color.clear.frame(width: 34, height: 34)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Start date info
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 18))
                            .foregroundColor(themeManager.current.primaryText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Starting today")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(themeManager.current.primaryText)
                            Text(todayString())
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(themeManager.current.cardBackground)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))

                    // Days selector
                    VStack(alignment: .leading, spacing: 14) {
                        Text("How many days?")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(themeManager.current.primaryText)

                        HStack(spacing: 10) {
                            ForEach(dayOptions, id: \.self) { d in
                                dayButton(d, label: "\(d)d")
                            }
                        }

                        // Custom stepper
                        if !dayOptions.contains(selectedDays) || true {
                            HStack {
                                Text("Custom:")
                                    .font(.system(size: 13))
                                    .foregroundColor(themeManager.current.secondaryText)
                                Spacer()
                                Stepper("\(selectedDays) days", value: $selectedDays, in: 1...7)
                                    .labelsHidden()
                                Text("\(selectedDays) days")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(themeManager.current.primaryText)
                                    .frame(width: 70)
                            }
                        }
                    }
                    .padding(16)
                    .background(themeManager.current.cardBackground)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))

                    // Meals per day selector
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Meals per day?")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(themeManager.current.primaryText)

                        HStack(spacing: 10) {
                            ForEach(mealOptions, id: \.self) { m in
                                mealButton(m)
                            }
                        }

                        // Show which meals
                        let mealNames = mealNames(for: selectedMeals)
                        Text("Includes: \(mealNames)")
                            .font(.system(size: 12))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                    .padding(16)
                    .background(themeManager.current.cardBackground)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))

                    // Summary
                    summaryCard

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }

            // Generate button
            VStack(spacing: 0) {
                Divider().background(themeManager.current.cardBorder)
                Button(action: generate) {
                    Text("Generate Plan")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(themeManager.current == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(themeManager.current == .dark ? Color.white : Color.black)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    func dayButton(_ days: Int, label: String) -> some View {
        let isSelected = selectedDays == days
        return Button(action: { withAnimation(.spring()) { selectedDays = days } }) {
            Text(label)
                .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected
                    ? (themeManager.current == .dark ? .black : .white)
                    : themeManager.current.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? (themeManager.current == .dark ? Color.white : Color.black)
                          : themeManager.current.inputBackground))
        }
        .buttonStyle(.plain)
    }

    func mealButton(_ meals: Int) -> some View {
        let isSelected = selectedMeals == meals
        let label = meals == 1 ? "1 meal" : meals == 2 ? "2 meals" : "3 meals"
        return Button(action: { withAnimation(.spring()) { selectedMeals = meals } }) {
            Text(label)
                .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected
                    ? (themeManager.current == .dark ? .black : .white)
                    : themeManager.current.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? (themeManager.current == .dark ? Color.white : Color.black)
                          : themeManager.current.inputBackground))
        }
        .buttonStyle(.plain)
    }

    var summaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your plan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text("\(selectedDays) days × \(selectedMeals) meals")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text("~\(selectedDays * selectedMeals * nutritionPlan.dailyCalories / 3) kcal total")
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.current.secondaryText)
            }
            Spacer()
            Text("\(selectedDays * selectedMeals)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundColor(themeManager.current.primaryText)
            Text("meals")
                .font(.system(size: 13))
                .foregroundColor(themeManager.current.secondaryText)
        }
        .padding(18)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    // MARK: - Generating

    var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: themeManager.current.primaryText))
                .scaleEffect(1.4)
            VStack(spacing: 8) {
                Text("Building Your Plan")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text(generatingText)
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.current.secondaryText)
                    .animation(.easeInOut, value: generatingText)
            }
            Text("\(selectedDays) days × \(selectedMeals) meals • Starting today")
                .font(.system(size: 12))
                .foregroundColor(themeManager.current.secondaryText)
            Spacer()
        }
    }

    // MARK: - Logic

    func generate() {
        isGenerating = true
        let steps = ["Creating diverse menus…", "Planning day by day…", "Calculating nutrition…", "Finalising your plan…"]
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 2) {
                generatingText = step
            }
        }

        let userId = SessionManager.shared.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : SessionManager.shared.userID

        HealthAPIManager.shared.generateWeeklyMealPlan(
            userId: userId,
            nutritionPlan: nutritionPlan,
            healthProfile: healthProfile,
            days: selectedDays,
            mealsPerDay: selectedMeals,
            onProgress: { msg in generatingText = msg }
        ) { plan, err in
            isGenerating = false
            if let plan = plan {
                onGenerated?(plan)
                dismiss()
            } else {
                errorMsg = err ?? "Failed to generate plan"
                showError = true
            }
        }
    }

    func todayString() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: Date())
    }

    func mealNames(for count: Int) -> String {
        switch count {
        case 1: return "Lunch"
        case 2: return "Breakfast & Dinner"
        default: return "Breakfast, Lunch & Dinner"
        }
    }
}
