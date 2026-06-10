import Foundation

/// Persists chat messages per user and calendar day.
enum DailyTipChatStore {

    static func save(
        messages: [DailyTipChatMessage],
        userId: String,
        dateKey: String,
        defaults: UserDefaults = .standard
    ) {
        let key = storageKey(userId: userId, dateKey: dateKey)
        guard let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(
        userId: String,
        dateKey: String,
        defaults: UserDefaults = .standard
    ) -> [DailyTipChatMessage] {
        let key = storageKey(userId: userId, dateKey: dateKey)
        guard let data = defaults.data(forKey: key),
              let messages = try? JSONDecoder().decode([DailyTipChatMessage].self, from: data) else {
            return []
        }
        return messages
    }

    private static func storageKey(userId: String, dateKey: String) -> String {
        let scope = userId.isEmpty ? "guest" : userId
        return "daily_tip_chat_\(scope)_\(dateKey)"
    }
}

extension DailyTip {
    /// Calendar day key extracted from tip id (`yyyy-MM-dd_category`).
    var dateKey: String {
        DailyTipHistoryStore.dateKey(fromTipId: id)
    }
}
