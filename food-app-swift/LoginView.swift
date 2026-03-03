import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

func debugLog(_ message: String) {
    print("🟠 [LoginView LOG] \(Date()): \(message)")
}

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
    
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
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
                                        .focused($focusedField, equals: .email)
                                        .onChange(of: email) { old, new in
                                            debugLog("User typing email: '\(new)'")
                                            validateEmail()
                                        }
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
                                            .focused($focusedField, equals: .password)
                                    } else {
                                        TextField("Enter your password", text: $password)
                                            .foregroundColor(.white)
                                            .focused($focusedField, equals: .password)
                                    }
                                    
                                    Button(action: {
                                        isSecure.toggle()
                                    }) {
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
                                                .stroke(passwordError.isEmpty ? Color.white.opacity(0.1) : Color.red.opacity(0.5), lineWidth: 1)
                                        )
                                )
                                .onChange(of: password) { old, new in
                                    debugLog("User typing password: \(new.count) characters")
                                    validatePassword()
                                }
                                
                                
                                if !passwordError.isEmpty {
                                    Text(passwordError)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .transition(.opacity)
                                }
                            }
                            
                            // Remember Me & Forgot Password
                            HStack {
                                Button(action: {
                                    rememberMe.toggle()
                                    debugLog("User toggled RememberMe = \(rememberMe)")
                                    
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                            .foregroundColor(rememberMe ? .orange : .gray)
                                            .font(.title3)
                                        
                                        Text("Remember me for 7 days")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Spacer()
                                
                                Button("Forgot Password?") {
                                    debugLog("User tapped Forgot Password")
                                    showForgotPassword = true
                                }
                                .buttonStyle(PlainButtonStyle())
                                .font(.caption)
                                .foregroundColor(.orange)
                            }
                            
                            // Login Button
                            Button(action: {
                                focusedField = nil
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
                            }
                            .disabled(isLoading)
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())
                            
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
                                // Apple login button
                                SignInWithAppleButton(.signIn) { request in
                                    debugLog("User tapped Sign in with Apple")
                                    print("🍎 Apple SignIn request started")
                                    request.requestedScopes = [.fullName, .email]
                                    debugLog("Apple login: Requesting scopes = fullName, email")
                                    print("🍎 Requested scopes: fullName & email")
                                } onCompletion: { result in
                                    print("🍎 onCompletion triggered with result: \(result)")
                                    
                                    switch result {
                                    case .success(let authResults):
                                        debugLog("Apple login SUCCESS")
                                        print("✅ Authorization success, checking credential type...")
                                        
                                        if let credential = authResults.credential as? ASAuthorizationAppleIDCredential {
                                            print("🔑 Credential received: \(credential)")
                                            
                                            let userId = credential.user
                                            let email = credential.email ?? "\(userId)@privaterelay.appleid.com"
                                            let identityToken = credential.identityToken
                                            
                                            print("🎉 Apple login success")
                                            print("🔒 userId (Apple sub): \(userId)")
                                            print("📧 email: \(email)")
                                            
                                            if let tokenData = identityToken {
                                                print("📦 identityToken (raw data length): \(tokenData.count) bytes")
                                                if let tokenStr = String(data: tokenData, encoding: .utf8) {
                                                    print("📜 identityToken (string): \(tokenStr.prefix(80))...")
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
                                        } else {
                                            print("❌ Credential is not ASAuthorizationAppleIDCredential")
                                            self.loginFailed = true
                                            self.loginErrorMessage = "Unexpected credential type"
                                        }
                                        
                                    case .failure(let error):
                                        debugLog("Apple login FAILURE: \(error.localizedDescription)")
                                        print("❌ Sign in with Apple failed: \(error.localizedDescription)")
                                        self.loginFailed = true
                                        self.loginErrorMessage = error.localizedDescription
                                    }
                                }
                                .signInWithAppleButtonStyle(.white)
                                .frame(height: 50)
                                .cornerRadius(12)
                                
                                // Google login button
                                Button(action: {
                                    debugLog("User tapped Sign in with Google")
                                    focusedField = nil
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    debugLog("Google login UI presented")
                                    handleGoogleLogin()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Continue with Google")
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
                            
                            // Register Link
                            HStack(spacing: 4) {
                                Text("New to the app?")
                                    .foregroundColor(.gray)
                                
                                Button("Create Account") {
                                    showRegister = true
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
            .navigationDestination(isPresented: $showRegister) {
                RegisterView()
            }
            .navigationDestination(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
        }
    }
    
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
    
    // UPDATED: Apple login with email tracking
    private func attemptAppleLogin(email: String, token: String) {
        debugLog("Starting Apple login request")
        isLoading = true
        loginFailed = false
        
        NetworkManager.shared.appleLogin(email: email, identityToken: token) { result in
            self.isLoading = false
            
            switch result {
            case .success(let (userId, name, jwtToken)):
                print("✅ Apple login successful")
                // UPDATED: Pass email and login method
                SessionManager.shared.login(
                    id: userId,
                    name: name,
                    email: email,
                    token: jwtToken,
                    loginMethod: "apple"
                )
                withAnimation(.spring()) {
                    self.navigateToDashboard = true
                }
                
            case .failure(let error):
                print("❌ Apple login failed: \(error)")
                debugLog("Apple login FAILURE: \(error)")
                self.loginFailed = true
                self.loginErrorMessage = "Apple login failed. Please try again."
            }
        }
    }
    
    private func handleGoogleLogin() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            print("❌ No root view controller")
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error = error {
                print("❌ Google Sign-In failed:", error.localizedDescription)
                debugLog("Google login FAILURE: \(error.localizedDescription)")
                return
            }
            
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                print("❌ Google Sign-In: no user or idToken")
                debugLog("Google login FAILURE: no user or idToken")
                return
            }
            
            let email = user.profile?.email ?? ""
            let fullName = user.profile?.name ?? ""
            
            print("✅ Google login success")
            debugLog("Google backend login SUCCESS: userId=\(email)")
            print("📧 Email:", email)
            print("🧑 Name:", fullName)
            print("🔑 idToken:", idToken.prefix(20), "...")
            
            self.sendGoogleTokenToBackend(idToken: idToken, email: email)
        }
    }
    
    // UPDATED: Google login with email tracking
    private func sendGoogleTokenToBackend(idToken: String, email: String) {
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/google_login") else { return }
        
        // ← 加 timeout
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90  // ← 原来没有这行！
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["idToken": idToken, "email": email]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        DispatchQueue.main.async { self.isLoading = true }  // ← 加 loading
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { self.isLoading = false }
            
            if let error = error {
                print("❌ Network error:", error.localizedDescription)
                DispatchQueue.main.async {
                    self.loginFailed = true
                    self.loginErrorMessage = "Google login failed, please retry"
                }
                return
            }
            
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userId = json["user_id"] as? String,
               let name = json["name"] as? String,
               let token = json["token"] as? String {
                
                DispatchQueue.main.async {
                    SessionManager.shared.login(
                        id: userId,
                        name: name,
                        email: email,
                        token: token,
                        loginMethod: "google"
                    )
                    withAnimation(.spring()) {
                        self.navigateToDashboard = true
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.loginFailed = true
                    self.loginErrorMessage = "Google login failed, please retry"
                }
            }
        }.resume()
    }
    // UPDATED: Email login with email tracking and optimized timeout
    private func attemptLogin() {
        isLoading = true
        loginFailed = false
        loginErrorMessage = "Starting up server, please wait..."  // ← 先显示提示
        
        NetworkManager.shared.loginFast(email: email, password: password) { result in
            self.isLoading = false
            self.loginErrorMessage = ""
            
            switch result {
            case .success(let (userId, name, token)):
                debugLog("Login API returned SUCCESS: userId=\(userId), name=\(name)")
                SessionManager.shared.login(
                    id: userId,
                    name: name,
                    email: self.email,
                    token: token,
                    loginMethod: "email"
                )
                withAnimation(.spring()) {
                    self.navigateToDashboard = true
                }
                
            case .failure(let error):
                debugLog("Login API returned FAILURE: \(error.localizedDescription)")
                self.loginFailed = true
                
                if let nsError = error as NSError? {
                    switch nsError.code {
                    case 401:
                        self.loginErrorMessage = "Invalid email or password"
                    case NSURLErrorTimedOut:
                        self.loginErrorMessage = "Server is starting up, please try again in 30 seconds"
                    case NSURLErrorNotConnectedToInternet:
                        self.loginErrorMessage = "No internet connection"
                    case NSURLErrorNetworkConnectionLost:
                        self.loginErrorMessage = "Connection lost, please retry"
                    default:
                        self.loginErrorMessage = "Login failed. Please try again."
                    }
                } else {
                    self.loginErrorMessage = "Login failed. Please try again."
                }
            }
        }
    }
}
