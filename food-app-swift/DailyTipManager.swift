import Foundation
import Combine

/// Coordinates today's tip generation and UI state persistence.
///
/// Responsibilities:
/// - Load HealthProfile + locally cached nutrition goals.
/// - Collect backend-labeled abnormal metrics from HealthReport.
/// - Build a DailyTip through `DailyTipEngine`.
/// - Persist "dismissed today" state for the Daily Banner.
/// - Persist whether the floating-tip first-use hint has been seen.
@MainActor
final class DailyTipManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var tip: DailyTip
    @Published private(set) var isMinimized: Bool
    @Published private(set) var hasSeenFloatingHint: Bool
    @Published private(set) var historyEntries: [DailyTipHistoryEntry] = []

    // MARK: - Dependencies

    private let session: SessionManager
    private let healthAPI: HealthAPIManager
    private let defaults: UserDefaults

    // MARK: - Persistence Keys

    private enum Keys {
        static let dismissedDate = "daily_banner_dismissed_date"
        static let floatingHintSeen = "daily_tip_floating_hint_seen"
    }

    // MARK: - Init

    init(
        session: SessionManager = .shared,
        healthAPI: HealthAPIManager = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.session = session
        self.healthAPI = healthAPI
        self.defaults = defaults

        // Start with a safe fallback so UI can render immediately.
        self.tip = DailyTipEngine.recommend(for: DailyTipContext(profile: nil, goals: [], date: Date()))
        self.hasSeenFloatingHint = defaults.bool(forKey: Keys.floatingHintSeen)
        self.isMinimized = false

        // Initialize today's minimized state from local persistence.
        self.isMinimized = isDismissedToday()
        reloadHistory()
    }

    // MARK: - Public API

    /// Refreshes today's tip: tries AI backend first, falls back to local rule engine.
    func refresh() {
        isMinimized = isDismissedToday()

        let goals = loadHealthGoalsFromCachedPlan()
        let userId = currentUserId()

        guard !userId.isEmpty else {
            applyTip(DailyTipEngine.recommend(for: DailyTipContext(profile: nil, goals: goals, abnormalMetrics: [], date: Date())))
            return
        }

        healthAPI.fetchHealthProfile(userId: userId) { [weak self] profile in
            guard let self else { return }
            self.healthAPI.fetchHealthReport { [weak self] report in
                guard let self else { return }
                let abnormalMetrics = HealthMetricCollector.collect(from: report)
                let context = DailyTipContext(
                    profile: profile,
                    goals: goals,
                    abnormalMetrics: abnormalMetrics,
                    date: Date(),
                    healthSummary: report?.healthSummary,
                    reportLifestyleTip: report?.lifestyleTip
                )
                let goalStrings = goals.map(\.rawValue)

                self.healthAPI.generateDailyTip(goals: goalStrings, force: false, date: self.todayKey()) { [weak self] aiTip, _ in
                    guard let self else { return }
                    if let aiTip {
                        self.applyTip(aiTip)
                    } else {
                        self.applyTip(DailyTipEngine.recommend(for: context))
                    }
                }
            }
        }
    }

    func reloadHistory() {
        historyEntries = DailyTipHistoryStore.load(userId: currentUserId(), defaults: defaults)
    }

    /// Marks banner as dismissed for the current calendar day.
    ///
    /// Dismiss behavior is day-scoped: hidden for the rest of today and reset on the next day.
    func dismissForToday() {
        defaults.set(todayKey(), forKey: Keys.dismissedDate)
        isMinimized = true
    }

    /// Restores banner visibility for the current app session.
    ///
    /// Note: this does not clear today's dismissed date. If app is restarted on
    /// the same day, the banner may start minimized again per persisted rule.
    func restore() {
        isMinimized = false
    }

    /// Records that the floating-tip onboarding bubble has been seen.
    func markFloatingHintSeen() {
        hasSeenFloatingHint = true
        defaults.set(true, forKey: Keys.floatingHintSeen)
    }

    // MARK: - Private Helpers

    private func applyTip(_ newTip: DailyTip) {
        tip = newTip
        DailyTipHistoryStore.save(tip: newTip, userId: currentUserId(), defaults: defaults)
        reloadHistory()
    }

    private func currentUserId() -> String {
        if !session.userID.isEmpty {
            return session.userID
        }
        return defaults.string(forKey: "user_id") ?? ""
    }

    private func isDismissedToday() -> Bool {
        guard let saved = defaults.string(forKey: Keys.dismissedDate) else { return false }
        return saved == todayKey()
    }

    private func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.startOfDay(for: Date()))
    }

    /// Reads goals from the same local cache pattern used in ContentView.
    private func loadHealthGoalsFromCachedPlan() -> [HealthGoal] {
        let userId = currentUserId()
        guard !userId.isEmpty,
              let data = defaults.data(forKey: "nutrition_plan_\(userId)"),
              let plan = try? JSONDecoder().decode(NutritionPlan.self, from: data) else {
            return []
        }

        return plan.goals.compactMap { HealthGoal(rawValue: $0) }
    }
}
