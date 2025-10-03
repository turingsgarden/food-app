//
//  NutritionModels.swift
//  food-app-swift
//
//  Created by Utsav Doshi on 7/19/25.
//

import Foundation
import SwiftUI  // Add this line

// MARK: - Nutrition Data Models

struct NutritionItem: Identifiable, Codable {
    var id = UUID()
    let name: String
    let value: String
    let unit: String
    let reasoning: String?
    
    var displayValue: String {
        return "\(value) \(unit)"
    }
    
    var color: Color {
        switch name.lowercased() {
        case let n where n.contains("calorie"):
            return .red
        case let n where n.contains("protein"):
            return .blue
        case let n where n.contains("carb"):
            return .orange
        case let n where n.contains("fat"):
            return .purple
        case let n where n.contains("fiber"):
            return .green
        case let n where n.contains("sugar"):
            return .yellow
        case let n where n.contains("sodium"):
            return .pink
        default:
            return .gray
        }
    }
    
    var icon: String {
        switch name.lowercased() {
        case let n where n.contains("calorie"):
            return "flame.fill"
        case let n where n.contains("protein"):
            return "bolt.fill"
        case let n where n.contains("carb"):
            return "leaf.fill"
        case let n where n.contains("fat"):
            return "drop.fill"
        case let n where n.contains("fiber"):
            return "circle.grid.2x2.fill"
        case let n where n.contains("sugar"):
            return "heart.fill"
        case let n where n.contains("sodium"):
            return "triangle.fill"
        default:
            return "circle.fill"
        }
    }
}

// MARK: - Nutrition Parser

struct NutritionParser {
    static func parseNutrition(from text: String) -> [NutritionItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [NutritionItem] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines, markdown headers, and lines with dashes
            if trimmedLine.isEmpty ||
               trimmedLine.contains("------") ||
               trimmedLine.hasPrefix("#") ||
               trimmedLine.hasPrefix("**") {
                continue
            }
            
            // Parse pipe-separated values
            let components = trimmedLine.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            
            if components.count >= 3 {
                let name = components[0]
                let value = components[1]
                let unit = components[2]
                let reasoning = components.count > 3 ? components[3] : nil
                
                // Validate that value is numeric
                if !value.isEmpty && (Double(value) != nil || Int(value) != nil) {
                    let item = NutritionItem(
                        name: name,
                        value: value,
                        unit: unit,
                        reasoning: reasoning
                    )
                    items.append(item)
                }
            }
        }
        
        return items
    }
    
    static func extractCalories(from items: [NutritionItem]) -> Int? {
        for item in items {
            if item.name.lowercased().contains("calorie") {
                return Int(item.value)
            }
        }
        return nil
    }
}
