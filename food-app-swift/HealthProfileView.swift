//
//  HealthProfileView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//
import SwiftUI

struct HealthProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @Environment(\.dismiss) var dismiss

    var onComplete: ((HealthProfile) -> Void)?

    // Step control
    @State private var currentStep = 0
    let totalSteps = 4

    // Step 1 — Body metrics
    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70
    @State private var age: Int = 30
    @State private var sex: String = ""

    // Step 2 — Clinical markers (all optional)
    @State private var hasBP = false
    @State private var systolicBP: Double = 120
    @State private var diastolicBP: Double = 80
    @State private var hasBloodSugar = false
    @State private var bloodSugar: Double = 5.0
    @State private var hasCholesterol = false
    @State private var cholesterol: Double = 4.5
    @State private var hasTriglycerides = false
    @State private var triglycerides: Double = 1.2

    // Step 3 — Diet preferences & allergens
    @State private var selectedDietary: Set<String> = []
    @State private var selectedAllergens: Set<String> = []

    // Step 4 — Review & save
    @State private var isSaving = false
    @State private var errorMsg = ""
    @State private var showError = false

    var bmi: Double {
        let h = heightCm / 100
        return weightKg / (h * h)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    progressHeader
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            switch currentStep {
                            case 0: step1Body
                            case 1: step2Clinical
                            case 2: step3Diet
                            case 3: step4Review
                            default: EmptyView()
                            }
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    navigationButtons
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMsg) }
        }
    }

    // MARK: - Progress Header

    var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: {
                    if currentStep > 0 { withAnimation(.spring()) { currentStep -= 1 } }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(currentStep == 0 ? .clear : themeManager.current.primaryText)
                        .frame(width: 36, height: 36)
                        .background(currentStep == 0 ? Color.clear : themeManager.current.inputBackground)
                        .cornerRadius(10)
                }
                .disabled(currentStep == 0)

                Spacer()

                VStack(spacing: 2) {
                    Text("Health Profile")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text("Step \(currentStep + 1) of \(totalSteps)")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }

                Spacer()
                // Balance the back button
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Step dots
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentStep
                              ? (themeManager.current == .dark ? Color.white : Color.black)
                              : themeManager.current.cardBorder)
                        .frame(width: i == currentStep ? 28 : 8, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Step 1: Body Metrics

    var step1Body: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(icon: "figure.stand", title: "Body Metrics",
                      subtitle: "We'll calculate your BMI and daily energy needs")

            // BMI preview card
            if !sex.isEmpty {
                bmiCard
            }

            // Height
            MetricInputCard(
                label: "Height", unit: "cm",
                value: $heightCm, range: 100...220, step: 1,
                format: { "\(Int($0))" }
            )

            // Weight
            MetricInputCard(
                label: "Weight", unit: "kg",
                value: $weightKg, range: 30...250, step: 0.5,
                format: { String(format: "%.1f", $0) }
            )

            // Age
            MetricInputCard(
                label: "Age", unit: "yrs",
                value: Binding(get: { Double(age) }, set: { age = Int($0) }),
                range: 12...100, step: 1,
                format: { "\(Int($0))" }
            )

            // Sex
            VStack(alignment: .leading, spacing: 10) {
                Text("Biological Sex")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                HStack(spacing: 10) {
                    ForEach(["Male", "Female", "Other"], id: \.self) { option in
                        Button(action: { sex = option.lowercased() }) {
                            Text(option)
                                .font(.system(size: 14, weight: sex == option.lowercased() ? .bold : .regular))
                                .foregroundColor(sex == option.lowercased()
                                    ? (themeManager.current == .dark ? .black : .white)
                                    : themeManager.current.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(sex == option.lowercased()
                                          ? (themeManager.current == .dark ? Color.white : Color.black)
                                          : themeManager.current.inputBackground))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.current.cardBorder, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    var bmiCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your BMI")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                    .textCase(.uppercase)
                    .tracking(0.5)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", bmi))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(themeManager.current.primaryText)
                    Text(bmiCategoryLabel().0)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(bmiCategoryLabel().1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(bmiCategoryLabel().1.opacity(0.12))
                        .cornerRadius(8)
                }
            }
            Spacer()
            // BMI gauge
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.12), lineWidth: 8)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: min(bmi / 40.0, 1.0))
                    .stroke(bmiCategoryLabel().1, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func bmiCategoryLabel() -> (String, Color) {
        switch bmi {
        case ..<18.5: return ("Underweight", .blue)
        case 18.5..<25: return ("Normal", .green)
        case 25..<30: return ("Overweight", .orange)
        default: return ("Obese", .red)
        }
    }

    // MARK: - Step 2: Clinical Markers

    var step2Clinical: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(icon: "heart.fill", title: "Clinical Markers",
                      subtitle: "Optional — skip if you don't have these values")

            clinicalToggleCard(
                title: "Blood Pressure",
                subtitle: "Normal: 90–120 / 60–80 mmHg",
                icon: "waveform.path.ecg",
                isOn: $hasBP
            ) {
                VStack(spacing: 12) {
                    sliderCard(label: "Systolic (upper)", value: $systolicBP,
                               range: 80...200, step: 1,
                               display: "\(Int(systolicBP)) mmHg",
                               warningRange: 120...139)
                    sliderCard(label: "Diastolic (lower)", value: $diastolicBP,
                               range: 40...130, step: 1,
                               display: "\(Int(diastolicBP)) mmHg",
                               warningRange: 80...89)
                }
            }

            clinicalToggleCard(
                title: "Fasting Blood Sugar",
                subtitle: "Normal: 3.9–5.5 mmol/L",
                icon: "drop.fill",
                isOn: $hasBloodSugar
            ) {
                sliderCard(label: "Blood Sugar", value: $bloodSugar,
                           range: 2.0...15.0, step: 0.1,
                           display: String(format: "%.1f mmol/L", bloodSugar),
                           warningRange: 5.6...6.9)
            }

            clinicalToggleCard(
                title: "Total Cholesterol",
                subtitle: "Normal: < 5.2 mmol/L",
                icon: "chart.bar.fill",
                isOn: $hasCholesterol
            ) {
                sliderCard(label: "Cholesterol", value: $cholesterol,
                           range: 1.0...10.0, step: 0.1,
                           display: String(format: "%.1f mmol/L", cholesterol),
                           warningRange: 5.2...6.2)
            }

            clinicalToggleCard(
                title: "Triglycerides",
                subtitle: "Normal: < 1.7 mmol/L",
                icon: "drop.triangle.fill",
                isOn: $hasTriglycerides
            ) {
                sliderCard(label: "Triglycerides", value: $triglycerides,
                           range: 0.2...8.0, step: 0.1,
                           display: String(format: "%.1f mmol/L", triglycerides),
                           warningRange: 1.7...2.3)
            }
        }
    }

    // MARK: - Step 3: Dietary Preferences & Allergens

    var step3Diet: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepTitle(icon: "leaf.fill", title: "Diet & Allergens",
                      subtitle: "Help us build a meal plan that works for you")

            // Dietary preferences
            VStack(alignment: .leading, spacing: 12) {
                Text("Dietary Preferences")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(DietaryOption.all) { option in
                        let isSelected = selectedDietary.contains(option.id)
                        Button(action: {
                            if option.id == "no_restriction" {
                                selectedDietary = isSelected ? [] : ["no_restriction"]
                            } else {
                                selectedDietary.remove("no_restriction")
                                if isSelected { selectedDietary.remove(option.id) }
                                else { selectedDietary.insert(option.id) }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: option.icon)
                                    .font(.system(size: 13))
                                    .foregroundColor(isSelected
                                        ? (themeManager.current == .dark ? .black : .white)
                                        : .green)
                                    .frame(width: 20)
                                Text(option.displayName)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected
                                        ? (themeManager.current == .dark ? .black : .white)
                                        : themeManager.current.primaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected
                                      ? (themeManager.current == .dark ? Color.white : Color.black)
                                      : themeManager.current.inputBackground))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(themeManager.current.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Allergens
            VStack(alignment: .leading, spacing: 12) {
                Text("Allergens to Avoid")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(themeManager.current.primaryText)
                Text("We'll exclude these from your meal plan")
                    .font(.system(size: 13))
                    .foregroundColor(themeManager.current.secondaryText)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(AllergenOption.all) { allergen in
                        let isSelected = selectedAllergens.contains(allergen.id)
                        Button(action: {
                            if isSelected { selectedAllergens.remove(allergen.id) }
                            else { selectedAllergens.insert(allergen.id) }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "xmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(isSelected ? .red : themeManager.current.secondaryText)
                                Text(allergen.displayName)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(themeManager.current.primaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.red.opacity(0.06) : themeManager.current.inputBackground))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.red.opacity(0.3) : themeManager.current.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Step 4: Review

    var step4Review: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle(icon: "checkmark.circle.fill", title: "Review Profile",
                      subtitle: "Confirm your health information before we create your plan")

            // Body
            reviewCard(title: "Body Metrics") {
                reviewRow("Height", value: "\(Int(heightCm)) cm")
                reviewRow("Weight", value: String(format: "%.1f kg", weightKg))
                reviewRow("Age", value: "\(age) years")
                reviewRow("Sex", value: sex.capitalized)
                reviewRow("BMI", value: String(format: "%.1f — %@", bmi, bmiCategoryLabel().0))
            }

            // Clinical
            if hasBP || hasBloodSugar || hasCholesterol || hasTriglycerides {
                reviewCard(title: "Clinical Markers") {
                    if hasBP {
                        reviewRow("Blood Pressure", value: "\(Int(systolicBP))/\(Int(diastolicBP)) mmHg")
                    }
                    if hasBloodSugar {
                        reviewRow("Blood Sugar", value: String(format: "%.1f mmol/L", bloodSugar))
                    }
                    if hasCholesterol {
                        reviewRow("Cholesterol", value: String(format: "%.1f mmol/L", cholesterol))
                    }
                    if hasTriglycerides {
                        reviewRow("Triglycerides", value: String(format: "%.1f mmol/L", triglycerides))
                    }
                }
            }

            // Diet
            reviewCard(title: "Diet & Allergens") {
                reviewRow("Preferences", value: selectedDietary.isEmpty ? "No restriction"
                          : selectedDietary.joined(separator: ", "))
                reviewRow("Allergens", value: selectedAllergens.isEmpty ? "None"
                          : selectedAllergens.joined(separator: ", "))
            }
        }
    }

    // MARK: - Navigation Buttons

    var navigationButtons: some View {
        VStack(spacing: 0) {
            Divider().background(themeManager.current.cardBorder)
            HStack(spacing: 12) {
                if currentStep < totalSteps - 1 {
                    // Skip (only step 1 cannot be skipped)
                    if currentStep > 0 {
                        Button(action: {
                            withAnimation(.spring()) { currentStep += 1 }
                        }) {
                            Text("Skip")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(themeManager.current.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(themeManager.current.inputBackground)
                                .cornerRadius(16)
                        }
                    }
                    // Next
                    Button(action: {
                        if canProceed {
                            withAnimation(.spring()) { currentStep += 1 }
                        }
                    }) {
                        Text("Next")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canProceed
                                ? (themeManager.current == .dark ? Color.white : Color.black)
                                : Color.gray.opacity(0.3))
                            .cornerRadius(16)
                    }
                    .disabled(!canProceed)
                } else {
                    // Final save
                    Button(action: saveProfile) {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(
                                    tint: themeManager.current == .dark ? .black : .white))
                            }
                            Text(isSaving ? "Saving…" : "Save & Continue")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(themeManager.current == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(themeManager.current == .dark ? Color.white : Color.black)
                        .cornerRadius(16)
                    }
                    .disabled(isSaving)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    var canProceed: Bool {
        switch currentStep {
        case 0: return !sex.isEmpty
        default: return true
        }
    }

    // MARK: - Save

    func saveProfile() {
        isSaving = true
        let userId = session.userID.isEmpty
            ? UserDefaults.standard.string(forKey: "user_id") ?? ""
            : session.userID

        let profile = HealthProfile(
            userId: userId,
            heightCm: heightCm,
            weightKg: weightKg,
            age: age,
            sex: sex,
            systolicBP: hasBP ? Int(systolicBP) : nil,
            diastolicBP: hasBP ? Int(diastolicBP) : nil,
            fastingBloodSugar: hasBloodSugar ? bloodSugar : nil,
            totalCholesterol: hasCholesterol ? cholesterol : nil,
            triglycerides: hasTriglycerides ? triglycerides : nil,
            dietaryPreferences: Array(selectedDietary),
            allergens: Array(selectedAllergens)
        )

        HealthAPIManager.shared.saveHealthProfile(profile) { success, err in
            self.isSaving = false
            if success {
                UserDefaults.standard.set(true, forKey: "health_profile_complete")
                self.onComplete?(profile)
                self.dismiss()
            } else {
                self.errorMsg = err ?? "Failed to save. Please try again."
                self.showError = true
            }
        }
    }

    // MARK: - Reusable Sub-components

    func stepTitle(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(themeManager.current == .dark ? .white : .black)
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
            }
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(themeManager.current.secondaryText)
        }
        .padding(.top, 8)
    }

    func sliderCard(label: String, value: Binding<Double>, range: ClosedRange<Double>,
                    step: Double, display: String, warningRange: ClosedRange<Double>? = nil) -> some View {
        let isWarning = warningRange.map { value.wrappedValue >= $0.lowerBound && value.wrappedValue <= $0.upperBound } ?? false
        let isDanger = warningRange.map { value.wrappedValue > $0.upperBound } ?? false
        let accentColor: Color = isDanger ? .red : isWarning ? .orange : (themeManager.current == .dark ? .white : .black)

        return VStack(spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text(display)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
            }
            Slider(value: value, in: range, step: step)
                .accentColor(accentColor)
            if isWarning || isDanger {
                HStack(spacing: 4) {
                    Image(systemName: isDanger ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(accentColor)
                    Text(isDanger ? "Above normal range" : "Borderline — consult your doctor")
                        .font(.system(size: 11))
                        .foregroundColor(accentColor)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(isWarning || isDanger ? accentColor.opacity(0.3) : themeManager.current.cardBorder, lineWidth: 1))
    }

    func clinicalToggleCard<Content: View>(title: String, subtitle: String, icon: String,
                                           isOn: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isOn.wrappedValue ? (themeManager.current == .dark ? .white : .black) : themeManager.current.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(isOn.wrappedValue ? (themeManager.current == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)) : themeManager.current.inputBackground)
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(themeManager.current.primaryText)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .toggleStyle(SwitchToggleStyle(tint: themeManager.current == .dark ? .white : .black))
                    .labelsHidden()
            }
            if isOn.wrappedValue {
                content()
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(themeManager.current.cardBorder, lineWidth: 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOn.wrappedValue)
    }

    func reviewCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(themeManager.current.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func reviewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(themeManager.current.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.current.primaryText)
        }
    }
}

// MARK: - MetricInputCard（滑块 + 可直接输入）

struct MetricInputCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let label: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    @State private var textInput: String = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                // 点击数值可直接输入
                HStack(spacing: 4) {
                    if isEditing {
                        TextField("", text: $textInput)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .focused($focused)
                            .onSubmit { commitInput() }
                            .onChange(of: focused) { _, isFocused in
                                if !isFocused { commitInput() }
                            }
                    } else {
                        Text(format(value))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(themeManager.current.primaryText)
                            .onTapGesture { startEditing() }
                    }
                    Text(unit)
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.current.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(themeManager.current.inputBackground)
                .cornerRadius(10)
                .onTapGesture { startEditing() }
            }

            Slider(value: $value, in: range, step: step)
                .accentColor(themeManager.current == .dark ? .white : .black)
                .onChange(of: value) { _, newVal in
                    if !isEditing {
                        textInput = format(newVal)
                    }
                }

            HStack {
                Text("\(Int(range.lowerBound))\(unit)")
                    .font(.caption2)
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text("\(Int(range.upperBound))\(unit)")
                    .font(.caption2)
                    .foregroundColor(themeManager.current.secondaryText)
            }
        }
        .padding(16)
        .background(themeManager.current.cardBackground)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(themeManager.current.cardBorder, lineWidth: 1))
        .onAppear { textInput = format(value) }
    }

    func startEditing() {
        textInput = format(value)
        isEditing = true
        focused = true
    }

    func commitInput() {
        if let v = Double(textInput) {
            let clamped = min(max(v, range.lowerBound), range.upperBound)
            // snap to step
            let steps = round((clamped - range.lowerBound) / step)
            value = range.lowerBound + steps * step
        }
        textInput = format(value)
        isEditing = false
    }
}
