import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isSecure = true
    @State private var rememberMe = false

    @State private var emailError = ""
    @State private var passwordError = ""
    @State private var loginFailed = false
    @State private var loginErrorMessage = ""
    @State private var navigateToDashboard = false
    @State private var isLoading = false
    @State private var showRegister = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background matching dashboard
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
                        // Logo and Header
                        VStack(spacing: 20) {
                            Image(systemName: "camera.macro.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .orange.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .orange.opacity(0.3), radius: 20)
                            
                            VStack(spacing: 8) {
                                Text("Welcome Back")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Log in to track your nutrition")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.top, 60)

                        // Login Form
                        VStack(spacing: 20) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .textCase(.uppercase)
                                    .tracking(1)
                                
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(.gray)
                                        .frame(width: 20)
                                    
                                    TextField("Enter your email", text: $email)
                                        .keyboardType(.emailAddress)
                                        .autocapitalization(.none)
                                        .foregroundColor(.white)
                                        .onChange(of: email) { _, _ in validateEmail() }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(emailError.isEmpty ? Color.white.opacity(0.1) : Color.red.opacity(0.5), lineWidth: 1)
                                        )
                                )
                                
                                if !emailError.isEmpty {
                                    Text(emailError)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .transition(.opacity)
                                }
                            }

                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .textCase(.uppercase)
                                    .tracking(1)
                                
                                HStack {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(.gray)
                                        .frame(width: 20)
                                    
                                    if isSecure {
                                        SecureField("Enter your password", text: $password)
                                            .foregroundColor(.white)
                                    } else {
                                        TextField("Enter your password", text: $password)
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
                                                .stroke(passwordError.isEmpty ? Color.white.opacity(0.1) : Color.red.opacity(0.5), lineWidth: 1)
                                        )
                                )
                                .onChange(of: password) { _, _ in validatePassword() }
                                
                                if !passwordError.isEmpty {
                                    Text(passwordError)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .transition(.opacity)
                                }
                            }

                            // Remember Me & Forgot Password
                            HStack {
                                Toggle(isOn: $rememberMe) {
                                    Text("Remember me")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .toggleStyle(CheckboxToggleStyle())
                                
                                Spacer()
                                
                                Button("Forgot Password?") {
                                    // Handle forgot password
                                }
                                .font(.caption)
                                .foregroundColor(.orange)
                            }

                            // Login Button
                            Button(action: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                validateEmail()
                                validatePassword()
                                if emailError.isEmpty && passwordError.isEmpty {
                                    attemptLogin()
                                }
                            }) {
                                ZStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        HStack {
                                            Text("Log In")
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
                            }
                            .disabled(isLoading)

                            if loginFailed {
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text(loginErrorMessage)
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
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

                            // Social Login
                            VStack(spacing: 12) {
                                // Apple 登录按钮
                                SignInWithAppleButton(.signIn) { request in
                                    request.requestedScopes = [.fullName, .email]
                                } onCompletion: { result in
                                    switch result {
                                    case .success(let authResults):
                                        if let credential = authResults.credential as? ASAuthorizationAppleIDCredential {
                                            let userId = credential.user                // Apple 的 sub
                                            let email = credential.email ?? "\(userId)@apple.local"
                                            let identityToken = credential.identityToken
                                            let authCode = credential.authorizationCode

                                            print("🍏 Apple login success")
                                            print("userId: \(userId)")
                                            print("email: \(email)")

                                            if let tokenData = identityToken, let tokenStr = String(data: tokenData, encoding: .utf8) {
                                                // 传给后端：tokenStr + email
                                                attemptAppleLogin(email: email, token: tokenStr)
                                            } else {
                                                self.loginFailed = true
                                                self.loginErrorMessage = "Failed to get Apple identity token"
                                            }
                                        }

                                    case .failure(let error):
                                        print("❌ Sign in with Apple failed: \(error.localizedDescription)")
                                        self.loginFailed = true
                                        self.loginErrorMessage = error.localizedDescription
                                    }
                                }
                                .frame(height: 50)
                                .cornerRadius(12)


                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Continue with Google")
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
                            }

                            // Register Link
                            HStack(spacing: 4) {
                                Text("New to the app?")
                                    .foregroundColor(.gray)
                                
                                Button("Create Account") {
                                    showRegister = true
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
            }
            .preferredColorScheme(.dark)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardView()
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
        }
    }

    // MARK: - Validation
    private func validateEmail() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        withAnimation(.easeInOut(duration: 0.2)) {
            emailError = trimmed.isEmpty ? "Email is required" :
                (!trimmed.contains("@") || !trimmed.contains(".")) ? "Enter a valid email" : ""
        }
    }

    private func validatePassword() {
        let trimmed = password.trimmingCharacters(in: .whitespaces)
        withAnimation(.easeInOut(duration: 0.2)) {
            passwordError = trimmed.isEmpty ? "Password is required" :
                (trimmed.count < 6 ? "Password must be at least 6 characters" : "")
        }
    }
    
    // MARK: -Apple Login
    private func attemptAppleLogin(email: String, token: String) {
        isLoading = true
        loginFailed = false
        
        NetworkManager.shared.appleLogin(email: email, identityToken: token) { result in
            self.isLoading = false
            
            switch result {
            case .success(let (userId, name, jwtToken)):
                print("✅ Apple login successful")
                SessionManager.shared.login(id: userId, name: name, token: jwtToken)
                withAnimation(.spring()) {
                    self.navigateToDashboard = true
                }
                
            case .failure(let error):
                print("❌ Apple login failed: \(error)")
                self.loginFailed = true
                self.loginErrorMessage = "Apple login failed. Please try again."
            }
        }
    }


    // MARK: - Login API Call with JWT
    private func attemptLogin() {
        isLoading = true
        loginFailed = false
        
        NetworkManager.shared.login(email: email, password: password) { result in
            self.isLoading = false
            
            switch result {
            case .success(let (userId, name, token)):
                print("✅ Login successful - Token received")
                
                // Save user session with JWT token
                SessionManager.shared.login(id: userId, name: name, token: token)

                // Navigate to dashboard
                withAnimation(.spring()) {
                    self.navigateToDashboard = true
                }
                
            case .failure(let error):
                print("❌ Login failed: \(error)")
                self.loginFailed = true
                
                if let nsError = error as NSError? {
                    if nsError.code == 401 {
                        self.loginErrorMessage = "Invalid email or password"
                    } else {
                        self.loginErrorMessage = nsError.localizedDescription
                    }
                } else {
                    self.loginErrorMessage = "Login failed. Please try again."
                }
            }
        }
    }
}

// Custom Checkbox Toggle Style
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundColor(configuration.isOn ? .orange : .gray)
                    .font(.system(size: 20))
                
                configuration.label
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
