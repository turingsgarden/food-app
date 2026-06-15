import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let email: String
    let goBackToLogin: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var message = ""
    @State private var messageColor: Color = .red
    @State private var isSubmitting = false
    @State private var finished = false
    @State private var shouldDismissAfterAlert = false

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(themeManager.current.primaryText)
                        .font(.title2)
                        .padding(.top, 10)
                        .padding(.leading, 5)
                }
                Spacer()
            }

            Text("Create New Password")
                .font(.largeTitle).bold()
                .foregroundColor(themeManager.current.primaryText)
                .padding(.top, 10)

            SecureField("New password", text: $newPassword)
                .padding()
                .background(themeManager.current.inputBackground)
                .cornerRadius(10)
                .foregroundColor(themeManager.current.primaryText)

            SecureField("Confirm password", text: $confirmPassword)
                .padding()
                .background(themeManager.current.inputBackground)
                .cornerRadius(10)
                .foregroundColor(themeManager.current.primaryText)

            Button(action: submitNewPassword) {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Update Password").foregroundColor(.white).bold()
                }
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.orange)
            .cornerRadius(12)
            .disabled(isSubmitting)

            if !message.isEmpty {
                Text(message).foregroundColor(messageColor).padding(.top, 10)
            }

            Spacer()
        }
        .padding()
        .background(themeManager.current.background.ignoresSafeArea())
        .preferredColorScheme(themeManager.current.colorScheme)
        .navigationBarBackButtonHidden(true)
        .alert("Password Reset Successful!", isPresented: $finished) {
            Button("OK") { shouldDismissAfterAlert = true }
        }
        .onChange(of: shouldDismissAfterAlert) { value in
            if value { dismiss(); goBackToLogin() }
        }
    }

    private func submitNewPassword() {
        guard newPassword == confirmPassword else {
            message = "Passwords do not match"; messageColor = .red; return
        }
        guard newPassword.count >= 6 else {
            message = "Password must be at least 6 characters"; messageColor = .red; return
        }
        guard let url = AppConfig.url(path: "/reset_password") else { return }

        isSubmitting = true; message = ""

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email, "new_password": newPassword])

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async { isSubmitting = false }
            if let error = error {
                DispatchQueue.main.async { message = error.localizedDescription; messageColor = .red }
                return
            }
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 200 {
                DispatchQueue.main.async { message = "Password updated!"; messageColor = .green; finished = true }
                return
            }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errMsg = json["error"] as? String {
                DispatchQueue.main.async { message = errMsg; messageColor = .red }
            } else {
                DispatchQueue.main.async { message = "Failed to update password."; messageColor = .red }
            }
        }.resume()
    }
}
