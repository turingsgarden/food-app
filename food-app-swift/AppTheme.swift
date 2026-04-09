//
//  AppTheme.swift
//  food-app-swift
//
//  Created by Helen Tu on 2/4/26.
//
import SwiftUI

enum AppTheme: String, CaseIterable {
    case light, dark

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }


    var isDark: Bool { self == .dark }

    var background: Color {
        switch self {
        case .dark: return Color.black
        case .light: return Color(UIColor.systemBackground)
        }
    }

    var cardBackground: Color {
        switch self {
        case .dark: return Color.white.opacity(0.06)
 
        case .light: return Color(UIColor.systemBackground)
        }
    }

    var primaryText: Color {
        switch self {
        case .dark: return .white
        case .light: return Color(UIColor.label)
        }
    }

    var secondaryText: Color {
        switch self {
        case .dark: return .gray
        case .light: return Color(UIColor.secondaryLabel)
        }
    }

    var cardBorder: Color {
        switch self {
        case .dark: return Color.white.opacity(0.10)

        case .light: return Color(UIColor.separator).opacity(0.5)
        }
    }

    var inputBackground: Color {
        switch self {
        case .dark: return Color.white.opacity(0.08)

        case .light: return Color(UIColor.secondarySystemBackground)
        }
    }
}

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: AppTheme {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: "app_theme")
        }
    }

    private init() {

        let saved = UserDefaults.standard.string(forKey: "app_theme") ?? "light"
        self.current = AppTheme(rawValue: saved) ?? .light
    }
}
