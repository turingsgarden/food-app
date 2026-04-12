//
//  Healthapimanager.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//

// HealthAPIManager.swift
// Health Agent — 所有网络请求
// 包含：Keep-alive 防休眠 + 异步生成餐食计划（轮询）

import Foundation
import UIKit

class HealthAPIManager {
    static let shared = HealthAPIManager()
    private let base = "https://food-app-swift-qb4k.onrender.com"
    private var keepAliveTimer: Timer?

    private var token: String? { SessionManager.shared.getAuthToken() }

    // MARK: - Keep-Alive（防止 Render 冷启动）

    func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 25 * 60, repeats: true) { _ in
            guard let url = URL(string: "\(self.base)/ping") else { return }
            URLSession.shared.dataTask(with: url) { _, _, _ in
                print("🔄 Keep-alive ping sent")
            }.resume()
        }
        if let url = URL(string: "\(base)/ping") {
            URLSession.shared.dataTask(with: url) { _, _, _ in
                print("🔄 Initial ping to wake up server")
            }.resume()
        }
    }

    func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

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
        guard let url = URL(string: "\(base)/get-health-profile"),
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

    // MARK: - Generate Weekly Meal Plan（异步提交 + 轮询）

    func generateWeeklyMealPlan(
        userId: String,
        nutritionPlan: NutritionPlan,
        healthProfile: HealthProfile,
        days: Int = 7,
        mealsPerDay: Int = 3,
        onProgress: ((String) -> Void)? = nil,
        completion: @escaping (WeeklyMealPlan?, String?) -> Void
    ) {
        guard let url = URL(string: "\(base)/generate-meal-plan-async"),
              let token = token else { completion(nil, "Auth error"); return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        let payload: [String: Any] = [
            "nutrition_plan": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(nutritionPlan))) ?? [:],
            "health_profile": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(healthProfile))) ?? [:],
            "days": days,
            "meals_per_day": mealsPerDay
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                DispatchQueue.main.async { completion(nil, err.localizedDescription) }
                return
            }
            guard let data = data,
                  (resp as? HTTPURLResponse)?.statusCode == 202,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jobId = json["job_id"] as? String
            else {
                DispatchQueue.main.async { completion(nil, "Failed to start generation") }
                return
            }
            print("🍽️ Meal plan job started: \(jobId)")
            DispatchQueue.main.async { onProgress?("Generating your meal plan…") }
            self.pollMealPlanJob(jobId: jobId, token: token, retries: 40, onProgress: onProgress, completion: completion)
        }.resume()
    }

    private func pollMealPlanJob(
        jobId: String,
        token: String,
        retries: Int,
        onProgress: ((String) -> Void)?,
        completion: @escaping (WeeklyMealPlan?, String?) -> Void
    ) {
        guard retries > 0 else {
            DispatchQueue.main.async { completion(nil, "Generation is taking too long, please try again") }
            return
        }

        guard let url = URL(string: "\(base)/meal-plan-status/\(jobId)") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    self.pollMealPlanJob(jobId: jobId, token: token, retries: retries - 1, onProgress: onProgress, completion: completion)
                }
                return
            }

            let status = json["status"] as? String ?? ""
            print("📊 Job status: \(status) | retries left: \(retries)")

            switch status {
            case "done":
                guard let resultObj = json["result"],
                      let resultData = try? JSONSerialization.data(withJSONObject: resultObj),
                      let plan = try? JSONDecoder().decode(WeeklyMealPlan.self, from: resultData)
                else {
                    DispatchQueue.main.async { completion(nil, "Failed to parse meal plan") }
                    return
                }
                DispatchQueue.main.async { completion(plan, nil) }

            case "error":
                let errMsg = json["error"] as? String ?? "Unknown error"
                DispatchQueue.main.async { completion(nil, errMsg) }

            default:
                let elapsed = (40 - retries) * 3
                DispatchQueue.main.async { onProgress?("Still generating… (\(elapsed)s)") }
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    self.pollMealPlanJob(jobId: jobId, token: token, retries: retries - 1, onProgress: onProgress, completion: completion)
                }
            }
        }.resume()
    }

    // MARK: - Fetch Current Week Plan

    func fetchCurrentWeekPlan(userId: String, completion: @escaping (WeeklyMealPlan?) -> Void) {
        guard let url = URL(string: "\(base)/get-meal-plan"),
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
