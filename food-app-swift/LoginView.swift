//  LoginView.swift
//  food-app-swift
//
//  Created by Helen Tu on 3/3/26.
import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

func debugLog(_ message: String) {
    print("🟠 [LoginView LOG] \(Date()): \(message)")
}

struct LoginView: View {
    @EnvironmentObject var themeManager: ThemeManager
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
    
    enum Field { case email, password }
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background
                    .ignoresSafeArea()
                    .onTapGesture { focusedField = nil }
                
                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 20) {
                            Image(systemName: "camera.macro.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(LinearGradient(
                                    colors: [.orange, .orange.opacity(0.7)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .shadow(color: .orange.opacity(0.3), radius: 20)
                            
                            VStack(spacing: 8) {
                                Text("Welcome Back")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text("Log in to track your nutrition")
                                    .font(.subheadline)
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                        }
                        .padding(.top, 60)
                        
                        VStack(spacing: 20) {
                            // Email Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email").font(.caption)
                                    .foregroundColor(themeManager.current.secondaryText)
                                    .textCase(.uppercase).tracking(1)
                                
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(themeManager.current.secondaryText).frame(width: 20)
                                    TextField("Enter your email", text: $email)
                                        .keyboardType(.emailAddress).autocapitalization(.none)
                                        .foregroundColor(themeManager.current.primaryText)
                                        .focused($focusedField, equals: .email)
                                        .onChange(of: email) { _, _ in validateEmail() }
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(themeManager.current.inputBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(emailError.isEmpty ? themeManager.current.cardBorder : Color.red.opacity(0.5), lineWidth: 1)))
                                
                                if !emailError.isEmpty {
                                    Text(emailError).font(.caption).foregroundColor(.red).transition(.opacity)
                                }
                            }
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password").font(.caption)
                                    .foregroundColor(themeManager.current.secondaryText)
                                    .textCase(.uppercase).tracking(1)
                                
                                HStack {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(themeManager.current.secondaryText).frame(width: 20)
                                    if isSecure {
                                        SecureField("Enter your password", text: $password)
                                            .foregroundColor(themeManager.current.primaryText)
                                            .focused($focusedField, equals: .password)
                                    } else {
                                        TextField("Enter your password", text: $password)
                                            .foregroundColor(themeManager.current.primaryText)
                                            .focused($focusedField, equals: .password)
                                    }
                                    Button(action: { isSecure.toggle() }) {
                                        Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(themeManager.current.secondaryText).font(.caption)
                                    }.buttonStyle(PlainButtonStyle())
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(themeManager.current.inputBackground)
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(passwordError.isEmpty ? themeManager.current.cardBorder : Color.red.opacity(0.5), lineWidth: 1)))
                                .onChange(of: password) { _, _ in validatePassword() }
                                
                                if !passwordError.isEmpty {
                                    Text(passwordError).font(.caption).foregroundColor(.red).transition(.opacity)
                                }
                            }
                            
                            HStack {
                                Button(action: { rememberMe.toggle() }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                            .foregroundColor(rememberMe ? .orange : themeManager.current.secondaryText).font(.title3)
                                        Text("Remember me for 7 days").font(.caption)
                                            .foregroundColor(themeManager.current.secondaryText)
                                    }
                                }.buttonStyle(PlainButtonStyle())
                                Spacer()
                                Button("Forgot Password?") { showForgotPassword = true }
                                    .buttonStyle(PlainButtonStyle()).font(.caption).foregroundColor(.orange)
                            }
                            
                            Button(action: {
                                focusedField = nil
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                validateEmail(); validatePassword()
                                if emailError.isEmpty && passwordError.isEmpty { attemptLogin() }
                            }) {
                                ZStack {
                                    if isLoading {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        HStack {
                                            Text("Log In").fontWeight(.semibold)
                                            Image(systemName: "arrow.right")
                                        }
                                    }
                                }
                                .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 50)
                                .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                .cornerRadius(12).shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isLoading).buttonStyle(PlainButtonStyle()).contentShape(Rectangle())
                            
                            if loginFailed {
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                                    Text(loginErrorMessage).foregroundColor(.red).font(.caption)
                                }
                                .padding().background(Color.red.opacity(0.1)).cornerRadius(8)
                            }
                            
                            HStack {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                                Text("OR").font(.caption).foregroundColor(themeManager.current.secondaryText).padding(.horizontal, 16)
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                            }.padding(.vertical, 8)
                            
                            VStack(spacing: 12) {
                                SignInWithAppleButton(.signIn) { request in
                                    request.requestedScopes = [.fullName, .email]
                                } onCompletion: { result in
                                    switch result {
                                    case .success(let authResults):
                                        if let credential = authResults.credential as? ASAuthorizationAppleIDCredential {
                                            let userId = credential.user
                                            let email = credential.email ?? "\(userId)@privaterelay.appleid.com"
                                            if let tokenData = credential.identityToken,
                                               let tokenStr = String(data: tokenData, encoding: .utf8) {
                                                attemptAppleLogin(email: email, token: tokenStr)
                                            } else {
                                                self.loginFailed = true
                                                self.loginErrorMessage = "Failed to parse Apple identity token"
                                            }
                                        }
                                    case .failure(let error):
                                        self.loginFailed = true
                                        self.loginErrorMessage = error.localizedDescription
                                    }
                                }
                                .signInWithAppleButtonStyle(themeManager.current == .dark ? .white : .black)
                                .frame(height: 50).cornerRadius(12)
                                
                                Button(action: {
                                    focusedField = nil
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    handleGoogleLogin()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Continue with Google").fontWeight(.medium)
                                    }
                                    .foregroundColor(themeManager.current.primaryText)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(themeManager.current.inputBackground)
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                            .stroke(themeManager.current.cardBorder, lineWidth: 1)))
                                }
                                .buttonStyle(PlainButtonStyle()).contentShape(Rectangle())
                            }
                            
                            HStack(spacing: 4) {
                                Text("New to the app?").foregroundColor(themeManager.current.secondaryText)
                                Button("Create Account") { showRegister = true }
                                    .buttonStyle(PlainButtonStyle()).foregroundColor(.orange).fontWeight(.semibold)
                            }.font(.subheadline)
                        }
                        .padding(.horizontal, 24)
                        Spacer(minLength: 50)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardView().navigationBarBackButtonHidden(true)
            }
            .navigationDestination(isPresented: $showRegister) { RegisterView() }
            .navigationDestination(isPresented: $showForgotPassword) { ForgotPasswordView() }
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
    
    private func knownAccountEmail() -> String? {
        let session = SessionManager.shared
        guard session.isLoggedIn else { return nil }
        let email = session.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? nil : email
    }

    private func attemptAppleLogin(email: String, token: String) {
        isLoading = true; loginFailed = false
        NetworkManager.shared.appleLogin(
            email: email,
            identityToken: token,
            knownEmail: knownAccountEmail()
        ) { result in
            self.isLoading = false
            switch result {
            case .success(let (userId, name, responseEmail, jwtToken)):
                SessionManager.shared.login(
                    id: userId,
                    name: name,
                    email: responseEmail,
                    token: jwtToken,
                    loginMethod: "apple"
                )
                withAnimation(.spring()) { self.navigateToDashboard = true }
            case .failure:
                self.loginFailed = true
                self.loginErrorMessage = "Apple login failed. Please try again."
            }
        }
    }

    private func handleGoogleLogin() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            guard let user = result?.user, let idToken = user.idToken?.tokenString else { return }
            self.sendGoogleTokenToBackend(
                idToken: idToken,
                email: user.profile?.email ?? "",
                name: user.profile?.name ?? ""
            )
        }
    }

    private func sendGoogleTokenToBackend(idToken: String, email: String, name: String) {
        DispatchQueue.main.async { self.isLoading = true }
        NetworkManager.shared.googleLogin(
            idToken: idToken,
            email: email,
            name: name,
            knownEmail: knownAccountEmail()
        ) { result in
            DispatchQueue.main.async { self.isLoading = false }
            switch result {
            case .success(let (userId, responseName, responseEmail, token)):
                DispatchQueue.main.async {
                    SessionManager.shared.login(
                        id: userId,
                        name: responseName,
                        email: responseEmail,
                        token: token,
                        loginMethod: "google"
                    )
                    withAnimation(.spring()) { self.navigateToDashboard = true }
                }
            case .failure:
                DispatchQueue.main.async {
                    self.loginFailed = true
                    self.loginErrorMessage = "Google login failed, please retry"
                }
            }
        }
    }
    
    private func attemptLogin() {
        isLoading = true; loginFailed = false
        loginErrorMessage = "Starting up server, please wait..."
        NetworkManager.shared.loginFast(email: email, password: password) { result in
            self.isLoading = false; self.loginErrorMessage = ""
            switch result {
            case .success(let (userId, name, token)):
                SessionManager.shared.login(id: userId, name: name, email: self.email, token: token, loginMethod: "email")
                withAnimation(.spring()) { self.navigateToDashboard = true }
            case .failure(let error):
                self.loginFailed = true
                let code = (error as NSError).code
                switch code {
                case 401: self.loginErrorMessage = "Invalid email or password"
                case NSURLErrorTimedOut: self.loginErrorMessage = "Server is starting up, please try again in 30 seconds"
                case NSURLErrorNotConnectedToInternet: self.loginErrorMessage = "No internet connection"
                case NSURLErrorNetworkConnectionLost: self.loginErrorMessage = "Connection lost, please retry"
                default: self.loginErrorMessage = "Login failed. Please try again."
                }
            }
        }
    }
}
