import SwiftUI
import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift

struct RegisterView: View {
    @EnvironmentObject var themeManager: ThemeManager
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
    
    enum Field { case name, email, password, confirmPassword }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background
                    .ignoresSafeArea()
                    .onTapGesture { focusedField = nil }

                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 20) {
                            HStack {
                                Button(action: { dismiss() }) {
                                    Image(systemName: "chevron.left")
                                        .foregroundColor(themeManager.current.secondaryText)
                                }
                                .buttonStyle(PlainButtonStyle())
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                Text("Create Account")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(themeManager.current.primaryText)
                                Text("Start your nutrition journey today")
                                    .font(.subheadline)
                                    .foregroundColor(themeManager.current.secondaryText)
                            }
                        }
                        .padding(.top, 20)

                        VStack(spacing: 20) {
                            FormField(title: "Full Name", icon: "person.fill", placeholder: "Enter your name",
                                      text: $name, error: $nameError, validate: validateName,
                                      focusedField: $focusedField, field: .name)
                            FormField(title: "Email", icon: "envelope.fill", placeholder: "Enter your email",
                                      text: $email, error: $emailError, validate: validateEmail,
                                      keyboardType: .emailAddress, focusedField: $focusedField, field: .email)
                            SecureFormField(title: "Password", icon: "lock.fill", placeholder: "Create a password",
                                           text: $password, isSecure: $isSecure, error: $passwordError,
                                           validate: validatePassword, focusedField: $focusedField, field: .password)
                            if !password.isEmpty { PasswordStrengthIndicator(password: password) }
                            SecureFormField(title: "Confirm Password", icon: "lock.fill", placeholder: "Confirm your password",
                                           text: $confirmPassword, isSecure: $isConfirmSecure, error: $confirmPasswordError,
                                           validate: validateConfirmPassword, focusedField: $focusedField, field: .confirmPassword)

                            HStack(alignment: .top, spacing: 12) {
                                Button(action: { agreedToTerms.toggle() }) {
                                    Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                        .foregroundColor(agreedToTerms ? .orange : themeManager.current.secondaryText).font(.title3)
                                }.buttonStyle(PlainButtonStyle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("I agree to the ").foregroundColor(themeManager.current.secondaryText) +
                                    Text("Terms of Service").foregroundColor(.orange).underline() +
                                    Text(" and ").foregroundColor(themeManager.current.secondaryText) +
                                    Text("Privacy Policy").foregroundColor(.orange).underline()
                                }
                                .font(.caption).multilineTextAlignment(.leading)
                                Spacer()
                            }

                            Button(action: {
                                focusedField = nil
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                validateAll()
                                if allValid() && agreedToTerms { attemptRegister() }
                            }) {
                                ZStack {
                                    if isLoading {
                                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        HStack {
                                            Text("Create Account").fontWeight(.semibold)
                                            Image(systemName: "arrow.right")
                                        }
                                    }
                                }
                                .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 50)
                                .background(LinearGradient(gradient: Gradient(colors: [.orange, .orange.opacity(0.8)]),
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                                .cornerRadius(12).shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                                .opacity(agreedToTerms ? 1.0 : 0.6)
                            }
                            .disabled(isLoading || !agreedToTerms).buttonStyle(PlainButtonStyle()).contentShape(Rectangle())

                            if registrationFailed { ErrorCard(message: registrationError) }

                            HStack {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                                Text("OR").font(.caption).foregroundColor(themeManager.current.secondaryText).padding(.horizontal, 16)
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                            }.padding(.vertical, 8)

                            VStack(spacing: 12) {
                                SignInWithAppleButton(.signUp) { request in
                                    request.requestedScopes = [.fullName, .email]
                                } onCompletion: { result in
                                    switch result {
                                    case .success(let authResults):
                                        if let credential = authResults.credential as? ASAuthorizationAppleIDCredential {
                                            let userId = credential.user
                                            let email = credential.email ?? "\(userId)@apple.local"
                                            let fullName = credential.fullName
                                            let displayName = "\(fullName?.givenName ?? "") \(fullName?.familyName ?? "")".trimmingCharacters(in: .whitespaces)
                                            if let tokenData = credential.identityToken,
                                               let tokenStr = String(data: tokenData, encoding: .utf8) {
                                                attemptAppleRegister(email: email, name: displayName.isEmpty ? "Apple User" : displayName, token: tokenStr)
                                            } else {
                                                self.registrationFailed = true; self.registrationError = "Failed to get Apple identity token"
                                            }
                                        }
                                    case .failure(let error):
                                        if (error as NSError).code != 1001 {
                                            self.registrationFailed = true; self.registrationError = "Apple sign-up failed"
                                        }
                                    }
                                }
                                .signInWithAppleButtonStyle(themeManager.current == .dark ? .white : .black)
                                .frame(height: 50).cornerRadius(12)

                                Button(action: {
                                    focusedField = nil
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    handleGoogleRegister()
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Sign up with Google").fontWeight(.medium)
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
                                Text("Already have an account?").foregroundColor(themeManager.current.secondaryText)
                                Button("Log In") { dismiss() }
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
            .navigationBarBackButtonHidden(true)
            .navigationDestination(isPresented: $navigateToDashboard) {
                DashboardView().navigationBarBackButtonHidden(true)
            }
        }
    }

    func validateName() {
        withAnimation(.easeInOut(duration: 0.2)) { nameError = name.isEmpty ? "Name is required" : "" }
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
            passwordError = password.isEmpty ? "Password is required" :
                password.count < 6 ? "Password must be at least 6 characters" : ""
        }
    }
    func validateConfirmPassword() {
        withAnimation(.easeInOut(duration: 0.2)) {
            confirmPasswordError = confirmPassword != password ? "Passwords do not match" : ""
        }
    }
    func validateAll() {
        validateName(); validateEmail(); validatePassword(); validateConfirmPassword()
        if !agreedToTerms { registrationError = "Please agree to the terms and conditions"; registrationFailed = true }
    }
    func allValid() -> Bool {
        nameError.isEmpty && emailError.isEmpty && passwordError.isEmpty && confirmPasswordError.isEmpty
    }

    func attemptRegister() {
        isLoading = true; registrationFailed = false
        guard let url = AppConfig.url(path: "/register") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name, "email": email, "password": password])
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if error != nil { self.registrationFailed = true; self.registrationError = "Network error. Please try again."; return }
                guard let data = data else { self.registrationFailed = true; self.registrationError = "No response from server."; return }
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 409 { self.registrationFailed = true; self.registrationError = "This email is already registered."; return }
                    else if httpResponse.statusCode != 200 { self.registrationFailed = true; self.registrationError = "Registration failed. Please try again."; return }
                }
                do {
                    let resp = try JSONDecoder().decode(RegisterResponse.self, from: data)
                    withAnimation(.spring()) { self.session.login(id: resp.user_id, name: resp.name, token: resp.token, isNewUser: true); self.navigateToDashboard = true }
                } catch { self.registrationFailed = true; self.registrationError = "Unexpected error. Please try again." }
            }
        }.resume()
    }

    private func attemptAppleRegister(email: String, name: String, token: String) {
        isLoading = true; registrationFailed = false
        NetworkManager.shared.appleLogin(email: email, identityToken: token) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let (userId, userName, jwtToken)):
                    let finalName = name.isEmpty ? userName : name
                    withAnimation(.spring()) { self.session.login(id: userId, name: finalName, token: jwtToken, isNewUser: true); self.navigateToDashboard = true }
                case .failure:
                    self.registrationFailed = true; self.registrationError = "Apple sign-up failed. Please try again."
                }
            }
        }
    }

    private func handleGoogleRegister() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            guard let user = result?.user, let idToken = user.idToken?.tokenString else { return }
            self.sendGoogleTokenToBackend(idToken: idToken, email: user.profile?.email ?? "")
        }
    }

    private func sendGoogleTokenToBackend(idToken: String, email: String) {
        guard let url = AppConfig.url(path: "/google_login") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["idToken": idToken, "email": email])
        URLSession.shared.dataTask(with: request) { data, _, error in
            if error != nil {
                DispatchQueue.main.async { self.registrationFailed = true; self.registrationError = "Network error. Please try again." }
                return
            }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let userId = json["user_id"] as? String,
               let name = json["name"] as? String,
               let token = json["token"] as? String {
                DispatchQueue.main.async {
                    withAnimation(.spring()) { self.session.login(id: userId, name: name, token: token, isNewUser: true); self.navigateToDashboard = true }
                }
            } else {
                DispatchQueue.main.async { self.registrationFailed = true; self.registrationError = "Registration failed. Please try again." }
            }
        }.resume()
    }
}

// MARK: - Supporting Views

struct FormField: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let icon: String; let placeholder: String
    @Binding var text: String; @Binding var error: String
    let validate: () -> Void
    var keyboardType: UIKeyboardType = .default
    var focusedField: FocusState<RegisterView.Field?>.Binding
    var field: RegisterView.Field
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundColor(themeManager.current.secondaryText).textCase(.uppercase).tracking(1)
            HStack {
                Image(systemName: icon).foregroundColor(themeManager.current.secondaryText).frame(width: 20)
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .emailAddress ? .none : .words)
                    .foregroundColor(themeManager.current.primaryText)
                    .focused(focusedField, equals: field)
                    .onChange(of: text) { _, _ in validate() }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.current.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(error.isEmpty ? themeManager.current.cardBorder : Color.red.opacity(0.5), lineWidth: 1)))
            if !error.isEmpty { Text(error).font(.caption).foregroundColor(.red).transition(.opacity) }
        }
    }
}

struct SecureFormField: View {
    @EnvironmentObject var themeManager: ThemeManager
    let title: String; let icon: String; let placeholder: String
    @Binding var text: String; @Binding var isSecure: Bool; @Binding var error: String
    let validate: () -> Void
    var focusedField: FocusState<RegisterView.Field?>.Binding
    var field: RegisterView.Field
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundColor(themeManager.current.secondaryText).textCase(.uppercase).tracking(1)
            HStack {
                Image(systemName: icon).foregroundColor(themeManager.current.secondaryText).frame(width: 20)
                if isSecure {
                    SecureField(placeholder, text: $text).foregroundColor(themeManager.current.primaryText).focused(focusedField, equals: field)
                } else {
                    TextField(placeholder, text: $text).foregroundColor(themeManager.current.primaryText).focused(focusedField, equals: field)
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
                    .stroke(error.isEmpty ? themeManager.current.cardBorder : Color.red.opacity(0.5), lineWidth: 1)))
            .onChange(of: text) { _, _ in validate() }
            if !error.isEmpty { Text(error).font(.caption).foregroundColor(.red).transition(.opacity) }
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
                Text("Password strength:").font(.caption).foregroundColor(.gray)
                Text(strength.text).font(.caption).fontWeight(.semibold).foregroundColor(strength.color)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 4).fill(strength.color)
                        .frame(width: geometry.size.width * strength.progress, height: 4)
                        .animation(.spring(), value: strength.progress)
                }
            }.frame(height: 4)
        }
    }
}

struct ErrorCard: View {
    let message: String
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
            Text(message).foregroundColor(.red).font(.caption)
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1)))
    }
}
