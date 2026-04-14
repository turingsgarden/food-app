//
//  NewOnboardingView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/12/26.
//



import SwiftUI

struct NewOnboardingView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @State private var showLogin = false
    @State private var showHealthProfile = false

    // Health Profile fill in（Step 1 only: height, weight, age, sex）
    @State private var heightCm: Double = 170
    @State private var weightKg: Double = 70
    @State private var age: Int = 25
    @State private var sex: String = ""

    var bmi: Double {
        let h = heightCm / 100
        return weightKg / (h * h)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            // App branding
                            VStack(spacing: 8) {
                                Image(systemName: "heart.text.clipboard.fill")
                                    .font(.system(size: 44))
                                    .foregroundColor(themeManager.current.primaryText)
                                    .padding(.top, 40)
                                Text("Health Agent")
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text("Your personalised AI nutrition plan")
                                    .font(.system(size: 15))
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                            .padding(.bottom, 8)

                            // Quick health info
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Tell us about yourself")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(themeManager.current.primaryText)

                                // BMI preview
                                if !sex.isEmpty {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("BMI")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(themeManager.current.secondaryText)
                                                .textCase(.uppercase)
                                            Text(String(format: "%.1f", bmi))
                                                .font(.system(size: 24, weight: .black, design: .rounded))
                                                .foregroundColor(themeManager.current.primaryText)
                                        }
                                        Spacer()
                                        Text(bmiLabel())
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(bmiColor())
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(bmiColor().opacity(0.1))
                                            .cornerRadius(20)
                                    }
                                    .padding(14)
                                    .background(themeManager.current.inputBackground)
                                    .cornerRadius(14)
                                }

                                // Height
                                quickSlider(label: "Height", value: $heightCm, range: 100...220, unit: "cm",
                                            display: "\(Int(heightCm))")

                                // Weight
                                quickSlider(label: "Weight", value: $weightKg, range: 30...250, unit: "kg",
                                            display: String(format: "%.1f", weightKg))

                                // Age
                                quickSlider(label: "Age", value: Binding(get: { Double(age) }, set: { age = Int($0) }),
                                            range: 12...100, unit: "yrs", display: "\(age)")

                                // Sex
                                HStack(spacing: 8) {
                                    ForEach(["Male", "Female", "Other"], id: \.self) { s in
                                        Button(action: { sex = s.lowercased() }) {
                                            Text(s)
                                                .font(.system(size: 14, weight: sex == s.lowercased() ? .bold : .regular))
                                                .foregroundColor(sex == s.lowercased()
                                                    ? (themeManager.current == .dark ? .black : .white)
                                                    : themeManager.current.primaryText)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(RoundedRectangle(cornerRadius: 12)
                                                    .fill(sex == s.lowercased()
                                                          ? (themeManager.current == .dark ? Color.white : Color.black)
                                                          : themeManager.current.inputBackground))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(18)
                            .background(themeManager.current.cardBackground)
                            .cornerRadius(20)
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(themeManager.current.cardBorder, lineWidth: 1))

                            Spacer(minLength: 80)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Bottom buttons
                    VStack(spacing: 12) {
                        Divider().background(themeManager.current.cardBorder)

                        // Get Started
                        Button(action: startJourney) {
                            Text("Get Started")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(themeManager.current == .dark ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(sex.isEmpty
                                    ? Color.gray.opacity(0.3)
                                    : (themeManager.current == .dark ? Color.white : Color.black))
                                .cornerRadius(16)
                        }
                        .disabled(sex.isEmpty)
                        .padding(.horizontal, 20)

                        // Already have account / Skip
                        HStack(spacing: 4) {
                            Button(action: { showLogin = true }) {
                                Text("Already have an account?")
                                    .font(.system(size: 14))
                                    .foregroundColor(themeManager.current.secondaryText)
                                    .underline()
                            }
                            Text("·")
                                .foregroundColor(themeManager.current.secondaryText)
                            Button(action: { showLogin = true }) {
                                Text("Sign in")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(themeManager.current.primaryText)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showLogin) {
                
                OnboardingView()
                    .navigationBarBackButtonHidden(true)
                    .environmentObject(themeManager)
            }
            .navigationDestination(isPresented: $showHealthProfile) {
                
                HealthProfileView { profile in
                 
                }
                .environmentObject(themeManager)
            }
        }
    }

    func startJourney() {

        showHealthProfile = true
    }

    func quickSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, display: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(themeManager.current.secondaryText)
                Spacer()
                Text("\(display) \(unit)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.current.primaryText)
            }
            Slider(value: value, in: range, step: 1)
                .accentColor(themeManager.current == .dark ? .white : .black)
        }
    }

    func bmiLabel() -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal ✓"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }

    func bmiColor() -> Color {
        switch bmi {
        case ..<18.5: return .blue
        case 18.5..<25: return .green
        case 25..<30: return .orange
        default: return .red
        }
    }
}
