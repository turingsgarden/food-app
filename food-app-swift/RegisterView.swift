import SwiftUI
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift

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
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, email, password, confirmPassword
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
                .onTapGesture {
                    focusedField = nil
                }

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
                                .buttonStyle(PlainButtonStyle())
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
                                validate: validateName,
                                focusedField: $focusedField,
                                field: .name
                            )
                            
                            // Email Field
                            FormField(
                                title: "Email",
                                icon: "envelope.fill",
                                placeholder: "Enter your email",
                                text: $email,
                                error: $emailError,
                                validate: validateEmail,
                                keyboardType: .emailAddress,
                                focusedField: $focusedField,
                                field: .email
                            )

                            // Password Field
                            SecureFormField(
                                title: "Password",
                                icon: "lock.fill",
                                placeholder: "Create a password",
                                text: $password,
                                isSecure: $isSecure,
                                error: $passwordError,
                                validate: validatePassword,
                                focusedField: $focusedField,
                                field: .password
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
                                validate: validateConfirmPassword,
                                focusedField: $focusedField,
                                field: .confirmPassword
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

                            // Register Button
                            Button(action: {
                                focusedField = nil
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
                                .frame(height: 50)
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
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())

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

                            // Social Registration - FIXED
                            VStack(spacing: 12) {
                                // Apple Sign-In - FIXED
                                SignInWithAppleButton(.signUp) { request in
                                    print("🍎 Apple SignUp request started")
                                    request.requestedScopes = [.fullName, .email]
                                } onCompletion: { result in
                                    print("🍎 Apple SignUp completion triggered")
                                    
                                    switch result {
                                    case .success(let authResults):
                                        print("✅ Apple authorization success")
                                        
                                        if let credential = authResults.credential as? ASAuthorizationAppleIDCredential {
                                            let userId = credential.user
                                            let email = credential.email ?? "\(userId)@apple.local"
                                            let fullName = credential.fullName
                                            let firstName = fullName?.givenName ?? ""
                                            let lastName = fullName?.familyName ?? ""
                                            let displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                                            
                                            print("🎉 Apple signup data:")
                                            print("📧 Email: \(email)")
                                            print("👤 Name: \(displayName)")
                                            
                                            if let tokenData = credential.identityToken,
                                               let tokenStr = String(data: tokenData, encoding: .utf8) {
                                                print("🔑 Token received, registering...")
                                                attemptAppleRegister(email: email, name: displayName.isEmpty ? "Apple User" : displayName, token: tokenStr)
                                            } else {
                                                print("❌ Failed to get identity token")
                                                self.registrationFailed = true
                                                self.registrationError = "Failed to get Apple identity token"
                                            }
                                        } else {
                                            print("❌ Invalid credential type")
                                            self.registrationFailed = true
                                            self.registrationError = "Invalid Apple credential"
                                        }
                                        
                                    case .failure(let error):
                                        print("❌ Apple Sign-In failed: \(error.localizedDescription)")
                                        // Don't show error if user cancelled
                                        if (error as NSError).code != 1001 {
                                            self.registrationFailed = true
                                            self.registrationError = "Apple sign-up failed"
                                        }
                                    }
                                }
                                .signInWithAppleButtonStyle(.white)
                                .frame(height: 50)
                                .cornerRadius(12)

                                // Google Sign-In - FIXED
                                Button(action: {
                                    focusedField = nil
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    handleGoogleRegister()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Sign up with Google")
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contentShape(Rectangle())
                            }

                            // Login Link
                            HStack(spacing: 4) {
                                Text("Already have an account?")
                                    .foregroundColor(.gray)
                                
                                Button("Log In") {
                                    dismiss()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.orange)
                                .fontWeight(.semibold)
                            }
                            .font(.subheadline)
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 50)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
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

    // MARK: - Email/Password Registration
    
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
                    print("✅ Registration successful, navigating to dashboard")
                    withAnimation(.spring()) {
                        self.session.login(id: response.user_id, name: response.name, token: response.token, isNewUser: true)
                        self.navigateToDashboard = true
                    }
                } catch {
                    print("❌ JSON decode error: \(error)")
                    self.registrationFailed = true
                    self.registrationError = "Unexpected error. Please try again."
                }
            }
        }.resume()
    }
    
    // MARK: - Apple Sign-In Registration
    
    private func attemptAppleRegister(email: String, name: String, token: String) {
        isLoading = true
        registrationFailed = false
        
        NetworkManager.shared.appleLogin(email: email, identityToken: token) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let (userId, userName, jwtToken)):
                    print("✅ Apple registration successful")
                    // Use the name from Apple if available, otherwise use backend name
                    let finalName = name.isEmpty ? userName : name
                    withAnimation(.spring()) {
                        self.session.login(id: userId, name: finalName, token: jwtToken, isNewUser: true)
                        self.navigateToDashboard = true
                    }
                    
                case .failure(let error):
                    print("❌ Apple registration failed: \(error)")
                    self.registrationFailed = true
                    self.registrationError = "Apple sign-up failed. Please try again."
                }
            }
        }
    }
    
    // MARK: - Google Sign-In Registration
    
    private func handleGoogleRegister() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("❌ No root view controller")
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                print("❌ Google Sign-In failed:", error.localizedDescription)
                // Don't show error if user cancelled
                if (error as NSError).code != -5 {
                    DispatchQueue.main.async {
                        self.registrationFailed = true
                        self.registrationError = "Google sign-up failed"
                    }
                }
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                print("❌ Google Sign-In: no user or idToken")
                return
            }
            
            let email = user.profile?.email ?? ""
            let fullName = user.profile?.name ?? ""
            
            print("✅ Google sign-up success")
            print("📧 Email:", email)
            print("🧑 Name:", fullName)
            
            self.sendGoogleTokenToBackend(idToken: idToken, email: email)
        }
    }
    
    private func sendGoogleTokenToBackend(idToken: String, email: String) {
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/google_login") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["idToken": idToken, "email": email]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Network error:", error.localizedDescription)
                DispatchQueue.main.async {
                    self.registrationFailed = true
                    self.registrationError = "Network error. Please try again."
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 Backend response code:", httpResponse.statusCode)
            }
            
            if let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("📦 Backend response:", json)
                        
                        if let userId = json["user_id"] as? String,
                           let name = json["name"] as? String,
                           let token = json["token"] as? String {
                            print("✅ Google registration successful")
                            DispatchQueue.main.async {
                                withAnimation(.spring()) {
                                    self.session.login(id: userId, name: name, token: token, isNewUser: true)
                                    self.navigateToDashboard = true
                                }
                            }
                        } else {
                            print("❌ Missing fields in backend response")
                            DispatchQueue.main.async {
                                self.registrationFailed = true
                                self.registrationError = "Registration failed. Please try again."
                            }
                        }
                    }
                } catch {
                    print("❌ JSON parse error:", error.localizedDescription)
                    DispatchQueue.main.async {
                        self.registrationFailed = true
                        self.registrationError = "Registration failed. Please try again."
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Supporting Views

struct FormField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var error: String
    let validate: () -> Void
    var keyboardType: UIKeyboardType = .default
    var focusedField: FocusState<RegisterView.Field?>.Binding
    var field: RegisterView.Field
    
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
                    .focused(focusedField, equals: field)
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
    var focusedField: FocusState<RegisterView.Field?>.Binding
    var field: RegisterView.Field
    
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
                        .focused(focusedField, equals: field)
                } else {
                    TextField(placeholder, text: $text)
                        .foregroundColor(.white)
                        .focused(focusedField, equals: field)
                }
                
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .buttonStyle(PlainButtonStyle())
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
