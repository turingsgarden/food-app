//
//  Healthapimanager.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//

import Foundation
import UIKit

// MARK: - Timeout constants (change in one place, applies everywhere)
private enum Timeout {
    static let short: TimeInterval   = 15   // water, exercise, profile reads
    static let standard: TimeInterval = 30  // most reads/writes
    static let long: TimeInterval    = 60   // generate-targets, generate-health-report
    static let upload: TimeInterval  = 120  // analyze-meal-photo (Gemini heavy)
}

private struct TraceResponse: Codable {
    let request_id: String
    let steps: [TraceStep]
}

class HealthAPIManager {
    static let shared = HealthAPIManager()
    private let base = "https://food-app-swift-qb4k.onrender.com"
    private var keepAliveTimer: Timer?

    private var token: String? { SessionManager.shared.getAuthToken() }

    // MARK: - Keep-Alive

    func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 25 * 60, repeats: true) { _ in
            guard let url = URL(string: "\(self.base)/ping") else { return }
            URLSession.shared.dataTask(with: url) { _, _, _ in
                print("🔄 Keep-alive ping sent")
            }.resume()
        }
        // immediate ping on start
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

    enum HealthProfileFetchOutcome {
        case found(HealthProfile)
        case notFound
        case failure(String)
    }

    func fetchHealthProfileOutcome(
        userId: String,
        completion: @escaping (HealthProfileFetchOutcome) -> Void
    ) {
        guard let url = URL(string: "\(base)/get-health-profile"),
              let token = token else {
            completion(.failure("Authentication required"))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = Timeout.standard
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(err.localizedDescription))
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    completion(.failure("Invalid response"))
                    return
                }
                switch http.statusCode {
                case 200:
                    guard let data = data,
                          let profile = try? JSONDecoder().decode(HealthProfile.self, from: data)
                    else {
                        completion(.failure("Failed to parse health profile"))
                        return
                    }
                    completion(.found(profile))
                case 404:
                    completion(.notFound)
                case 401:
                    completion(.failure("Session expired - please log in again"))
                default:
                    completion(.failure("Server error (\(http.statusCode))"))
                }
            }
        }.resume()
    }

    func saveHealthProfile(_ profile: HealthProfile, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(base)/save-health-profile"),
              let token = token else { completion(false, "Auth error"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(profile)
        req.timeoutInterval = Timeout.standard
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(false, err.localizedDescription); return }
                guard let http = resp as? HTTPURLResponse else {
                    completion(false, "No response from server")
                    return
                }
                if http.statusCode == 200 {
                    completion(true, nil)
                    return
                }
                var message = "Failed to save health profile"
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    message = error
                } else if http.statusCode == 401 {
                    message = "Session expired - please log in again"
                }
                completion(false, message)
            }
        }.resume()
    }

    func fetchHealthProfile(userId: String, completion: @escaping (HealthProfile?) -> Void) {
        fetchHealthProfileOutcome(userId: userId) { outcome in
            if case .found(let profile) = outcome {
                completion(profile)
            } else {
                completion(nil)
            }
        }
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
        req.timeoutInterval = Timeout.long
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

    // MARK: - Weekly Meal Plan

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
        req.timeoutInterval = Timeout.standard

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
        req.timeoutInterval = Timeout.short

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
        req.timeoutInterval = Timeout.standard
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

    // MARK: - Analyze Meal Photo (with retry)

    func analyzeMealPhoto(
        imageData: Data,
        userId: String,
        date: String,
        mealType: String,
        plannedMeal: PlannedMeal?,
        remainingPlan: [DayMealPlan],
        retryCount: Int = 0,                          // ← internal retry counter
        completion: @escaping (MealLog?, String?) -> Void
    ) {
        guard let url = URL(string: "\(base)/analyze-meal-photo"),
              let token = token else { completion(nil, "Auth error"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = Timeout.upload          // 120s – Gemini can be slow

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
            // --- success path ---
            if let data = data,
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let log = try? JSONDecoder().decode(MealLog.self, from: data) {
                DispatchQueue.main.async { completion(log, nil) }
                return
            }

            // --- failure path: retry once after 3 s ---
            let maxRetries = 1
            if retryCount < maxRetries {
                let reason = err?.localizedDescription ?? "status \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
                print("⚠️ analyzeMealPhoto failed (\(reason)), retrying in 3 s… (attempt \(retryCount + 1)/\(maxRetries))")
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    self.analyzeMealPhoto(
                        imageData: imageData,
                        userId: userId,
                        date: date,
                        mealType: mealType,
                        plannedMeal: plannedMeal,
                        remainingPlan: remainingPlan,
                        retryCount: retryCount + 1,
                        completion: completion
                    )
                }
            } else {
                let msg = err?.localizedDescription ?? "Failed to analyze photo"
                DispatchQueue.main.async { completion(nil, msg) }
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

    // MARK: - Execution Trace

    func fetchTrace(
        requestId: String,
        completion: @escaping (Result<[TraceStep], Error>) -> Void
    ) {
        guard let url = URL(string: "\(base)/trace/\(requestId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? requestId)")
        else {
            completion(.failure(NSError(domain: "HealthAPIManager", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = Timeout.short
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err {
                    completion(.failure(err))
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    completion(.failure(NSError(domain: "HealthAPIManager", code: -2,
                                                userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                    return
                }
                if http.statusCode == 404 {
                    completion(.failure(NSError(domain: "HealthAPIManager", code: 404,
                                                userInfo: [NSLocalizedDescriptionKey: "Trace not found"])))
                    return
                }
                guard http.statusCode == 200,
                      let data = data,
                      let trace = try? JSONDecoder().decode(TraceResponse.self, from: data)
                else {
                    completion(.failure(NSError(domain: "HealthAPIManager", code: http.statusCode,
                                                userInfo: [NSLocalizedDescriptionKey: "Failed to load trace"])))
                    return
                }
                completion(.success(trace.steps))
            }
        }.resume()
    }
}

// MARK: - Health Report

extension HealthAPIManager {

    func fetchHealthReport(completion: @escaping (HealthReport?) -> Void) {
        guard let url = URL(string: "\(base)/get-health-report"),
              let token = token else { completion(nil); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = Timeout.standard
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let report = try? JSONDecoder().decode(HealthReport.self, from: data)
                else { completion(nil); return }
                completion(report)
            }
        }.resume()
    }

    func generateHealthReport(
        goals: [String] = [],
        force: Bool = false,
        completion: @escaping (HealthReport?, String?) -> Void
    ) {
        guard let url = URL(string: "\(base)/generate-health-report"),
              let token = token else { completion(nil, "Auth error"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = Timeout.long
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["goals": goals, "force": force])
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let err = err { completion(nil, err.localizedDescription); return }
                guard let data = data,
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let report = try? JSONDecoder().decode(HealthReport.self, from: data)
                else {
                    completion(nil, "Failed to generate health report")
                    return
                }
                completion(report, nil)
            }
        }.resume()
    }
}
