//
//  EditPersonalInfoView.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/14/26.
//

import SwiftUI

struct EditPersonalInfoView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var session = SessionManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var gender: String = "Female"

    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMsg = ""

    let genders = ["Male", "Female", "Non-binary", "Prefer not to say"]

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.current.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(themeManager.current.inputBackground)
                                    .frame(width: 80, height: 80)
                                Text(String(displayName.prefix(1)).uppercased())
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundColor(themeManager.current.primaryText)
                            }
                            Text("Personal Info")
                                .font(.system(size: 13))
                                .foregroundColor(themeManager.current.secondaryText)
                        }
                        .padding(.top, 20).padding(.bottom, 28)

                        
                        VStack(spacing: 1) {
                            infoRow(icon: "person.fill", label: "Name") {
                                TextField("Your name", text: $displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(themeManager.current.primaryText)
                                    .multilineTextAlignment(.trailing)
                            }

                            infoRow(icon: "envelope.fill", label: "Email") {
                                Text(email.isEmpty ? "—" : email)
                                    .font(.system(size: 15))
                                    .foregroundColor(themeManager.current.secondaryText)
                            }

                            infoRow(icon: "calendar", label: "Date of Birth") {
                                DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                                    .labelsHidden()
                                    .colorScheme(themeManager.current == .dark ? .dark : .light)
                            }

                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(themeManager.current.secondaryText)
                                        .frame(width: 20)
                                    Text("Gender")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(themeManager.current.primaryText)
                                    Spacer()
                                }

                                HStack(spacing: 8) {
                                    ForEach(["Male", "Female", "Other"], id: \.self) { g in
                                        Button(action: { gender = g }) {
                                            Text(g)
                                                .font(.system(size: 13, weight: gender == g ? .bold : .regular))
                                                .foregroundColor(gender == g
                                                    ? (themeManager.current == .dark ? .black : .white)
                                                    : themeManager.current.primaryText)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(RoundedRectangle(cornerRadius: 10)
                                                    .fill(gender == g
                                                          ? (themeManager.current == .dark ? Color.white : Color.black)
                                                          : themeManager.current.inputBackground))
                                                .overlay(RoundedRectangle(cornerRadius: 10)
                                                    .stroke(themeManager.current.cardBorder, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 16)
                            .background(themeManager.current.cardBackground)
                        }
                        .background(themeManager.current.cardBackground)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(themeManager.current.cardBorder, lineWidth: 1))
                        .padding(.horizontal, 20)

                        
                        Button(action: save) {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(
                                        tint: themeManager.current == .dark ? .black : .white)).scaleEffect(0.85)
                                }
                                Text(isSaving ? "Saving…" : "Save Changes")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(themeManager.current == .dark ? .black : .white)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(themeManager.current == .dark ? Color.white : Color.black)
                            .cornerRadius(16)
                        }
                        .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).count < 2)
                        .padding(.horizontal, 20).padding(.top, 28)

                        Spacer(minLength: 40)
                    }
                }
            }
            .preferredColorScheme(themeManager.current.colorScheme)
            .navigationTitle("Personal Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(themeManager.current.primaryText)
                }
            }
            .onAppear { loadCurrentInfo() }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMsg) }
        }
    }

    // MARK: - Row Component

    func infoRow<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.current.secondaryText)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(themeManager.current.primaryText)
                Spacer()
                value()
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            Divider().background(themeManager.current.cardBorder).padding(.leading, 50)
        }
    }

    // MARK: - Load / Save

    func loadCurrentInfo() {
        displayName = session.userName

        guard let token = session.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/get-login-methods") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONDecoder().decode([String: String].self, from: data) else { return }
            DispatchQueue.main.async { self.email = json["email"] ?? "" }
        }.resume()

       
        if let profile = ProfileManager.shared.userProfile {
            gender = profile.gender
        
            let approxBirth = Calendar.current.date(byAdding: .year, value: -profile.age, to: Date()) ?? Date()
            dateOfBirth = approxBirth
        }
    }

    func save() {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isSaving = true

        guard let token = session.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/update_name") else {
            isSaving = false; errorMsg = "Server error"; showError = true; return
        }
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": trimmed])

        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                self.isSaving = false
                if error != nil { self.errorMsg = "Network error"; self.showError = true; return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.session.userName = trimmed
                    ProfileManager.shared.fetchProfile(force: true)
                    self.dismiss()
                } else {
                    self.errorMsg = "Failed to save"; self.showError = true
                }
            }
        }.resume()
    }
}
