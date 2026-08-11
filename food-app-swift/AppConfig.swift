import Foundation

/// Runtime configuration injected per Xcode build flavor (Production vs Dev-William).
// enum AppConfig {
//   // private static let productionFallback = "https://food-app-swift-qb4k.onrender.com"
//   private static let productionFallback = "https://food-app-swift-afsara-staging.onrender.com"

//   static let apiBaseURL: String = {
//     guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String else {
//       return productionFallback
//     }
//     let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
//     guard !trimmed.isEmpty, !trimmed.contains("$(") else {
//       return productionFallback
//     }
//     return trimmed
//   }()
//   // static let apiBaseURL = "http://127.0.0.1:5001"

//   static let developerLabel: String = {
//     guard let raw = Bundle.main.object(forInfoDictionaryKey: "DEVELOPER_LABEL") as? String else {
//       return "production"
//     }
//     let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
//     guard !trimmed.isEmpty, !trimmed.contains("$(") else {
//       return "production"
//     }
//     return trimmed
//   }()

//   static func url(path: String) -> URL? {
//     let normalizedBase =
//       apiBaseURL.hasSuffix("/")
//       ? String(apiBaseURL.dropLast())
//       : apiBaseURL
//     let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
//     return URL(string: normalizedBase + normalizedPath)
//   }
// }

enum AppConfig {
  static let apiBaseURL =
    "https://food-app-swift-afsara-staging.onrender.com"

  static let developerLabel = "afsara-staging"

  static func url(path: String) -> URL? {
    let normalizedBase =
      apiBaseURL.hasSuffix("/")
      ? String(apiBaseURL.dropLast())
      : apiBaseURL

    let normalizedPath =
      path.hasPrefix("/")
      ? path
      : "/\(path)"

    return URL(
      string: normalizedBase + normalizedPath
    )
  }
}
