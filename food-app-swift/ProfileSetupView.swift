import SwiftUI

struct ProfileSetupView: View {
    @ObservedObject var session = SessionManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @Environment(\.dismiss) var dismiss

    // Existing profile for editing (nil for new setup)
    let existingProfile: UserProfile?
    
    @State private var age: Double = 25
    @State private var gender: String = "Select"
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
    
    // Validation states
    @State private var validationErrors: [String] = []
    @State private var showValidationAlert = false
    @State private var genderError = false
    @State private var ageError = false
    @State private var calorieError = false
    
    // Is this an edit mode?
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
    
    // Computed property for form validation
    var isFormValid: Bool {
        return age >= 10 && age <= 120 &&
               gender != "Select" &&
               calorieTarget >= 1000 && calorieTarget <= 5000
    }
    
    var validationMessage: String {
        if gender == "Select" {
            return "Please select your gender"
        } else if age < 10 || age > 120 {
            return "Age must be between 10 and 120"
        } else if calorieTarget < 1000 || calorieTarget > 5000 {
            return "Calorie target must be between 1000 and 5000"
        } else {
            return ""
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.black.opacity(0.95),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 16) {
                            // Progress Indicator (only for new setup)
                            if !isEditMode {
                                HStack(spacing: 8) {
                                    ForEach(1...3, id: \.self) { step in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(step <= 2 ? Color.orange : Color.white.opacity(0.2))
                                            .frame(height: 6)
                                    }
                                }
                                .padding(.horizontal, 80)
                            }
                            
                            VStack(spacing: 8) {
                                Text(isEditMode ? "Edit Your Profile" : "Complete Your Profile")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text(isEditMode ? "Update your nutrition preferences" : "Help us personalize your nutrition journey")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 20)

                        // Validation Warning
                        if !isFormValid && !validationMessage.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.yellow)
                                Text(validationMessage)
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.yellow.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal)
                            .transition(.opacity)
                        }

                        // Personal Info Section
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeader(title: "Personal Information", icon: "person.fill", color: Color.orange)
                            
                            // Age Slider
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Age")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Spacer()
                                    
                                    Text("\(Int(age)) years")
                                        .font(.headline)
                                        .foregroundColor(ageError ? .red : .orange)
                                }
                                
                                Slider(value: $age, in: 10...120, step: 1)
                                    .accentColor(ageError ? .red : .orange)
                                    .onChange(of: age) { _, _ in
                                        validateAge()
                                    }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(ageError ? Color.red.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )

                            // Gender Selector with validation styling
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Gender")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    if genderError {
                                        Text("(Required)")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                
                                HStack(spacing: 12) {
                                    ForEach(genderOptions, id: \.self) { option in
                                        GenderButton(
                                            title: option,
                                            isSelected: gender == option,
                                            hasError: genderError && gender == "Select",
                                            action: { 
                                                gender = option
                                                validateGender()
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Activity Level Section
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeader(title: "Activity Level", icon: "figure.run", color: Color.green)
                            
                            VStack(spacing: 12) {
                                ForEach(activityOptions, id: \.0) { option in
                                    ActivityLevelCard(
                                        level: option.0,
                                        title: option.1,
                                        description: option.2,
                                        isSelected: activityLevel == option.0,
                                        action: { activityLevel = option.0 }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Nutrition Goals Section
                        VStack(alignment: .leading, spacing: 20) {
                            SectionHeader(title: "Nutrition Goals", icon: "target", color: Color.purple)
                            
                            // Calorie Target with validation
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Daily Calorie Target")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Spacer()
                                    
                                    Text("\(Int(calorieTarget)) kcal")
                                        .font(.headline)
                                        .foregroundColor(calorieError ? .red : .orange)
                                }
                                
                                Slider(value: $calorieTarget, in: 1000...5000, step: 50)
                                    .accentColor(calorieError ? .red : .orange)
                                    .onChange(of: calorieTarget) { _, _ in
                                        validateCalories()
                                    }
                                
                                HStack {
                                    Text("1000")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("5000")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(calorieError ? Color.red.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )

                            // Dietary Preferences
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Dietary Preferences (Optional)")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                
                                VStack(spacing: 12) {
                                    DietaryToggle(
                                        title: "Vegetarian",
                                        description: "No meat or fish",
                                        icon: "leaf.fill",
                                        isOn: $isVegetarian
                                    )
                                    
                                    DietaryToggle(
                                        title: "Keto",
                                        description: "Low carb, high fat",
                                        icon: "drop.fill",
                                        isOn: $isKeto
                                    )
                                    
                                    DietaryToggle(
                                        title: "Gluten-Free",
                                        description: "No gluten products",
                                        icon: "exclamationmark.triangle.fill",
                                        isOn: $isGlutenFree
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)

                        // Save Button with validation state
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            if validateForm() {
                                saveProfile()
                            } else {
                                showValidationAlert = true
                            }
                        }) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(isEditMode ? "Save Changes" : "Complete Setup")
                                        .fontWeight(.semibold)
                                    Image(systemName: isEditMode ? "checkmark" : "arrow.right")
                                }
                            }
                            .foregroundColor(isFormValid ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: isFormValid ? 
                                        [.orange, .orange.opacity(0.8)] : 
                                        [.gray, .gray.opacity(0.8)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: isFormValid ? .orange.opacity(0.3) : .clear, 
                                    radius: 8, x: 0, y: 4)
                        }
                        .disabled(isSaving)
                        .padding(.horizontal)
                        
                        // Skip option for optional setup (only for new users)
                        if !isEditMode {
                            Button(action: {
                                navigateToDashboard = true
                            }) {
                                Text("Skip for now")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.bottom, 20)
                        }
                        
                        .padding(.bottom, 40)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.gray)
                    }
                }
            }
            .onAppear {
                loadExistingProfile()
            }
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardView()
                    .navigationBarBackButtonHidden(true)
            }
            .alert("Complete Required Fields", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationErrors.joined(separator: "\n"))
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .overlay(
                // Loading overlay
                ZStack {
                    if showLoadingOverlay {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text(loadingMessage)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Syncing with server...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.black.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                    }
                }
                .animation(.easeInOut, value: showLoadingOverlay)
            )
        }
    }
    
    // MARK: - Validation Functions
    
    func validateGender() {
        genderError = gender == "Select"
    }
    
    func validateAge() {
        ageError = age < 10 || age > 120
    }
    
    func validateCalories() {
        calorieError = calorieTarget < 1000 || calorieTarget > 5000
    }
    
    func validateForm() -> Bool {
        validationErrors.removeAll()
        
        validateGender()
        validateAge()
        validateCalories()
        
        if gender == "Select" {
            validationErrors.append("• Please select your gender")
        }
        
        if age < 10 || age > 120 {
            validationErrors.append("• Age must be between 10 and 120 years")
        }
        
        if calorieTarget < 1000 || calorieTarget > 5000 {
            validationErrors.append("• Daily calorie target must be between 1000 and 5000")
        }
        
        return validationErrors.isEmpty
    }
    
    func loadExistingProfile() {
        guard let profile = existingProfile else { return }
        
        // Load existing values
        age = Double(profile.age)
        gender = profile.gender
        activityLevel = profile.activity_level
        calorieTarget = Double(profile.calorie_target)
        isVegetarian = profile.is_vegetarian ?? false
        isKeto = profile.is_keto ?? false
        isGlutenFree = profile.is_gluten_free ?? false
        
        print("📍 Loaded existing profile for editing")
    }

    func saveProfile() {
        guard validateForm() else {
            showValidationAlert = true
            return
        }
        
        isSaving = true
        showLoadingOverlay = true
        loadingMessage = isEditMode ? "Updating your profile..." : "Setting up your profile..."
        
        let userId = session.userID.isEmpty ?
            UserDefaults.standard.string(forKey: "user_id") ?? "" : session.userID
        
        // Create UserProfile object
        let profile = UserProfile(
            _id: existingProfile?._id,
            user_id: userId,
            age: Int(age),
            gender: gender,
            activity_level: activityLevel,
            calorie_target: Int(calorieTarget),
            is_vegetarian: isVegetarian,
            is_keto: isKeto,
            is_gluten_free: isGlutenFree,
            updated_at: nil
        )
        
        // Save using ProfileManager
        profileManager.saveProfile(profile) { [self] success, error in
            self.isSaving = false
            self.showLoadingOverlay = false
            
            if success {
                print("✅ Profile saved successfully to MongoDB")
                
                // Clear new registration flag after successful profile save
                SessionManager.shared.clearNewRegistrationFlag()
                
                if self.isEditMode {
                    // Just dismiss for edit mode
                    self.dismiss()
                } else {
                    // Navigate to dashboard for new setup
                    self.navigateToDashboard = true
                }
            } else {
                self.errorMessage = error ?? "Failed to save profile. Please try again."
                self.showError = true
                print("❌ Profile save failed: \(self.errorMessage)")
            }
        }
    }
}

// MARK: - Supporting Views with validation states

struct GenderButton: View {
    let title: String
    let isSelected: Bool
    var hasError: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.orange : Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    hasError ? Color.red.opacity(0.5) : 
                                    (isSelected ? Color.clear : Color.white.opacity(0.2)), 
                                    lineWidth: 1
                                )
                        )
                )
        }
    }
}

struct ActivityLevelCard: View {
    let level: String
    let title: String
    let description: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Level indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.orange : Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Text(level)
                        .font(.headline)
                        .foregroundColor(isSelected ? .black : .white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.orange.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }
}

struct DietaryToggle: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isOn ? .orange : .gray)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .labelsHidden()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}