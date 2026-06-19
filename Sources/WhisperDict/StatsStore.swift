import Foundation

/// Local, private usage stats — never leave the Mac. Single writer for all
/// counters; UserSettings keeps read-through getters for totalWords/
/// totalDictations for back-compat. Reuses the existing "totalWords" and
/// "totalDictations" UserDefaults keys, so prior data is preserved.
enum StatsStore {
    private static let d = UserDefaults.standard

    static func record(words: Int, bundleID: String?, seconds: Double) {
        d.set(totalWords + words, forKey: "totalWords")
        d.set(totalDictations + 1, forKey: "totalDictations")
        d.set(totalSpeakingSeconds + seconds, forKey: "totalSpeakingSeconds")

        if let id = bundleID, !id.isEmpty {
            var byApp = wordsByApp
            byApp[id, default: 0] += words
            d.set(byApp, forKey: "wordsByApp")
        }

        var byDay = wordsByDay
        byDay[todayKey(), default: 0] += words
        let keep = Set(last7DayKeys())
        d.set(byDay.filter { keep.contains($0.key) }, forKey: "wordsByDay")
    }

    static var totalWords: Int { d.integer(forKey: "totalWords") }
    static var totalDictations: Int { d.integer(forKey: "totalDictations") }
    static var totalSpeakingSeconds: Double { d.double(forKey: "totalSpeakingSeconds") }

    static func wordsPerMinute() -> Int {
        let minutes = totalSpeakingSeconds / 60
        guard minutes > 0 else { return 0 }
        return Int((Double(totalWords) / minutes).rounded())
    }

    static func topApps(limit: Int) -> [(bundleID: String, words: Int)] {
        wordsByApp.sorted { $0.value > $1.value }.prefix(limit).map { (bundleID: $0.key, words: $0.value) }
    }

    static func last7Days() -> [(day: String, words: Int)] {
        let byDay = wordsByDay
        return last7DayKeys().map { (day: $0, words: byDay[$0] ?? 0) }
    }

    // MARK: - Private

    private static var wordsByApp: [String: Int] { d.dictionary(forKey: "wordsByApp") as? [String: Int] ?? [:] }
    private static var wordsByDay: [String: Int] { d.dictionary(forKey: "wordsByDay") as? [String: Int] ?? [:] }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func todayKey() -> String { dayFormatter.string(from: Date()) }

    /// Last 7 day-keys, oldest first (index 6 is today).
    private static func last7DayKeys() -> [String] {
        let cal = Calendar.current
        let today = Date()
        return (0..<7).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { dayFormatter.string(from: $0) }
        }
    }
}
