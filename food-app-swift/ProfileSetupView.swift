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
        ("1", "Sedentary", "Little to no exercise"),
        ("2", "Lightly Active", "Exercise 1-3 days/week"),
        ("3", "Active", "Exercise 3-5 days/week"),
        ("4", "Very Active", "Exercise 6-7 days/week")
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

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            if !isEditMode {
                                HStack(spacing: 8) {
                                    ForEach(1...3, id: \.self) { step in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(step <= 2 ? Color.orange : themeManager.current.cardBorder)
                                            .frame(height: 6)
                                    }
                                }
                                .padding(.horizontal, 80)
                            }
                            VStack(spacing: 8) {
                                Text(isEditMode ? "Edit Your Profile" : "Complete Your Profile")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text(isEditMode ? "Update your nutrition preferences" : "Help us personalize your nutrition journey")
                                    .font(.subheadline).foregroundColor(themeManager.current.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)

                        if showValidationErrors && !validationMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(validationMessages, id: \.self) { message in
                                    HStack {
                                        Image(systemName: "exclamationmark.circle.fill").foregroundColor(.yellow).font(.caption)
                                        Text(message).font(.caption).foregroundColor(.yellow)
                                    }
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3), lineWidth: 1)))
                            .padding(.horizontal).transition(.opacity)
                        }

                        // Personal Info
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeader(title: "Personal Information", icon: "person.fill", color: .orange)
                                .environmentObject(themeManager)

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Age").font(.subheadline).foregroundColor(themeManager.current.primaryText)
                                    Spacer()
                                    Text("\(Int(age)) years").font(.headline).foregroundColor(ageError ? .red : .orange)
                                }
                                Slider(value: $age, in: 10...120, step: 1).accentColor(ageError ? .red : .orange)
                                    .onChange(of: age) { _, _ in ageError = age < 10 || age > 120; updateValidationState() }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(themeManager.current.cardBackground)
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(ageError ? Color.red.opacity(0.5) : themeManager.current.cardBorder, lineWidth: 1)))

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Gender").font(.subheadline).foregroundColor(themeManager.current.primaryText)
                                    if genderError { Text("(Required)").font(.caption).foregroundColor(.red) }
                                }
                                HStack(spacing: 12) {
                                    ForEach(genderOptions, id: \.self) { option in
                                        GenderButton(title: option, isSelected: gender == option,
                                                     hasError: genderError && gender.isEmpty,
                                                     action: { gender = option; genderError = false; updateValidationState() })
                                            .environmentObject(themeManager)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Activity Level
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeader(title: "Activity Level", icon: "figure.run", color: .orange)
                                .environmentObject(themeManager)
                            VStack(spacing: 12) {
                                ForEach(activityOptions, id: \.0) { option in
                                    ActivityLevelCard(level: option.0, title: option.1, description: option.2,
                                                      isSelected: activityLevel == option.0,
                                                      action: { activityLevel = option.0 })
                                        .environmentObject(themeManager)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Nutrition Goals
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeader(title: "Nutrition Goals", icon: "target", color: .orange)
                                .environmentObject(themeManager)

                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Daily Calorie Target").font(.subheadline)
                                        .foregroundColor(themeManager.current.primaryText)
                                    Spacer()
                                    Text("\(Int(calorieTarget)) kcal").font(.headline)
                                        .foregroundColor(calorieError ? .red : .orange)
                                }
                                Slider(value: $calorieTarget, in: 1000...5000, step: 50)
                                    .accentColor(calorieError ? .red : .orange)
                                    .onChange(of: calorieTarget) { _, _ in
                                        calorieError = calorieTarget < 1000 || calorieTarget > 5000
                                        updateValidationState()
                                    }
                                HStack {
                                    Text("1000").font(.caption).foregroundColor(themeManager.current.secondaryText)
                                    Spacer()
                                    Text("5000").font(.caption).foregroundColor(themeManager.current.secondaryText)
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 12).fill(themeManager.current.cardBackground)
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(calorieError ? Color.red.opacity(0.5) : themeManager.current.cardBorder, lineWidth: 1)))

                            VStack(alignment: .leading, spacing: 16) {
                                Text("Dietary Preferences (Optional)").font(.subheadline)
                                    .foregroundColor(themeManager.current.primaryText)
                                VStack(spacing: 12) {
                                    DietaryToggle(title: "Vegetarian", description: "No meat or fish", icon: "leaf.fill", isOn: $isVegetarian)
                                        .environmentObject(themeManager)
                                    DietaryToggle(title: "Keto", description: "Low carb, high fat", icon: "drop.fill", isOn: $isKeto)
                                        .environmentObject(themeManager)
                                    DietaryToggle(title: "Gluten-Free", description: "No gluten products", icon: "exclamationmark.triangle.fill", isOn: $isGlutenFree)
                                        .environmentObject(themeManager)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Save Button
                        VStack(spacing: 8) {
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if validateForm() { saveProfile() }
                            }) {
                                HStack {
                                    if isSaving {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text(isEditMode ? "Save Changes" : "Complete Setup").fontWeight(.semibold)
                                        Image(systemName: isEditMode ? "checkmark" : "arrow.right")
                                    }
                                }
                                .foregroundColor(isFormValid ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(LinearGradient(
                                    gradient: Gradient(colors: isFormValid ? [.orange, .orange.opacity(0.8)] : [.gray, .gray.opacity(0.8)]),
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .cornerRadius(12)
                                .shadow(color: isFormValid ? .orange.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
                            }
                            .disabled(isSaving)

                            if !isFormValid && !showValidationErrors {
                                Text("Complete all required fields to continue")
                                    .font(.caption).foregroundColor(themeManager.current.secondaryText)
                            }
                        }
                        .padding(.horizontal)

                        if !isEditMode {
                            Button(action: { SessionManager.shared.clearNewRegistrationFlag(); dismiss() }) {
                                Text("Skip for now").font(.caption).foregroundColor(themeManager.current.secondaryText)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundColor(themeManager.current.secondaryText)
                    }
                }
            }
            .onAppear { loadExistingProfile() }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: { Text(errorMessage) }
            .overlay(
                ZStack {
                    if showLoadingOverlay {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        VStack(spacing: 20) {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.5)
                            Text(loadingMessage).font(.headline).foregroundColor(.white)
                            Text("Syncing with server...").font(.caption).foregroundColor(.gray)
                        }
                        .padding(40)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.8))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1)))
                    }
                }
                .animation(.easeInOut, value: showLoadingOverlay)
            )
        }
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
        let profile = UserProfile(_id: existingProfile?._id, user_id: userId, age: Int(age), gender: gender,
                                   activity_level: activityLevel, calorie_target: Int(calorieTarget),
                                   is_vegetarian: isVegetarian, is_keto: isKeto, is_gluten_free: isGlutenFree, updated_at: nil)
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

// MARK: - Supporting Views

struct GenderButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let isSelected: Bool
    var hasError: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline).fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .black : themeManager.current.primaryText)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.orange : themeManager.current.inputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(hasError ? Color.red.opacity(0.5) : (isSelected ? Color.clear : themeManager.current.cardBorder), lineWidth: 1)))
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
                        .fill(isSelected ? Color.orange : themeManager.current.inputBackground)
                        .frame(width: 40, height: 40)
                    Text(level).font(.headline)
                        .foregroundColor(isSelected ? .black : themeManager.current.primaryText)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(themeManager.current.primaryText)
                    Text(description).font(.caption)
                        .foregroundColor(themeManager.current.secondaryText)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill").foregroundColor(.orange) }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? themeManager.current.cardBackground : themeManager.current.cardBackground)
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
