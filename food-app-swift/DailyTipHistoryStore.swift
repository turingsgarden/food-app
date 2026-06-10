import Foundation

/// One saved daily tip snapshot, keyed by calendar day.
struct DailyTipHistoryEntry: Codable, Identifiable {
    /// `yyyy-MM-dd` — same key used for tip ids and dismiss persistence.
    let dateKey: String
    let savedAt: Date
    let displayDate: String
    let tip: DailyTip

    var id: String { dateKey }
}

/// Local persistence for past daily tips (date-only list in UI).
enum DailyTipHistoryStore {

    private static let maxEntries = 120

    static func save(tip: DailyTip, userId: String, defaults: UserDefaults = .standard) {
        let key = storageKey(for: userId)
        let dateKey = DailyTipHistoryStore.dateKey(fromTipId: tip.id)
        let entry = DailyTipHistoryEntry(
            dateKey: dateKey,
            savedAt: Date(),
            displayDate: displayDate(for: dateKey),
            tip: tip
        )

        var entries = load(userId: userId, defaults: defaults)
        if let index = entries.firstIndex(where: { $0.dateKey == dateKey }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }

        entries.sort { $0.dateKey > $1.dateKey }
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        persist(entries, key: key, defaults: defaults)
    }

    static func load(userId: String, defaults: UserDefaults = .standard) -> [DailyTipHistoryEntry] {
        let key = storageKey(for: userId)
        guard let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([DailyTipHistoryEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.dateKey > $1.dateKey }
    }

    // MARK: - Private

    private static func storageKey(for userId: String) -> String {
        let scope = userId.isEmpty ? "guest" : userId
        return "daily_tip_history_\(scope)"
    }

    private static func persist(_ entries: [DailyTipHistoryEntry], key: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    /// Tip ids look like `yyyy-MM-dd_category`.
    static func dateKey(fromTipId tipId: String) -> String {
        if let dash = tipId.firstIndex(of: "_") {
            return String(tipId[..<dash])
        }
        return tipId
    }

    private static func displayDate(for dateKey: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        let date = parser.date(from: dateKey) ?? Date()

        let display = DateFormatter()
        display.calendar = parser.calendar
        display.locale = Locale.current
        display.timeZone = .current
        display.dateFormat = "MMM d, yyyy"
        return display.string(from: date)
    }
}
