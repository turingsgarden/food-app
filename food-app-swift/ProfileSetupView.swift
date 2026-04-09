//
//  ProfileSetupView.swift
//  food-app-swift
//

import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss

    let existingProfile: UserProfile?

    @State private var age: Double = 25
    @State private var gender: String = ""
    @State private var activityLevel = "2"
    @State private var calorieTarget: Double = 2200
    @State private var isVegetarian = false
    @State private var isKeto = false
    @State private var isGlutenFree = false
    @State private var navigateToDashboard = false
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showLoadingOverlay = false
    @State private var loadingMessage = "Setting up your profile..."
    @State private var showValidationErrors = false
    @State private var genderError = false
    @State private var ageError = false
    @State private var calorieError = false

    var isEditMode: Bool { existingProfile != nil }

    let genderOptions = ["Male", "Female", "Other"]
    let activityOptions = [
        ("1", "Sedentary", "Little to no exercise", "figure.stand"),
        ("2", "Lightly Active", "Exercise 1–3 days/week", "figure.walk"),
        ("3", "Active", "Exercise 3–5 days/week", "figure.run"),
        ("4", "Very Active", "Exercise 6–7 days/week", "bolt.fill")
    ]

    init(existingProfile: UserProfile? = nil) {
        self.existingProfile = existingProfile
    }

    var isFormValid: Bool {
        age >= 10 && age <= 120 && !gender.isEmpty && calorieTarget >= 1000 && calorieTarget <= 5000
    }

    var validationMessages: [String] {
        var messages: [String] = []
        if gender.isEmpty { messages.append("Please select your gender") }
        if age < 10 || age > 120 { messages.append("Age must be between 10 and 120") }
        if calorieTarget < 1000 || calorieTarget > 5000 { messages.append("Calorie target must be between 1000 and 5000") }
        return messages
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {

                        // ── 顶部 Header ──
                        topHeader

                       
                        if showValidationErrors && !validationMessages.isEmpty {
                            validationErrorCard
                        }

                       
                        profileCard {
                            VStack(spacing: 20) {
                                cardHeader(icon: "person.fill", title: "Personal Info")

                                // Age slider
                                ageSliderRow

                                Divider().background(themeManager.current.cardBorder)

                                // Gender selector
                                genderSelectorRow
                            }
                        }


                        profileCard {
                            VStack(spacing: 16) {
                                cardHeader(icon: "figure.run", title: "Activity Level")
                                activityGrid
                            }
                        }


                        profileCard {
                            VStack(spacing: 20) {
                                cardHeader(icon: "flame.fill", title: "Calorie Goal")
                                calorieSliderRow

                                Divider().background(themeManager.current.cardBorder)

                                // Dietary preferences
                                dietarySection
                            }
                        }

                        // ── Save Button ──
                        saveButton

                        if !isEditMode {
                            Button(action: {
                                SessionManager.shared.clearNewRegistrationFlag()
                                dismiss()
                            }) {
                                Text("Skip for now")
                                    .font(.system(size: 14))
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundColor(themeManager.current.secondaryText)
                    }
                }
            }
            .onAppear { loadExistingProfile() }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: { Text(errorMessage) }
            .overlay(loadingOverlay)
        }
    }

    // MARK: - Top Header

    var topHeader: some View {
        VStack(spacing: 10) {

            if !isEditMode {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i <= 1 ? Color.orange : themeManager.current.cardBorder)
                            .frame(width: i == 1 ? 20 : 8, height: 6)
                    }
                }
                .padding(.top, 16)
            }


            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: isEditMode ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
            }
            .padding(.top, isEditMode ? 20 : 8)

            VStack(spacing: 6) {
                Text(isEditMode ? "Edit Profile" : "Set Up Profile")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
                Text(isEditMode ? "Update your nutrition preferences" : "Help us personalize your nutrition journey")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.current.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Validation Error Card

    var validationErrorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(validationMessages, id: \.self) { message in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(themeManager.current.primaryText)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.current.cardBackground)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color.orange.opacity(0.4), lineWidth: 1))
        .transition(.opacity)
    }

    // MARK: - Card Container

    @ViewBuilder
    func profileCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(18)
        .background(themeManager.current.cardBackground)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(themeManager.current.cardBorder, lineWidth: 1))
    }

    func cardHeader(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(themeManager.current.primaryText)
            Spacer()
        }
    }

    // MARK: - Age Slider

    var ageSliderRow: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Age")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text("\(Int(age)) yrs")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(ageError ? .red : .orange)
            }
            Slider(value: $age, in: 10...120, step: 1)
                .accentColor(ageError ? .red : .orange)
                .onChange(of: age) { _, _ in
                    ageError = age < 10 || age > 120
                    updateValidationState()
                }
            HStack {
                Text("10").font(.caption2).foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text("120").font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
        }
    }

    // MARK: - Gender Selector

    var genderSelectorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gender")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                if genderError {
                    Text("· Required")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                ForEach(genderOptions, id: \.self) { option in
                    Button(action: {
                        gender = option
                        genderError = false
                        updateValidationState()
                    }) {
                        Text(option)
                            .font(.system(size: 14, weight: gender == option ? .semibold : .regular))
                            .foregroundColor(gender == option
                                ? (themeManager.current == .dark ? .black : .white)
                                : themeManager.current.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(gender == option
                                          ? (themeManager.current == .dark ? Color.white : Color.black)
                                          : themeManager.current.inputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(genderError && gender.isEmpty
                                            ? Color.red.opacity(0.4)
                                            : (gender == option ? Color.clear : themeManager.current.cardBorder),
                                            lineWidth: 1)
                            )
                    }
                }
            }
        }
    }



    var activityGrid: some View {
        VStack(spacing: 10) {
            ForEach(activityOptions, id: \.0) { level, title, desc, icon in
                Button(action: { activityLevel = level }) {
                    HStack(spacing: 14) {

                        ZStack {
                            Circle()
                                .fill(activityLevel == level
                                      ? (themeManager.current == .dark ? Color.white : Color.black)
                                      : themeManager.current.inputBackground)
                                .frame(width: 40, height: 40)
                            Image(systemName: icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(activityLevel == level
                                    ? (themeManager.current == .dark ? .black : .white)
                                    : themeManager.current.secondaryText)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(themeManager.current.primaryText)
                            Text(desc)
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.current.secondaryText)
                        }

                        Spacer()


                        ZStack {
                            Circle()
                                .stroke(activityLevel == level ? Color.orange : themeManager.current.cardBorder, lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                            if activityLevel == level {
                                Circle().fill(Color.orange).frame(width: 12, height: 12)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(themeManager.current.inputBackground)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(activityLevel == level ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Calorie Slider

    var calorieSliderRow: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Daily Calorie Target")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text("\(Int(calorieTarget)) kcal")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(calorieError ? .red : .orange)
            }
            Slider(value: $calorieTarget, in: 1000...5000, step: 50)
                .accentColor(calorieError ? .red : .orange)
                .onChange(of: calorieTarget) { _, _ in
                    calorieError = calorieTarget < 1000 || calorieTarget > 5000
                    updateValidationState()
                }
            HStack {
                Text("1,000").font(.caption2).foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text("5,000").font(.caption2).foregroundColor(themeManager.current.secondaryText)
            }
        }
    }

    // MARK: - Dietary Preferences

    var dietarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dietary Preferences")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(themeManager.current.secondaryText)
            VStack(spacing: 10) {
                DietaryToggleRow(title: "Vegetarian", subtitle: "No meat or fish",
                                 icon: "leaf.fill", isOn: $isVegetarian)
                DietaryToggleRow(title: "Keto", subtitle: "Low carb, high fat",
                                 icon: "drop.fill", isOn: $isKeto)
                DietaryToggleRow(title: "Gluten-Free", subtitle: "No gluten products",
                                 icon: "exclamationmark.triangle.fill", isOn: $isGlutenFree)
            }
        }
    }

    // MARK: - Save Button

    var saveButton: some View {
        VStack(spacing: 8) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if validateForm() { saveProfile() }
            }) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: isEditMode ? "checkmark" : "arrow.right")
                        Text(isEditMode ? "Save Changes" : "Complete Setup")
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(isFormValid ? Color.orange : Color.gray.opacity(0.4))
                .cornerRadius(16)
                .shadow(color: isFormValid ? .orange.opacity(0.25) : .clear, radius: 8, y: 4)
            }
            .disabled(isSaving)

            if !isFormValid && !showValidationErrors {
                Text("Complete all required fields to continue")
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.current.secondaryText)
            }
        }
    }

    // MARK: - Loading Overlay

    var loadingOverlay: some View {
        ZStack {
            if showLoadingOverlay {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                    Text(loadingMessage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(36)
                .background(RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.75))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)))
            }
        }
        .animation(.easeInOut, value: showLoadingOverlay)
    }



    func updateValidationState() {
        if showValidationErrors { showValidationErrors = !isFormValid }
    }

    func validateForm() -> Bool {
        genderError = gender.isEmpty
        ageError = age < 10 || age > 120
        calorieError = calorieTarget < 1000 || calorieTarget > 5000
        showValidationErrors = genderError || ageError || calorieError
        return !showValidationErrors
    }

    func loadExistingProfile() {
        guard let profile = existingProfile else { return }
        age = Double(profile.age)
        gender = profile.gender
        activityLevel = profile.activity_level
        calorieTarget = Double(profile.calorie_target)
        isVegetarian = profile.is_vegetarian ?? false
        isKeto = profile.is_keto ?? false
        isGlutenFree = profile.is_gluten_free ?? false
    }

    func saveProfile() {
        guard validateForm() else { return }
        isSaving = true; showLoadingOverlay = true
        loadingMessage = isEditMode ? "Updating your profile..." : "Setting up your profile..."
        let userId = session.userID.isEmpty ? UserDefaults.standard.string(forKey: "user_id") ?? "" : session.userID
        let profile = UserProfile(
            _id: existingProfile?._id, user_id: userId, age: Int(age), gender: gender,
            activity_level: activityLevel, calorie_target: Int(calorieTarget),
            is_vegetarian: isVegetarian, is_keto: isKeto, is_gluten_free: isGlutenFree, updated_at: nil
        )
        profileManager.saveProfile(profile) { success, error in
            self.isSaving = false; self.showLoadingOverlay = false
            if success {
                SessionManager.shared.clearNewRegistrationFlag()
                self.dismiss()
            } else {
                self.errorMessage = error ?? "Failed to save profile. Please try again."
                self.showError = true
            }
        }
    }
}



struct DietaryToggleRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isOn ? Color.orange.opacity(0.12) : themeManager.current.inputBackground)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isOn ? .orange : themeManager.current.secondaryText)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.current.primaryText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(themeManager.current.secondaryText)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(themeManager.current.inputBackground)
        .cornerRadius(14)
    }
}



struct GenderButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let isSelected: Bool
    var hasError: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected
                    ? (themeManager.current == .dark ? .black : .white)
                    : themeManager.current.primaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? (themeManager.current == .dark ? Color.white : Color.black)
                          : themeManager.current.inputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(hasError ? Color.red.opacity(0.5)
                                : (isSelected ? Color.clear : themeManager.current.cardBorder), lineWidth: 1)))
        }
    }
}

struct ActivityLevelCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let level: String; let title: String; let description: String
    let isSelected: Bool; let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isSelected
                              ? (themeManager.current == .dark ? Color.white : Color.black)
                              : themeManager.current.inputBackground)
                        .frame(width: 40, height: 40)
                    Text(level).font(.headline)
                        .foregroundColor(isSelected
                            ? (themeManager.current == .dark ? .black : .white)
                            : themeManager.current.primaryText)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(themeManager.current.primaryText)
                    Text(description).font(.caption)
                        .foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.orange)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.current.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange.opacity(0.5) : themeManager.current.cardBorder, lineWidth: 1)))
        }
    }
}

struct DietaryToggle: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let description: String; let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title3)
                .foregroundColor(isOn ? .orange : themeManager.current.secondaryText).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                    .foregroundColor(themeManager.current.primaryText)
                Text(description).font(.caption)
                    .foregroundColor(themeManager.current.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn).toggleStyle(SwitchToggleStyle(tint: .orange)).labelsHidden()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(themeManager.current.cardBackground)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(themeManager.current.cardBorder, lineWidth: 1)))
    }
}
