import SwiftUI

struct ResetPasswordView: View {
    let email: String
    let goBackToLogin: () -> Void   // closure from ForgotPasswordView

    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message = ""
    @State private var messageColor: Color = .red
    @State private var isSubmitting = false
    @State private var finished = false

    // NEW: This allows dismissing AFTER the alert closes
    @State private var shouldDismissAfterAlert = false

    var body: some View {
        VStack(spacing: 24) {

            // ---------------------------
            // Back Button
            // ---------------------------
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(.top, 10)
                        .padding(.leading, 5)
                }
                Spacer()
            }

            Text("Create New Password")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.white)
                .padding(.top, 10)

            SecureField("New password", text: $newPassword)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.white)

            SecureField("Confirm password", text: $confirmPassword)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(10)
                .foregroundColor(.white)

            Button(action: submitNewPassword) {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Update Password")
                        .foregroundColor(.white)
                        .bold()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.orange)
            .cornerRadius(12)
            .disabled(isSubmitting)

            if !message.isEmpty {
                Text(message)
                    .foregroundColor(messageColor)
                    .padding(.top, 10)
            }

            Spacer()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)

        // ---------------------------
        // Alert shown after success
        // ---------------------------
        .alert("Password Reset Successful!", isPresented: $finished) {
            Button("OK") {
                shouldDismissAfterAlert = true   // <-- triggers dismissal
            }
        }

        // ---------------------------
        // Handles dismiss after alert
        // ---------------------------
        .onChange(of: shouldDismissAfterAlert) { value in
            if value {
                dismiss()           // closes ResetPasswordView
                goBackToLogin()     // closes ForgotPasswordView → back to Login
            }
        }
    }

    // MARK: - Submit New Password
    private func submitNewPassword() {
        guard newPassword == confirmPassword else {
            message = "Passwords do not match"
            messageColor = .red
            return
        }

        guard newPassword.count >= 6 else {
            message = "Password must be at least 6 characters"
            messageColor = .red
            return
        }

        guard let url = URL(string: "https://food-app-swift-qb4k.onrender.com/reset_password") else { return }

        isSubmitting = true
        message = ""

        let body: [String: Any] = [
            "email": email,
            "new_password": newPassword
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { isSubmitting = false }

            if let error = error {
                DispatchQueue.main.async {
                    message = error.localizedDescription
                    messageColor = .red
                }
                return
            }

            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 200 {
                DispatchQueue.main.async {
                    message = "Password updated successfully!"
                    messageColor = .green
                    finished = true   // <-- triggers alert
                }
                return
            }

            // Handle backend error JSON
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errMsg = json["error"] as? String {
                DispatchQueue.main.async {
                    message = errMsg
                    messageColor = .red
                }
            } else {
                DispatchQueue.main.async {
                    message = "Failed to update password."
                    messageColor = .red
                }
            }
        }.resume()
    }
}
