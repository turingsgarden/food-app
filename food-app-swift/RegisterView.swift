import SwiftUI
import AuthenticationServices

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session = SessionManager.shared

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSecure = true
    @State private var isConfirmSecure = true

    @State private var nameError = ""
    @State private var emailError = ""
    @State private var passwordError = ""
    @State private var confirmPasswordError = ""
    @State private var registrationFailed = false
    @State private var registrationError = ""
    @State private var navigateToDashboard = false
    @State private var isLoading = false
    @State private var agreedToTerms = false

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
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 20) {
                            // Back button
                            HStack {
                                Button(action: { dismiss() }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "chevron.left")
                                        Text("Back")
                                    }
                                    .foregroundColor(.gray)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                Text("Create Account")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Start your nutrition journey today")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.top, 20)

                        // Registration Form
                        VStack(spacing: 20) {
                            // Name Field
                            FormField(
                                title: "Full Name",
                                icon: "person.fill",
                                placeholder: "Enter your name",
                                text: $name,
                                error: $nameError,
                                validate: validateName
                            )
                            
                            // Email Field
                            FormField(
                                title: "Email",
                                icon: "envelope.fill",
                                placeholder: "Enter your email",
                                text: $email,
                                error: $emailError,
                                validate: validateEmail,
                                keyboardType: .emailAddress
                            )

                            // Password Field
                            SecureFormField(
                                title: "Password",
                                icon: "lock.fill",
                                placeholder: "Create a password",
                                text: $password,
                                isSecure: $isSecure,
                                error: $passwordError,
                                validate: validatePassword
                            )
                            
                            // Password strength indicator
                            if !password.isEmpty {
                                PasswordStrengthIndicator(password: password)
                            }

                            // Confirm Password Field
                            SecureFormField(
                                title: "Confirm Password",
                                icon: "lock.fill",
                                placeholder: "Confirm your password",
                                text: $confirmPassword,
                                isSecure: $isConfirmSecure,
                                error: $confirmPasswordError,
                                validate: validateConfirmPassword
                            )

                            // Terms and Conditions
                            HStack(alignment: .top, spacing: 12) {
                                Button(action: { agreedToTerms.toggle() }) {
                                    Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                        .foregroundColor(agreedToTerms ? .orange : .gray)
                                        .font(.title3)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("I agree to the ")
                                        .foregroundColor(.gray) +
                                    Text("Terms of Service")
                                        .foregroundColor(.orange)
                                        .underline() +
                                    Text(" and ")
                                        .foregroundColor(.gray) +
                                    Text("Privacy Policy")
                                        .foregroundColor(.orange)
                                        .underline()
                                }
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                
                                Spacer()
                            }

                            // Register Button - FIXED RESPONSIVENESS
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                validateAll()
                                if allValid() && agreedToTerms {
                                    attemptRegister()
                                }
                            }) {
                                ZStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        HStack {
                                            Text("Create Account")
                                                .fontWeight(.semibold)
                                            Image(systemName: "arrow.right")
                                        }
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(12)
                                .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                                .opacity(agreedToTerms ? 1.0 : 0.6)
                            }
                            .disabled(isLoading || !agreedToTerms)
                            .buttonStyle(PlainButtonStyle()) // Add for better touch response

                            if registrationFailed {
                                ErrorCard(message: registrationError)
                            }

                            // Divider
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                
                                Text("OR")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)
                                
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                            }
                            .padding(.vertical, 8)

                            // Social Registration - Keep existing
                            VStack(spacing: 12) {
                                SignInWithAppleButton(.signUp, onRequest: { _ in }, onCompletion: { _ in })
                                    .frame(height: 50)
                                    .cornerRadius(12)

                                Button(action: {}) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Sign up with Google")
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle()) // Add for better touch response
                            }

                            // Login Link
                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .foregroundColor(.gray)
                                
                                Button("Log In") {
                                    dismiss()
                                }
                                .foregroundColor(.orange)
                                .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 50)
                    }
                }
                .scrollDismissesKeyboard(.interactively) // Add for better keyboard handling
            }
            .preferredColorScheme(.dark)
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardView()
                    .navigationBarBackButtonHidden(true)
            }
        }
    }

    // MARK: - Validation Functions
    
    func validateName() {
        withAnimation(.easeInOut(duration: 0.2)) {
            nameError = name.isEmpty ? "Name is required" : ""
        }
    }

    func validateEmail() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        withAnimation(.easeInOut(duration: 0.2)) {
            emailError = trimmed.isEmpty ? "Email is required" :
                (!trimmed.contains("@") || !trimmed.contains(".")) ? "Enter a valid email" : ""
        }
    }

    func validatePassword() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if password.isEmpty {
                passwordError = "Password is required"
            } else if password.count < 6 {
                passwordError = "Password must be at least 6 characters"
            } else {
                passwordError = ""
            }
        }
    }

    func validateConfirmPassword() {
        withAnimation(.easeInOut(duration: 0.2)) {
            confirmPasswordError = confirmPassword != password ? "Passwords do not match" : ""
        }
    }

    func validateAll() {
        validateName()
        validateEmail()
        validatePassword()
        validateConfirmPassword()
        
        if !agreedToTerms {
            registrationError = "Please agree to the terms and conditions"
            registrationFailed = true
        }
    }

    func allValid() -> Bool {
        nameError.isEmpty && emailError.isEmpty && passwordError.isEmpty && confirmPasswordError.isEmpty
    }

    // MARK: - API Call (WITHOUT OTP)
    
    func attemptRegister() {
        isLoading = true
        registrationFailed = false
        
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/register") else { return }

        let payload = ["name": name, "email": email, "password": password]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if error != nil {
                    self.registrationFailed = true
                    self.registrationError = "Network error. Please try again."
                    return
                }
                
                guard let data = data else {
                    self.registrationFailed = true
                    self.registrationError = "No response from server."
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 409 {
                        self.registrationFailed = true
                        self.registrationError = "This email is already registered."
                        return
                    } else if httpResponse.statusCode != 200 {
                        self.registrationFailed = true
                        self.registrationError = "Registration failed. Please try again."
                        return
                    }
                }
                
                // Decode the response
                do {
                    let response = try JSONDecoder().decode(RegisterResponse.self, from: data)
                    withAnimation(.spring()) {
                        self.session.login(id: response.user_id, name: response.name, token: response.token, isNewUser: true)
                        self.navigateToDashboard = true
                    }
                } catch {
                    self.registrationFailed = true
                    self.registrationError = "Unexpected error. Please try again."
                }
            }
        }.resume()
    }
}

// Keep all supporting views unchanged
struct FormField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var error: String
    let validate: () -> Void
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .textCase(.uppercase)
                .tracking(1)
            
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                    .frame(width: 20)
                
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                    .foregroundColor(.white)
                    .onChange(of: text) { _, _ in validate() }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(error.isEmpty ? Color.white.opacity(0.1) : Color.red.opacity(0.5), lineWidth: 1)
                    )
            )
            
            if !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
    }
}

struct SecureFormField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var isSecure: Bool
    @Binding var error: String
    let validate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .textCase(.uppercase)
                .tracking(1)
            
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.gray)
                    .frame(width: 20)
                
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .foregroundColor(.white)
                } else {
                    TextField(placeholder, text: $text)
                        .foregroundColor(.white)
                }
                
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(error.isEmpty ? Color.white.opacity(0.1) : Color.red.opacity(0.5), lineWidth: 1)
                    )
            )
            .onChange(of: text) { _, _ in validate() }
            
            if !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
    }
}

struct PasswordStrengthIndicator: View {
    let password: String
    
    var strength: (text: String, color: Color, progress: Double) {
        if password.count < 6 { return ("Weak", .red, 0.25) }
        else if password.count < 10 { return ("Fair", .orange, 0.5) }
        else if password.count < 14 { return ("Good", .yellow, 0.75) }
        else { return ("Strong", .green, 1.0) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Password strength:")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(strength.text)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(strength.color)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(strength.color)
                        .frame(width: geometry.size.width * strength.progress, height: 4)
                        .animation(.spring(), value: strength.progress)
                }
            }
            .frame(height: 4)
        }
    }
}

struct ErrorCard: View {
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .foregroundColor(.red)
                .font(.caption)
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
