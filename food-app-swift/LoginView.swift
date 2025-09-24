import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
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
    
    
    @State private var showForgotPassword = false
    @State private var forgotPasswordEmail = ""
    @State private var forgotPasswordMessage = ""
    @State private var forgotPasswordError = ""
    @State private var forgotPasswordLoading = false
    
    @State private var forgotPasswordStep = 1
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var resetPasswordError = ""
    @State private var resetPasswordMessage = ""
    @State private var statusMessage = ""


    @State private var showNewPassword = false


    
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
                                    showForgotPassword = true
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
                                    print("📩 Apple SignIn request started")
                                    request.requestedScopes = [.fullName, .email]
                                    print("📩 Requested scopes: fullName & email")
                                } onCompletion: { result in
                                    print("📩 onCompletion triggered with result: \(result)")
                                    
                                    switch result {
                                    case .success(let authResults):
                                        print("✅ Authorization success, checking credential type...")
                                        
                                        if let credential = authResults.credential as? ASAuthorizationAppleIDCredential {
                                            print("🔍 Credential received: \(credential)")
                                            
                                            let userId = credential.user                // Apple 的 sub（稳定ID）
                                            let email = credential.email ?? "\(userId)@apple.local"
                                            let identityToken = credential.identityToken
                                            let authCode = credential.authorizationCode
                                            
                                            print("🍏 Apple login success")
                                            print("🔑 userId (Apple sub): \(userId)")
                                            print("📧 email: \(email)")
                                            
                                            if let tokenData = identityToken {
                                                print("📦 identityToken (raw data length): \(tokenData.count) bytes")
                                                if let tokenStr = String(data: tokenData, encoding: .utf8) {
                                                    print("📜 identityToken (string): \(tokenStr.prefix(80))...") // 只打印前80字符避免太长
                                                    // 传给后端
                                                    attemptAppleLogin(email: email, token: tokenStr)
                                                } else {
                                                    print("❌ Failed to convert identityToken to String")
                                                    self.loginFailed = true
                                                    self.loginErrorMessage = "Failed to parse Apple identity token"
                                                }
                                            } else {
                                                print("❌ No identityToken received")
                                                self.loginFailed = true
                                                self.loginErrorMessage = "Failed to get Apple identity token"
                                            }
                                            
                                            if let code = authCode, let codeStr = String(data: code, encoding: .utf8) {
                                                print("📜 authorizationCode: \(codeStr)")
                                            } else {
                                                print("⚠️ No authorizationCode received")
                                            }
                                        } else {
                                            print("❌ Credential is not ASAuthorizationAppleIDCredential")
                                            self.loginFailed = true
                                            self.loginErrorMessage = "Unexpected credential type"
                                        }
                                        
                                    case .failure(let error):
                                        print("❌ Sign in with Apple failed: \(error.localizedDescription)")
                                        self.loginFailed = true
                                        self.loginErrorMessage = error.localizedDescription
                                    }
                                }
                                .signInWithAppleButtonStyle(.white)
                                .cornerRadius(12)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .padding(.horizontal, 0)
                                .onTapGesture {
                                    print("🖱 Apple button tapped (raw tap)")
                                }
                                
                                
                                
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    handleGoogleLogin()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Continue with Google")
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity) // stretch fully
                                }
                                .frame(height: 50) // lock to 50 like Apple
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .cornerRadius(12)
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
            .onAppear {
                if SessionManager.shared.isLoggedIn {
                    navigateToDashboard = true
                }
            }
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardView()
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
            .sheet(isPresented: $showForgotPassword) {
                VStack(spacing: 20) {
                    Text("Reset Password")
                        .font(.title2)
                        .bold()
                    
                    if forgotPasswordStep == 1 {
                        // Step 1: Email input
                        TextField("Enter your email", text: $forgotPasswordEmail)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                        
                        Button("Send Verification Code") {
                            sendForgotPasswordRequest()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    else if forgotPasswordStep == 2 {
                        // Step 2: Code input
                        TextField("Enter verification code", text: $resetCode)
                            .keyboardType(.numberPad)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                        
                        Button("Verify Code") {
                            verifyResetCode()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    else if forgotPasswordStep == 3 {
                        // Step 3: New password with toggle
                        HStack {
                            if showNewPassword {
                                TextField("Enter new password", text: $newPassword)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            } else {
                                SecureField("Enter new password", text: $newPassword)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            
                            Button(action: { showNewPassword.toggle() }) {
                                Image(systemName: showNewPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                        
                        Button("Reset Password") {
                            resetPassword()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    // Messages & Errors
                    if !forgotPasswordError.isEmpty {
                        Text(forgotPasswordError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    
                    Button("Cancel") {
                        resetForgotPasswordState()
                        showForgotPassword = false
                    }
                    .foregroundColor(.gray)
                    
                    Spacer()
                }
                .padding()
                .background(Color.black)
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
                
                if rememberMe {
                    UserDefaults.standard.set(true, forKey: "rememberMe")
                    UserDefaults.standard.set(userId, forKey: "userId")
                    UserDefaults.standard.set(name, forKey: "userName")
                    KeychainHelper.shared.save(token, service: "auth", account: "jwt")
                } else {
                    UserDefaults.standard.set(false, forKey: "rememberMe")
                    UserDefaults.standard.removeObject(forKey: "userId")
                    UserDefaults.standard.removeObject(forKey: "userName")
                    KeychainHelper.shared.delete(service: "auth", account: "jwt")
                }

                
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
    
    // MARK: - Login with Google
    private func handleGoogleLogin() {
        guard let rootVC = UIApplication.shared.windows.first?.rootViewController else {
            print("❌ No root view controller")
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                print("❌ Google Sign-In failed:", error.localizedDescription)
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                print("❌ Google Sign-In: no user or idToken")
                return
            }
            
            let email = user.profile?.email ?? ""
            let fullName = user.profile?.name ?? ""
            
            print("✅ Google login success")
            print("📧 Email:", email)
            print("🧑 Name:", fullName)
            print("🔑 idToken:", idToken.prefix(20), "...")
            
            // 把 token 传给后端验证
            sendGoogleTokenToBackend(idToken: idToken, email: email)
        }
    }
    
    /// 把 Google ID Token 发送到后端
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
                            print("✅ Google login successful - Saving session")
                            DispatchQueue.main.async {
                                SessionManager.shared.login(id: userId, name: name, token: token)
                                if rememberMe {
                                    UserDefaults.standard.set(true, forKey: "rememberMe")
                                    UserDefaults.standard.set(userId, forKey: "userId")
                                    UserDefaults.standard.set(name, forKey: "userName")
                                    KeychainHelper.shared.save(token, service: "auth", account: "jwt")
                                } else {
                                    UserDefaults.standard.set(false, forKey: "rememberMe")
                                    UserDefaults.standard.removeObject(forKey: "userId")
                                    UserDefaults.standard.removeObject(forKey: "userName")
                                    KeychainHelper.shared.delete(service: "auth", account: "jwt")
                                }
                                withAnimation(.spring()) {
                                    self.navigateToDashboard = true
                                }
                            }
                        } else {
                            print("❌ Missing fields in backend response")
                        }
                    }
                } catch {
                    print("❌ JSON parse error:", error.localizedDescription)
                }
            }
        }.resume()
    }
    
    private func sendForgotPasswordRequest() {
        let trimmed = forgotPasswordEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty, trimmed.contains("@"), trimmed.contains(".") else {
            forgotPasswordError = "Enter a valid email"
            return
        }
        
        forgotPasswordError = ""
        statusMessage = ""
        forgotPasswordLoading = true
        
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/forgot_password") else {
            forgotPasswordError = "Invalid API endpoint"
            forgotPasswordLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["email": trimmed]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                forgotPasswordLoading = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    print("❌ ForgotPassword Network error:", error.localizedDescription)
                    forgotPasswordError = "Network error: \(error.localizedDescription)"
                    statusMessage = ""
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌐 ForgotPassword HTTP Status:", httpResponse.statusCode)
            } else {
                print("⚠️ ForgotPassword: No valid HTTPURLResponse")
            }
            
            if let data = data {
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("📦 ForgotPassword Response body:", jsonString)
                } else {
                    print("⚠️ ForgotPassword: Could not decode response body")
                }
            } else {
                print("⚠️ ForgotPassword: No response data")
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    print("✅ ForgotPassword success: Verification code sent")
                    forgotPasswordError = ""
                    statusMessage = "✅ Verification code sent! Check your email."
                    forgotPasswordStep = 2
                }
            } else {
                DispatchQueue.main.async {
                    print("❌ ForgotPassword failure: Invalid status code or response")
                    forgotPasswordError = "❌ Failed to send reset code"
                    statusMessage = ""
                }
            }
        }.resume()
    }

    private func verifyResetCode() {
        guard !resetCode.isEmpty else {
            forgotPasswordError = "Enter the code you received"
            return
        }

        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/verify_reset_code") else {
            forgotPasswordError = "Invalid API endpoint"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": forgotPasswordEmail, "code": resetCode]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    forgotPasswordError = "Network error: \(error.localizedDescription)"
                    statusMessage = ""
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    forgotPasswordError = ""
                    statusMessage = "✅ Code verified! Enter new password."
                    forgotPasswordStep = 3
                }
            } else {
                DispatchQueue.main.async {
                    forgotPasswordError = "❌ Invalid or expired code"
                    statusMessage = ""
                }
            }
        }.resume()
    }

    private func resetPassword() {
        guard !newPassword.isEmpty, newPassword.count >= 6 else {
            forgotPasswordError = "Password must be at least 6 characters"
            return
        }

        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/reset_password") else {
            forgotPasswordError = "Invalid API endpoint"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": forgotPasswordEmail, "new_password": newPassword]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    forgotPasswordError = "Network error: \(error.localizedDescription)"
                    statusMessage = ""
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DispatchQueue.main.async {
                    forgotPasswordError = ""
                    statusMessage = "✅ Password reset successful! You can log in now."
                    resetForgotPasswordState()
                    showForgotPassword = false
                }
            } else {
                DispatchQueue.main.async {
                    forgotPasswordError = "❌ Failed to reset password"
                    statusMessage = ""
                }
            }
        }.resume()
    }

    private func resetForgotPasswordState() {
        forgotPasswordStep = 1
        forgotPasswordEmail = ""
        resetCode = ""
        newPassword = ""
        forgotPasswordError = ""
        statusMessage = ""
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
                
                if rememberMe {
                    UserDefaults.standard.set(true, forKey: "rememberMe")
                    UserDefaults.standard.set(userId, forKey: "userId")
                    UserDefaults.standard.set(name, forKey: "userName")
                    KeychainHelper.shared.save(token, service: "auth", account: "jwt")
                } else {
                    UserDefaults.standard.set(false, forKey: "rememberMe")
                    UserDefaults.standard.removeObject(forKey: "userId")
                    UserDefaults.standard.removeObject(forKey: "userName")
                    KeychainHelper.shared.delete(service: "auth", account: "jwt")
                }

                
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
