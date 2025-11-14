import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss   // ← allows going back
    
    @State private var email: String = ""
    @State private var code: String = ""
    @State private var message: String = ""
    @State private var isSending = false
    @State private var isVerifying = false
    @State private var showResetPassword = false

    
    var body: some View {
        VStack(spacing: 24) {
            
            // -------------------------------
            // Back Button
            // -------------------------------
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(10)
                }
                Spacer()
            }
            
            // Title
            Text("Reset Password")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.white)
                .padding(.top, 10)
            
            // Email Field
            TextField("Enter your email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.white)
            
            // Send Code Button
            Button(action: sendResetCode) {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Text("Send Verification Code")
                        .foregroundColor(.white)
                        .bold()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange)
            .cornerRadius(12)
            .disabled(isSending)
            
            // Code Field
            TextField("Enter verification code", text: $code)
                .keyboardType(.numberPad)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.white)
            
            // Verify Button
            Button(action: verifyCode) {
                if isVerifying {
                    ProgressView().tint(.white)
                } else {
                    Text("Verify Code")
                        .foregroundColor(.white)
                        .bold()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.green)
            .cornerRadius(12)
            .disabled(isVerifying)
            
            // Message
            if !message.isEmpty {
                Text(message)
                    .foregroundColor(.red)
                    .padding(.top, 10)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showResetPassword) {
            ResetPasswordView(email: email){
                dismiss()   // go back to LoginView
            }
        }
    }
    
    // MARK: - Send Reset Code
    private func sendResetCode() {
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/send_password_reset_code") else { return }
        
        isSending = true
        message = ""
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["email": email])
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { isSending = false }
            
            if let error = error {
                DispatchQueue.main.async { message = error.localizedDescription }
                return
            }
            
            guard let http = response as? HTTPURLResponse else { return }
            
            if http.statusCode == 200 {
                DispatchQueue.main.async { message = "Verification code sent!" }
            } else {
                DispatchQueue.main.async { message = "Email not registered. Fail to send code." }
            }
        }.resume()
    }
    
    // MARK: - Verify Code
    private func verifyCode() {
        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/verify_code") else { return }
        
        isVerifying = true
        message = ""
        
        let body = ["email": email, "code": code]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { isVerifying = false }
            
            if let error = error {
                DispatchQueue.main.async { message = error.localizedDescription }
                return
            }
            
            guard let http = response as? HTTPURLResponse else { return }
            
            if http.statusCode == 200 {
                DispatchQueue.main.async {
                    message = "Code verified!"
                    showResetPassword = true
                }
            } else {
                DispatchQueue.main.async { message = "Invalid or expired code." }
            }
        }.resume()
    }
}
