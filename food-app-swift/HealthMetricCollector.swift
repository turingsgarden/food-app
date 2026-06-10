import Foundation

/// Normalized abnormal metric payload for AI context and UI-driven tip generation.
struct AbnormalMetricContext: Codable, Identifiable, Equatable {
    let id: String
    let metric: String
    let currentValue: String
    let status: String
    let advice: String?
}

/// Collects backend-labeled abnormal metrics without re-implementing medical thresholds in the UI layer.
enum HealthMetricCollector {
    static func collect(from report: HealthReport?) -> [AbnormalMetricContext] {
        report?.attentionItems
            .filter { !$0.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().isEmpty }
            .filter { $0.status.lowercased() != "normal" }
            .map { item in
                AbnormalMetricContext(
                    id: item.metric,
                    metric: item.metric,
                    currentValue: item.currentValue,
                    status: item.status,
                    advice: item.advice
                )
            } ?? []
    }
}
