// Meal.swift

import Foundation

struct Meal: Identifiable, Codable {
    let _id: String
    var id: String { _id }

    let user_id: String
    var dish_prediction: String
    var image_description: String
    var hidden_ingredients: String?  // Changed from 'let' to 'var'
    var nutrition_info: String       // Changed from 'let' to 'var'
    let image_full: String?
    let image_thumb: String?
    let saved_at: String?
    let meal_type: String?
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
        let parts = line.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        // Now expecting 5 parts: name | min | max | unit | visibility
        guard parts.count == 5 else { return nil }

        let name = parts[0]
        let min = parts[1]
        let max = parts[2]
        let unit = parts[3]
        let visibility = parts[4]

        return "\(name) — \(min)-\(max) \(unit) (\(visibility))"
    }
}

func parseNutritionLines(from text: String) -> [String] {
    text.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        // name | min | max | unit
        guard parts.count == 4 else { return nil }

        let name = parts[0]
        let min = parts[1]
        let max = parts[2]
        let unit = parts[3]

        return "\(name) — \(min)-\(max) \(unit)"
    }
}

// In Meal.swift, replace the extractCalories function with this: average

func extractCalories(from text: String) -> Int? {
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        // Calories | min | max | kcal
        if parts.count >= 3,
           parts[0].lowercased().contains("calories"),
           let min = Int(parts[1].replacingOccurrences(of: ",", with: "")),
           let max = Int(parts[2].replacingOccurrences(of: ",", with: "")) {

            return (min + max) / 2   // return average
        }
    }
    return nil
}
