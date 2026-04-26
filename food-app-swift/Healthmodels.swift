//
//  Healthmodels.swift
//  food-app-swift
//
//  Created by Helen Tu on 4/9/26.
//

import Foundation

// MARK: - Health Profile

struct HealthProfile: Codable {
    var userId: String

    var heightCm: Double
    var weightKg: Double
    var age: Int
    var sex: String

  
    var systolicBP: Int?
    var diastolicBP: Int?
    var fastingBloodSugar: Double?
    var totalCholesterol: Double?
    var triglycerides: Double?

    var dietaryPreferences: [String]

    var allergens: [String]

    var bmi: Double { weightKg / ((heightCm / 100) * (heightCm / 100)) }

    var bmiCategory: String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case age, sex
        case systolicBP = "systolic_bp"
        case diastolicBP = "diastolic_bp"
        case fastingBloodSugar = "fasting_blood_sugar"
        case totalCholesterol = "total_cholesterol"
        case triglycerides
        case dietaryPreferences = "dietary_preferences"
        case allergens
    }
}

// MARK: - Health Goals

enum HealthGoal: String, CaseIterable, Codable {
    case loseWeight = "lose_weight"
    case gainMuscle = "gain_muscle"
    case controlBloodSugar = "control_blood_sugar"
    case lowerBloodPressure = "lower_blood_pressure"
    case lowerCholesterol = "lower_cholesterol"
    case improveDigestion = "improve_digestion"
    case boostEnergy = "boost_energy"
    case maintainWeight = "maintain_weight"

    var displayName: String {
        switch self {
        case .loseWeight: return "Lose Weight"
        case .gainMuscle: return "Build Muscle"
        case .controlBloodSugar: return "Control Blood Sugar"
        case .lowerBloodPressure: return "Lower Blood Pressure"
        case .lowerCholesterol: return "Lower Cholesterol"
        case .improveDigestion: return "Improve Digestion"
        case .boostEnergy: return "Boost Energy"
        case .maintainWeight: return "Maintain Weight"
        }
    }

    var icon: String {
        switch self {
        case .loseWeight: return "scalemass.fill"
        case .gainMuscle: return "figure.strengthtraining.traditional"
        case .controlBloodSugar: return "drop.fill"
        case .lowerBloodPressure: return "heart.fill"
        case .lowerCholesterol: return "waveform.path.ecg"
        case .improveDigestion: return "leaf.fill"
        case .boostEnergy: return "bolt.fill"
        case .maintainWeight: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Nutrition Plan (AI Generated)

struct NutritionPlan: Codable {
    var userId: String
    var dailyCalories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int
    var sodiumMg: Int
    var goals: [String]
    var aiAdvice: String
    var foodsToEat: [String]
    var foodsToAvoid: [String]
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dailyCalories = "daily_calories"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sodiumMg = "sodium_mg"
        case goals
        case aiAdvice = "ai_advice"
        case foodsToEat = "foods_to_eat"
        case foodsToAvoid = "foods_to_avoid"
        case createdAt = "created_at"
    }
}

// MARK: - Weekly Meal Plan

struct WeeklyMealPlan: Codable, Identifiable {
    var id: String?
    var userId: String?
    var weekStartDate: String
    var days: [DayMealPlan]
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId = "user_id"
        case weekStartDate = "week_start_date"
        case days
        case createdAt = "created_at"
    }
}

struct DayMealPlan: Codable, Identifiable {
    var id: String { date }
    var date: String
    var dayName: String
    var breakfast: PlannedMeal
    var lunch: PlannedMeal
    var dinner: PlannedMeal
    var totalCalories: Int

    var meals: [PlannedMeal] { [breakfast, lunch, dinner] }

    enum CodingKeys: String, CodingKey {
        case date
        case dayName = "day_name"
        case breakfast, lunch, dinner
        case totalCalories = "total_calories"
    }
}

struct PlannedMeal: Codable, Identifiable {
    var id: String { mealType + (name ?? "") }
    var mealType: String           // "breakfast" / "lunch" / "dinner"
    var name: String?
    var items: [MealItem]
    var totalCalories: Int
    var totalProtein: Int
    var totalCarbs: Int
    var totalFat: Int
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case mealType = "meal_type"
        case name, items
        case totalCalories = "total_calories"
        case totalProtein = "total_protein"
        case totalCarbs = "total_carbs"
        case totalFat = "total_fat"
        case notes
    }
}

struct MealItem: Codable, Identifiable {
    var id = UUID().uuidString
    var food: String
    var amountG: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    enum CodingKeys: String, CodingKey {
        case food
        case amountG = "amount_g"
        case calories, protein, carbs, fat
    }
}

// MARK: - Meal Log (photo compliance)

struct MealLog: Codable, Identifiable {
    var id: String?
    var userId: String?
    var date: String?
    var mealType: String?
    var imageBase64: String?
    var plannedMeal: PlannedMeal?

    var detectedFoods: [String]
    var estimatedCalories: Int
    var estimatedProtein: Int
    var estimatedCarbs: Int
    var estimatedFat: Int
    var complianceScore: Int
    var complianceFeedback: String
    var planAdjustmentNote: String?
    var savedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId = "user_id"
        case date, mealType = "meal_type"
        case imageBase64 = "image_base64"
        case plannedMeal = "planned_meal"
        case detectedFoods = "detected_foods"
        case estimatedCalories = "estimated_calories"
        case estimatedProtein = "estimated_protein"
        case estimatedCarbs = "estimated_carbs"
        case estimatedFat = "estimated_fat"
        case complianceScore = "compliance_score"
        case complianceFeedback = "compliance_feedback"
        case planAdjustmentNote = "plan_adjustment_note"
        case savedAt = "saved_at"
    }
}

// MARK: - Dietary Preferences & Allergens

struct DietaryOption: Identifiable {
    let id: String
    let displayName: String
    let icon: String

    static let all: [DietaryOption] = [
        DietaryOption(id: "no_restriction", displayName: "No Restriction", icon: "circle.grid.2x2.fill"),
        DietaryOption(id: "vegan", displayName: "Vegan", icon: "leaf.fill"),
        DietaryOption(id: "vegetarian", displayName: "Vegetarian", icon: "carrot.fill"),
        DietaryOption(id: "pescatarian", displayName: "Pescatarian", icon: "fish.fill"),
        DietaryOption(id: "gluten_free", displayName: "Gluten-Free", icon: "exclamationmark.triangle.fill"),
        DietaryOption(id: "keto", displayName: "Keto", icon: "drop.fill"),
        DietaryOption(id: "low_fodmap", displayName: "Low FODMAP", icon: "stomach.fill"),
        DietaryOption(id: "halal", displayName: "Halal", icon: "moon.fill"),
    ]
}

struct AllergenOption: Identifiable {
    let id: String
    let displayName: String
    let icon: String

    static let all: [AllergenOption] = [
        AllergenOption(id: "nuts", displayName: "Tree Nuts", icon: "⊘"),
        AllergenOption(id: "peanuts", displayName: "Peanuts", icon: "⊘"),
        AllergenOption(id: "dairy", displayName: "Dairy", icon: "⊘"),
        AllergenOption(id: "eggs", displayName: "Eggs", icon: "⊘"),
        AllergenOption(id: "shellfish", displayName: "Shellfish", icon: "⊘"),
        AllergenOption(id: "fish", displayName: "Fish", icon: "⊘"),
        AllergenOption(id: "gluten", displayName: "Gluten / Wheat", icon: "⊘"),
        AllergenOption(id: "soy", displayName: "Soy", icon: "⊘"),
        AllergenOption(id: "sesame", displayName: "Sesame", icon: "⊘"),
    ]
}

// MARK: - Blood Range Helpers

struct BloodRange {
    let name: String
    let unit: String
    let normal: ClosedRange<Double>
    let warning: ClosedRange<Double>

    static let systolicBP   = BloodRange(name: "Systolic BP",   unit: "mmHg",  normal: 90...120,  warning: 120...139)
    static let diastolicBP  = BloodRange(name: "Diastolic BP",  unit: "mmHg",  normal: 60...80,   warning: 80...89)
    static let bloodSugar   = BloodRange(name: "Fasting Sugar", unit: "mmol/L",normal: 3.9...5.5, warning: 5.6...6.9)
    static let cholesterol  = BloodRange(name: "Cholesterol",   unit: "mmol/L",normal: 0...5.2,   warning: 5.2...6.2)
    static let triglycerides = BloodRange(name: "Triglycerides",unit: "mmol/L",normal: 0...1.7,   warning: 1.7...2.3)
}
// MARK: - Health Report
 
struct HealthReport: Codable {
    var id: String?
    var userId: String?
    var healthScore: Int
    var healthSummary: String
    var statusBadge: String          // "Excellent" / "Good" / "Fair" / "Needs Attention"
    var dailyCalories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int
    var sodiumMg: Int
    var weeklyCalories: Int
    var attentionItems: [AttentionItem]
    var recommendedFoods: [RecommendedFood]
    var foodsToLimit: [String]
    var lifestyleTip: String
    var goals: [String]?
    var createdAt: String?
 
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case userId = "user_id"
        case healthScore = "health_score"
        case healthSummary = "health_summary"
        case statusBadge = "status_badge"
        case dailyCalories = "daily_calories"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sodiumMg = "sodium_mg"
        case weeklyCalories = "weekly_calories"
        case attentionItems = "attention_items"
        case recommendedFoods = "recommended_foods"
        case foodsToLimit = "foods_to_limit"
        case lifestyleTip = "lifestyle_tip"
        case goals
        case createdAt = "created_at"
    }
}
 
struct AttentionItem: Codable, Identifiable {
    var id: String { metric }
    var metric: String
    var currentValue: String
    var status: String    // "normal" / "borderline" / "high" / "low"
    var advice: String
 
    enum CodingKeys: String, CodingKey {
        case metric
        case currentValue = "current_value"
        case status, advice
    }
 
    var statusColor: String {
        switch status {
        case "normal":     return "green"
        case "borderline": return "orange"
        case "high", "low": return "red"
        default:           return "gray"
        }
    }
}
 
struct RecommendedFood: Codable, Identifiable {
    var id: String { food }
    let food:          String
    let reason:        String
    let dishes:        [String]
    let analysisBasis: String?

    enum CodingKeys: String, CodingKey {
        case food, reason, dishes
        case analysisBasis = "analysis_basis"
    }
}
