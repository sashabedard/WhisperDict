import Foundation

/// Local, private usage stats — never leave the Mac. Single writer for all
/// counters; UserSettings keeps read-through getters for totalWords/
/// totalDictations for back-compat. Reuses the existing "totalWords" and
/// "totalDictations" UserDefaults keys, so prior data is preserved.
enum StatsStore {
    private static let d = UserDefaults.standard

    static func record(words: Int, bundleID: String?, seconds: Double, language: String = "") {
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
        let keep = Set(lastNDayKeys(30))
        d.set(byDay.filter { keep.contains($0.key) }, forKey: "wordsByDay")

        if !language.isEmpty {
            var byLang = languageByCount
            byLang[language, default: 0] += 1
            d.set(byLang, forKey: "languageByCount")
        }
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

    static func last30Days() -> [(day: String, words: Int)] {
        let byDay = wordsByDay
        return lastNDayKeys(30).map { (day: $0, words: byDay[$0] ?? 0) }
    }

    static func recordCommand(instruction: String) {
        let norm = normalizeCommand(instruction)
        guard !norm.isEmpty else { return }
        d.set(totalCommands + 1, forKey: "totalCommands")
        var byCmd = commandByCount
        byCmd[norm, default: 0] += 1
        d.set(byCmd, forKey: "commandByCount")
    }

    static var totalCommands: Int { d.integer(forKey: "totalCommands") }

    static func topLanguages(limit: Int) -> [(language: String, count: Int)] {
        languageByCount.sorted { $0.value > $1.value }.prefix(limit).map { (language: $0.key, count: $0.value) }
    }

    static func topCommands(limit: Int) -> [(command: String, count: Int)] {
        commandByCount.sorted { $0.value > $1.value }.prefix(limit).map { (command: $0.key, count: $0.value) }
    }

    /// Estimated minutes saved vs typing at 40 wpm, minus time spent speaking.
    static func minutesSaved() -> Int {
        let typingMinutes = Double(totalWords) / 40.0
        let spokenMinutes = totalSpeakingSeconds / 60.0
        return max(0, Int((typingMinutes - spokenMinutes).rounded()))
    }

    // MARK: - Private

    private static var wordsByApp: [String: Int] { d.dictionary(forKey: "wordsByApp") as? [String: Int] ?? [:] }
    private static var wordsByDay: [String: Int] { d.dictionary(forKey: "wordsByDay") as? [String: Int] ?? [:] }
    private static var languageByCount: [String: Int] { d.dictionary(forKey: "languageByCount") as? [String: Int] ?? [:] }
    private static var commandByCount: [String: Int] { d.dictionary(forKey: "commandByCount") as? [String: Int] ?? [:] }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func todayKey() -> String { dayFormatter.string(from: Date()) }

    /// Last N day-keys, oldest first (index N-1 is today).
    private static func lastNDayKeys(_ n: Int) -> [String] {
        let cal = Calendar.current
        let today = Date()
        return (0..<n).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { dayFormatter.string(from: $0) }
        }
    }

    private static func normalizeCommand(_ s: String) -> String {
        let lowered = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(collapsed.prefix(40))
    }
}
