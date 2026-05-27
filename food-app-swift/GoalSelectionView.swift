//
//  GoalSelectionView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//


import SwiftUI

struct GoalSelectionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    let healthProfile: HealthProfile
    var onComplete: ((NutritionPlan) -> Void)?

    @State private var selectedGoals: Set<String> = []
    @State private var isGenerating = false
    @State private var generatedPlan: NutritionPlan?
    @State private var showPlan = false
    @State private var showPlanGenerator = false
    @State private var nutritionPlanForGenerator: NutritionPlan?
    @State private var errorMsg = ""
    @State private var showError = false
    @State private var generatingStep = 0
    let generatingSteps = [
        "Analysing your health profile…",
        "Calculating your nutrient targets…",
        "Personalising your dietary advice…",
        "Finalising your plan…"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                if isGenerating {
                    generatingView
                } else if showPlan, let plan = generatedPlan {
                    planResultView(plan: plan)
                } else {
                    goalPickerView
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMsg) }
            .fullScreenCover(isPresented: $showPlanGenerator, onDismiss: completeOnboardingIfNeeded) {
                if let plan = nutritionPlanForGenerator {
                    PlanGeneratorView(
                        nutritionPlan: plan,
                        healthProfile: healthProfile,
                        onGenerated: { _ in showPlanGenerator = false }
                    )
                    .environmentObject(themeManager)
                }
            }
        }
    }

    private func completeOnboardingIfNeeded() {
        guard let plan = nutritionPlanForGenerator else { return }
        onComplete?(plan)
        dismiss()
    }

    // MARK: - Goal Picker

    var goalPickerView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Health Goals")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text("Select all that apply — we'll tailor your plan")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.current.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(HealthGoal.allCases, id: \.rawValue) { goal in
                        let isSelected = selectedGoals.contains(goal.rawValue)
                        Button(action: {
                            withAnimation(.spring(response: 0.2)) {
                                if isSelected { selectedGoals.remove(goal.rawValue) }
                                else { selectedGoals.insert(goal.rawValue) }
                            }
                        }) {
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(isSelected
                                              ? (themeManager.current == .dark ? Color.white : Color.black)
                                              : themeManager.current.inputBackground)
                                        .frame(width: 52, height: 52)
                                    Image(systemName: goal.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(isSelected
                                            ? (themeManager.current == .dark ? .black : .white)
                                            : themeManager.current.secondaryText)
                                }
                                Text(goal.displayName)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(themeManager.current.primaryText)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .padding(.horizontal, 10)
                            .background(themeManager.current.cardBackground)
                            .cornerRadius(18)
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .stroke(isSelected
                                        ? (themeManager.current == .dark ? Color.white : Color.black)
                                        : themeManager.current.cardBorder,
                                        lineWidth: isSelected ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            // CTA
            VStack(spacing: 0) {
                Divider().background(themeManager.current.cardBorder)
                Button(action: generatePlan) {
                    Text(selectedGoals.isEmpty ? "Skip — Use General Plan" : "Generate My Plan")
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

    // MARK: - Generating View

    var generatingView: some View {
        VStack(spacing: 32) {
            Spacer()
            // Animated ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.1), lineWidth: 10)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: CGFloat(generatingStep + 1) / CGFloat(generatingSteps.count))
                    .stroke(themeManager.current == .dark ? Color.white : Color.black,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: generatingStep)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundColor(themeManager.current.primaryText)
            }

            VStack(spacing: 8) {
                Text("Creating Your Plan")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text(generatingSteps[min(generatingStep, generatingSteps.count - 1)])
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.current.secondaryText)
                    .animation(.easeInOut, value: generatingStep)
            }

            // Step dots
            HStack(spacing: 8) {
                ForEach(0..<generatingSteps.count, id: \.self) { i in
                    Circle()
                        .fill(i <= generatingStep
                              ? (themeManager.current == .dark ? Color.white : Color.black)
                              : Color.gray.opacity(0.2))
                        .frame(width: 8, height: 8)
                        .animation(.spring(), value: generatingStep)
                }
            }
            Spacer()
        }
    }

    // MARK: - Plan Result View

    func planResultView(plan: NutritionPlan) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Personalised Plan")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                        Text("Based on your health profile and goals")
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                    .padding(.top, 24)

                    // Daily targets
                    dailyTargetsCard(plan: plan)

                    // AI Advice
                    if !plan.aiAdvice.isEmpty {
                        adviceCard(plan: plan)
                    }

                    // Foods to eat
                    if !plan.foodsToEat.isEmpty {
                        foodListCard(title: "Recommended Foods", items: plan.foodsToEat, color: .green, icon: "checkmark.circle.fill")
                    }

                    // Foods to avoid
                    if !plan.foodsToAvoid.isEmpty {
                        foodListCard(title: "Foods to Limit", items: plan.foodsToAvoid, color: .red, icon: "xmark.circle.fill")
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
            }

            // CTA
            VStack(spacing: 0) {
                Divider().background(themeManager.current.cardBorder)
                Button(action: {
                    nutritionPlanForGenerator = plan
                    showPlanGenerator = true
                }) {
                    Text("Create My Weekly Meal Plan →")
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

    func dailyTargetsCard(plan: NutritionPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Targets")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)

            // Calorie big number
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(plan.dailyCalories)")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text("kcal / day")
                    .font(.system(size: 16))
                    .foregroundColor(themeManager.current.secondaryText)
            }

            // Macros grid
            HStack(spacing: 12) {
                macroCell("Protein", value: "\(plan.proteinG)g", color: Color(red: 0.93, green: 0.36, blue: 0.36))
                macroCell("Carbs", value: "\(plan.carbsG)g", color: Color(red: 0.95, green: 0.61, blue: 0.20))
                macroCell("Fat", value: "\(plan.fatG)g", color: Color(red: 0.35, green: 0.62, blue: 0.93))
                macroCell("Fiber", value: "\(plan.fiberG)g", color: Color(red: 0.55, green: 0.35, blue: 0.85))
            }
        }
        .padding(18)
        .background(themeManager.current.cardBackground)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func macroCell(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(themeManager.current.primaryText)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(12)
    }

    func adviceCard(plan: NutritionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.current.primaryText)
                Text("AI Health Insights")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
            }
            Text(plan.aiAdvice)
                .font(.system(size: 14))
                .foregroundColor(themeManager.current.secondaryText)
                .lineSpacing(4)
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func foodListCard(title: String, items: [String], color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
            VStack(spacing: 6) {
                ForEach(items.prefix(6), id: \.self) { item in
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundColor(color)
                        Text(item)
                            .font(.system(size: 14))
                            .foregroundColor(themeManager.current.primaryText)
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    // MARK: - Generate

    func generatePlan() {
        isGenerating = true
        generatingStep = 0

        // Animate through steps
        for i in 1..<generatingSteps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) {
                withAnimation { generatingStep = i }
            }
        }

        HealthAPIManager.shared.generateNutritionTargets(
            profile: healthProfile,
            goals: Array(selectedGoals)
        ) { plan, err in
            isGenerating = false
            if let plan = plan {
                generatedPlan = plan
                withAnimation(.spring()) { showPlan = true }
            } else {
                errorMsg = err ?? "Failed to generate plan. Please try again."
                showError = true
            }
        }
    }
}
