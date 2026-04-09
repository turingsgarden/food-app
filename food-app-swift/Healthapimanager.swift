//
//  Healthapimanager.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//

// HealthAPIManager.swift
// Health Agent — 所有网络请求

import Foundation
import UIKit

class HealthAPIManager {
    static let shared = HealthAPIManager()
    private let base = "https://food-app-swift-qb4k.onrender.com"

    private var token: String? { SessionManager.shared.getAuthToken() }

    // MARK: - Health Profile

    func saveHealthProfile(_ profile: HealthProfile, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(base)/save-health-profile"),
              let token = token else { completion(false, "Auth error"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(profile)
        req.timeoutInterval = 30
        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(false, err.localizedDescription); return }
                completion((resp as? HTTPURLResponse)?.statusCode == 200, nil)
            }
        }.resume()
    }

    func fetchHealthProfile(userId: String, completion: @escaping (HealthProfile?) -> Void) {
        guard let url = URL(string: "\(base)/get-health-profile?user_id=\(userId)"),
              let token = token else { completion(nil); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let profile = try? JSONDecoder().decode(HealthProfile.self, from: data)
                else { completion(nil); return }
                completion(profile)
            }
        }.resume()
    }

    // MARK: - Generate Nutrition Targets

    func generateNutritionTargets(
        profile: HealthProfile,
        goals: [String],
        completion: @escaping (NutritionPlan?, String?) -> Void
    ) {
        guard let url = URL(string: "\(base)/generate-targets"),
              let token = token else { completion(nil, "Auth error"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60
        let payload: [String: Any] = [
            "user_id": profile.userId,
            "profile": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profile))) ?? [:],
            "goals": goals
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(nil, err.localizedDescription); return }
                guard let data = data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let plan = try? JSONDecoder().decode(NutritionPlan.self, from: data)
                else { completion(nil, "Failed to parse nutrition plan"); return }
                completion(plan, nil)
            }
        }.resume()
    }

    // MARK: - Generate Weekly Meal Plan

    func generateWeeklyMealPlan(
        userId: String,
        nutritionPlan: NutritionPlan,
        healthProfile: HealthProfile,
        completion: @escaping (WeeklyMealPlan?, String?) -> Void
    ) {
        guard let url = URL(string: "\(base)/generate-meal-plan"),
              let token = token else { completion(nil, "Auth error"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 90   // AI 生成需要时间
        let payload: [String: Any] = [
            "user_id": userId,
            "nutrition_plan": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(nutritionPlan))) ?? [:],
            "health_profile": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(healthProfile))) ?? [:]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(nil, err.localizedDescription); return }
                guard let data = data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let plan = try? JSONDecoder().decode(WeeklyMealPlan.self, from: data)
                else { completion(nil, "Failed to generate meal plan"); return }
                completion(plan, nil)
            }
        }.resume()
    }

    func fetchCurrentWeekPlan(userId: String, completion: @escaping (WeeklyMealPlan?) -> Void) {
        guard let url = URL(string: "\(base)/get-meal-plan?user_id=\(userId)"),
              let token = token else { completion(nil); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let plan = try? JSONDecoder().decode(WeeklyMealPlan.self, from: data)
                else { completion(nil); return }
                completion(plan)
            }
        }.resume()
    }

    // MARK: - Analyze Meal Photo

    func analyzeMealPhoto(
        imageData: Data,
        userId: String,
        date: String,
        mealType: String,
        plannedMeal: PlannedMeal?,
        remainingPlan: [DayMealPlan],
        completion: @escaping (MealLog?, String?) -> Void
    ) {
        guard let url = URL(string: "\(base)/analyze-meal-photo"),
              let token = token else { completion(nil, "Auth error"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 90

        var payload: [String: Any] = [
            "user_id": userId,
            "date": date,
            "meal_type": mealType,
            "image_base64": imageData.base64EncodedString()
        ]
        if let planned = plannedMeal,
           let plannedData = try? JSONEncoder().encode(planned),
           let plannedJSON = try? JSONSerialization.jsonObject(with: plannedData) {
            payload["planned_meal"] = plannedJSON
        }
        if let remainingData = try? JSONEncoder().encode(remainingPlan),
           let remainingJSON = try? JSONSerialization.jsonObject(with: remainingData) {
            payload["remaining_plan"] = remainingJSON
        }

        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(nil, err.localizedDescription); return }
                guard let data = data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let log = try? JSONDecoder().decode(MealLog.self, from: data)
                else { completion(nil, "Failed to analyze photo"); return }
                completion(log, nil)
            }
        }.resume()
    }

    // MARK: - Image Compression Helper

    func compressImage(_ image: UIImage, maxKB: Int = 500) -> Data? {
        let maxDim: CGFloat = 1024
        let size = image.size
        var newSize = size
        if size.width > maxDim || size.height > maxDim {
            let ratio = min(maxDim / size.width, maxDim / size.height)
            newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        }
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        var compression: CGFloat = 0.8
        var data = resized.jpegData(compressionQuality: compression)
        while let d = data, d.count > maxKB * 1024, compression > 0.1 {
            compression -= 0.1
            data = resized.jpegData(compressionQuality: compression)
        }
        return data
    }
}
