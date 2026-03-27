//
//  Recalculationmanager.swift
//  food-app-swift
//
//  Created by Helen Tu on 3/13/26.
//

import Foundation
import SwiftUI

// MARK: - Recalculation State

enum RecalculationState {
    case idle
    case calculating
    case succeeded(nutritionInfo: String, mealId: String)
    case failed(mealId: String)
}

// MARK: - RecalculationManager

class RecalculationManager: ObservableObject {
    static let shared = RecalculationManager()

    @Published var state: RecalculationState = .idle
    @Published var isVisible: Bool = false

    private init() {}

    var isCalculating: Bool {
        if case .calculating = state { return true }
        return false
    }

    func startRecalculation(
        mealId: String,
        ingredients: String,
        mealData: [String: Any],
        onComplete: @escaping (String?) -> Void
    ) {
        DispatchQueue.main.async {
            self.state = .calculating
            self.isVisible = true
        }

        NetworkManager.shared.recalculateNutritionBackground(ingredients: ingredients) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let data):
                let nutritionInfo = data.nutrition_info
                DispatchQueue.main.async {
                    self.state = .succeeded(nutritionInfo: nutritionInfo, mealId: mealId)
                }
                // Now save to backend
                var updatedMealData = mealData
                updatedMealData["nutrition_info"] = nutritionInfo
                self.saveMealToBackend(mealData: updatedMealData) { success in
                    DispatchQueue.main.async {
                        if success {
                            NotificationCenter.default.post(
                                name: Notification.Name("NutritionRecalculated"),
                                object: nil,
                                userInfo: [
                                    "mealId": mealId,
                                    "nutritionInfo": nutritionInfo,
                                    "imageDescription": mealData["image_description"] as? String ?? ""
                                ]
                            )
                            onComplete(nutritionInfo)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                self.isVisible = false
                                self.state = .idle
                            }
                        } else {
                            self.state = .failed(mealId: mealId)
                            onComplete(nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                                self.isVisible = false
                                self.state = .idle
                            }
                        }
                    }
                }
            case .failure:
                DispatchQueue.main.async {
                    self.state = .failed(mealId: mealId)
                    onComplete(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        self.isVisible = false
                        self.state = .idle
                    }
                }
            }
        }
    }

    private func saveMealToBackend(mealData: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let token = SessionManager.shared.getAuthToken(),
              let url = URL(string: "https://food-app-swift-qb4k.onrender.com/update-meal"),
              let jsonData = try? JSONSerialization.data(withJSONObject: mealData) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    func dismiss() {
        isVisible = false
        state = .idle
    }
}

// MARK: - Floating Progress Button

struct RecalculationFloatingButton: View {
    @ObservedObject var manager = RecalculationManager.shared
    @State private var showDetail = false

    var body: some View {
        if manager.isVisible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    button
                        .padding(.trailing, 20)
                        .padding(.bottom, 100)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: manager.isVisible)
                }
            }
        }
    }

    @ViewBuilder
    private var button: some View {
        Button(action: { showDetail = true }) {
            HStack(spacing: 10) {
                icon
                label
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(buttonColor)
                    .shadow(color: buttonColor.opacity(0.5), radius: 10, x: 0, y: 4)
            )
        }
        .sheet(isPresented: $showDetail) {
            RecalculationDetailSheet(manager: manager)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch manager.state {
        case .calculating:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.85)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .bold))
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .bold))
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var label: some View {
        switch manager.state {
        case .calculating:
            Text("Recalculating...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        case .succeeded:
            Text("Nutrition updated!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        case .failed:
            Text("Recalculation failed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        case .idle:
            EmptyView()
        }
    }

    private var buttonColor: Color {
        switch manager.state {
        case .calculating: return Color.orange
        case .succeeded: return Color.green
        case .failed: return Color.red
        case .idle: return Color.gray
        }
    }
}

// MARK: - Detail Sheet (tapping the button)

struct RecalculationDetailSheet: View {
    @ObservedObject var manager: RecalculationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 28) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                statusIcon
                statusTitleView
                statusSubtitleView
                if case .failed = manager.state {
                    Button("Dismiss") {
                        manager.dismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .padding()
        }
        .presentationDetents([.height(320)])
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch manager.state {
        case .calculating:
            ZStack {
                Circle().fill(Color.orange.opacity(0.15)).frame(width: 80, height: 80)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .scaleEffect(1.5)
            }
        case .succeeded:
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
            }
        case .failed:
            ZStack {
                Circle().fill(Color.red.opacity(0.15)).frame(width: 80, height: 80)
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.red)
            }
        case .idle:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch manager.state {
        case .calculating: return "Recalculating Nutrition"
        case .succeeded: return "Nutrition Updated!"
        case .failed: return "Recalculation Failed"
        case .idle: return ""
        }
    }

    private var statusSubtitle: String {
        switch manager.state {
        case .calculating: return "Analyzing your ingredients with AI.\nYou can browse freely while this runs."
        case .succeeded: return "Your meal's nutrition info has been\nupdated successfully."
        case .failed: return "Could not recalculate nutrition.\nYour other changes were saved."
        case .idle: return ""
        }
    }

    @ViewBuilder
    private var statusTitleView: some View {
        Text(statusTitle)
            .font(.title3.bold())
            .foregroundColor(.white)
    }

    @ViewBuilder
    private var statusSubtitleView: some View {
        Text(statusSubtitle)
            .font(.subheadline)
            .foregroundColor(.gray)
            .multilineTextAlignment(.center)
    }
}
