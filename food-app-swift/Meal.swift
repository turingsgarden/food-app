// Meal.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/8/26.

import Foundation

struct Meal: Identifiable, Codable {
    let _id: String
    var id: String { _id }
    let user_id: String?
    var dish_prediction: String
    var image_description: String
    var hidden_ingredients: String?
    var nutrition_info: String
    let image_full: String?
    let image_thumb: String?
    let saved_at: String?
    let meal_type: String?
    let from_diet_plan: Bool?
    let compliance_score: Int?
    var aiInsight: MealInsight?          // ← AI meal analysis, saved once on creation

    enum CodingKeys: String, CodingKey {
        case _id, user_id, dish_prediction, image_description
        case hidden_ingredients, nutrition_info
        case image_full, image_thumb, saved_at, meal_type
        case from_diet_plan, compliance_score
        case aiInsight = "ai_insight"
    }
}

struct GeminiResult: Codable {
    let image_description: String
    let dish_prediction: String
    let hidden_ingredients: String?
    let nutrition_info: String
}

struct NutritionRecalculationResult: Codable {
    let nutrition_info: String
}

func parseIngredientLines(from text: String) -> [String] {
    text.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "|")
        guard parts.count == 4 else { return nil }
        return "\(parts[0].trimmingCharacters(in: .whitespaces)) — \(parts[1].trimmingCharacters(in: .whitespaces)) \(parts[2].trimmingCharacters(in: .whitespaces)) (\(parts[3].trimmingCharacters(in: .whitespaces)))"
    }
}

func parseNutritionLines(from text: String) -> [String] {
    text.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "|")
        guard parts.count == 4 else { return nil }
        return "\(parts[0].trimmingCharacters(in: .whitespaces)) — \(parts[1].trimmingCharacters(in: .whitespaces)) \(parts[2].trimmingCharacters(in: .whitespaces)) (\(parts[3].trimmingCharacters(in: .whitespaces)))"
    }
}

func extractCalories(from text: String) -> Int? {
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "|")
        if parts.count >= 2, parts[0].lowercased().contains("calories") {
            let valueString = parts[1].trimmingCharacters(in: .whitespaces)
            let cleanedValue = valueString.replacingOccurrences(of: ",", with: "")
            return Int(cleanedValue)
        }
    }
    return nil
}
