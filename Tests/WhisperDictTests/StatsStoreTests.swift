import XCTest
@testable import WhisperDict

final class StatsStoreTests: XCTestCase {

    private let suiteName = "WhisperDictTests.StatsStore"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        StatsStore.defaults = defaults
    }

    override func tearDown() {
        StatsStore.defaults.removePersistentDomain(forName: suiteName)
        StatsStore.defaults = .standard
        super.tearDown()
    }

    func testRecordAccumulatesTotals() {
        StatsStore.record(words: 10, bundleID: "com.a", seconds: 60, language: "en")
        StatsStore.record(words: 5, bundleID: "com.a", seconds: 30, language: "fr")

        XCTAssertEqual(StatsStore.totalWords, 15)
        XCTAssertEqual(StatsStore.totalDictations, 2)
        XCTAssertEqual(StatsStore.totalSpeakingSeconds, 90, accuracy: 1e-6)
    }

    func testWordsPerMinute() {
        StatsStore.record(words: 20, bundleID: nil, seconds: 60) // 20 words in 1 min
        XCTAssertEqual(StatsStore.wordsPerMinute(), 20)
    }

    func testWordsPerMinuteZeroWhenNoSpeakingTime() {
        XCTAssertEqual(StatsStore.wordsPerMinute(), 0)
    }

    func testMinutesSaved() {
        // 200 words ≈ 5 min typing at 40 wpm, minus 1 min spoken → ~4 saved.
        StatsStore.record(words: 200, bundleID: nil, seconds: 60)
        XCTAssertEqual(StatsStore.minutesSaved(), 4)
    }

    func testTopAppsRankedDescending() {
        StatsStore.record(words: 3, bundleID: "com.a", seconds: 1)
        StatsStore.record(words: 9, bundleID: "com.b", seconds: 1)
        StatsStore.record(words: 5, bundleID: "com.a", seconds: 1)

        // com.a = 3 + 5 = 8, com.b = 9 → ranked b, a.
        let top = StatsStore.topApps(limit: 2)
        XCTAssertEqual(top.map(\.bundleID), ["com.b", "com.a"])
        XCTAssertEqual(top.first?.words, 9)
        XCTAssertEqual(top.map(\.words), [9, 8])
    }

    func testTopLanguages() {
        StatsStore.record(words: 1, bundleID: nil, seconds: 1, language: "en")
        StatsStore.record(words: 1, bundleID: nil, seconds: 1, language: "en")
        StatsStore.record(words: 1, bundleID: nil, seconds: 1, language: "fr")

        let top = StatsStore.topLanguages(limit: 2)
        XCTAssertEqual(top.first?.language, "en")
        XCTAssertEqual(top.first?.count, 2)
    }

    func testRecordCommandNormalizesAndCounts() {
        StatsStore.record(words: 1, bundleID: nil, seconds: 1) // a dictation exists, unrelated
        StatsStore.recordCommand(instruction: "  Rends ÇA   formel ")
        StatsStore.recordCommand(instruction: "rends ça formel")

        XCTAssertEqual(StatsStore.totalCommands, 2)
        let top = StatsStore.topCommands(limit: 1)
        XCTAssertEqual(top.first?.command, "rends ça formel") // lowercased + whitespace-collapsed
        XCTAssertEqual(top.first?.count, 2)
    }

    func testEmptyCommandIsIgnored() {
        StatsStore.recordCommand(instruction: "   ")
        XCTAssertEqual(StatsStore.totalCommands, 0)
        XCTAssertTrue(StatsStore.topCommands(limit: 5).isEmpty)
    }
}
