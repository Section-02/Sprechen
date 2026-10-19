import XCTest
@testable import SprechenCore

final class SprechenCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func state(count: Int = 3, limit: Int = 20, target: Int = 5) -> AppState {
        var state = AppState()
        state.words = (0..<count).map { WordPair(german: "Wort \($0)", english: "word \($0)") }
        for pool in Pool.allCases {
            var config = PoolSettings(); config.limit = limit; config.target = target
            state.settings[pool.rawValue] = config
        }
        return state
    }
    func grade(_ id: UUID, pool: Pool = .englishToGerman, correct: Bool = true, state: inout AppState, at: Date? = nil) throws {
        try Scheduler.grade(wordID: id, pool: pool, direction: pool == .mixed ? .germanToEnglish : pool == .typeGerman ? .englishToGerman : pool, correct: correct, state: &state, now: at ?? now)
    }
    func testIndependentGraduationAndReplenishment() throws {
        var s = state(count: 4, limit: 1)
        Scheduler.replenish(.englishToGerman, state: &s)
        Scheduler.replenish(.germanToEnglish, state: &s)
        let word = try XCTUnwrap(Scheduler.next(.englishToGerman, state: s))
        for _ in 0..<5 { try grade(word.id, state: &s) }
        XCTAssertEqual(s.progressFor(word.id, .englishToGerman)?.status, .mastered)
        XCTAssertNotEqual(s.progressFor(word.id, .germanToEnglish)?.status, .mastered)
        XCTAssertEqual(s.activeCount(.englishToGerman), 1)
        XCTAssertNotEqual(Scheduler.next(.englishToGerman, state: s)?.id, word.id)
    }
    func testMixedUsesEitherPoolAndNeverUnseenWords() throws {
        var s = state(count: 40, limit: 50)
        Scheduler.replenish(.englishToGerman, state: &s)
        Scheduler.replenish(.mixed, state: &s)
        XCTAssertEqual(s.activeCount(.mixed), 0)
        for word in s.words.prefix(30) { try grade(word.id, state: &s) }
        Scheduler.replenish(.mixed, state: &s)
        XCTAssertEqual(s.activeCount(.mixed), 30)
        XCTAssertFalse(s.eligible(s.words[35], for: .mixed))
        let word = s.words[0]
        for _ in 0..<5 { try grade(word.id, pool: .mixed, state: &s) }
        XCTAssertEqual(s.progressFor(word.id, .mixed)?.status, .mastered)
        XCTAssertEqual(s.progressFor(word.id, .englishToGerman)?.streak, 1)
    }
    func testIncorrectAnswerResetsStreak() throws {
        var s = state(count: 1); Scheduler.replenish(.englishToGerman, state: &s)
        let id = s.words[0].id
        for _ in 0..<4 { try grade(id, state: &s) }
        try grade(id, correct: false, state: &s)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.streak, 0)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.status, .learning)
    }
    func testReinforceRequiresTwoDelayedReviewsAndFailureResets() throws {
        var s = state(count: 1); Scheduler.replenish(.englishToGerman, state: &s)
        let id = s.words[0].id
        for _ in 0..<2 { try grade(id, correct: false, state: &s) }
        for _ in 0..<5 { try grade(id, state: &s) }
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.status, .reinforce)
        XCTAssertNil(Scheduler.next(.englishToGerman, state: s, now: now))
        XCTAssertThrowsError(try grade(id, state: &s))
        let day1 = now.addingTimeInterval(86_400)
        try grade(id, state: &s, at: day1)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.dueAt, day1.addingTimeInterval(3 * 86_400))
        try grade(id, correct: false, state: &s, at: day1.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.streak, 0)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.status, .learning)
        for _ in 0..<5 { try grade(id, state: &s, at: day1) }
        let due = try XCTUnwrap(s.progressFor(id, .englishToGerman)?.dueAt)
        try grade(id, state: &s, at: due)
        try grade(id, state: &s, at: due.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.status, .mastered)
    }
    func testPauseReactivationPreservesHistory() throws {
        var s = state(count: 1); Scheduler.replenish(.englishToGerman, state: &s)
        let id = s.words[0].id
        try grade(id, state: &s)
        Scheduler.setPaused(true, wordID: id, state: &s)
        XCTAssertNil(Scheduler.next(.englishToGerman, state: s))
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.streak, 1)
        Scheduler.setPaused(false, wordID: id, state: &s)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.streak, 0)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.attempts, 1)
        XCTAssertEqual(s.reviews.count, 1)
    }
    func testLowerLimitParksWithoutLosingProgress() throws {
        var s = state(count: 30); Scheduler.replenish(.englishToGerman, state: &s)
        XCTAssertEqual(s.activeCount(.englishToGerman), 20)
        s.settings[Pool.englishToGerman.rawValue]?.limit = 5
        Scheduler.replenish(.englishToGerman, state: &s)
        XCTAssertEqual(s.activeCount(.englishToGerman), 5)
        XCTAssertEqual(s.progress.count, 20)
        s.settings[Pool.englishToGerman.rawValue]?.limit = 25
        Scheduler.replenish(.englishToGerman, state: &s)
        XCTAssertEqual(s.activeCount(.englishToGerman), 25)
    }
    func testCSVHandlesUnicodeQuotesCRLFAndMultiline() throws {
        let rows = [["german", "english"], ["der Schlüssel", "the key, a key"], ["sagen \"ja\"", "say\nyes"], ["grüßen", "greet"]]
        XCTAssertEqual(try CSV.parse("\u{FEFF}" + CSV.encode(rows)), rows)
        let entries = try VocabularyCSV.parse(CSV.encode(rows))
        XCTAssertEqual(entries.count, 3)
        XCTAssertThrowsError(try CSV.parse("german,english\n\"unclosed,x"))
        XCTAssertThrowsError(try VocabularyCSV.parse("german,english\nword,"))
        XCTAssertThrowsError(try VocabularyCSV.parse("german,english\nword,meaning,extra"))
    }
    func testProgressRoundTripAndCrossDeviceWordMapping() throws {
        var s = state(count: 3); Scheduler.replenish(.englishToGerman, state: &s)
        try grade(s.words[0].id, state: &s)
        Scheduler.replenish(.mixed, state: &s)
        let csv = try ProgressCSV.export(s)
        let restored = try ProgressCSV.restore(csv, into: s)
        XCTAssertEqual(restored.progress, s.progress)
        XCTAssertEqual(restored.settings, s.settings)
        XCTAssertEqual(restored.reviews, s.reviews)
        var other = AppState()
        other.words = s.words.map { WordPair(german: $0.german, english: $0.english) }
        let transferred = try ProgressCSV.restore(csv, into: other)
        XCTAssertEqual(transferred.progressFor(other.words[0].id, .englishToGerman)?.streak, 1)
        XCTAssertEqual(transferred.reviews[0].wordID, other.words[0].id)
        XCTAssertThrowsError(try ProgressCSV.restore(csv, into: AppState()))
    }
    func testDatabaseDurabilityAndBackupExclusion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("test.sqlite")
        var s = state(); Scheduler.replenish(.englishToGerman, state: &s)
        try grade(s.words[0].id, state: &s)
        do { let db = try Database(url: url); try db.save(s) }
        let reopened = try Database(url: url)
        XCTAssertEqual(try reopened.load(), s)
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        var invalid = s
        let orphan = Progress(wordID: UUID(), pool: .mixed); invalid.progress[orphan.key] = orphan
        XCTAssertThrowsError(try reopened.save(invalid))
        XCTAssertEqual(try reopened.load(), s, "A failed transaction must leave the previous saved state intact")
    }
    func testIncrementalEditsKeepHistoryAndDeletionRemovesIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try Database(url: folder.appendingPathComponent("test.sqlite"))
        var s = state(count: 2)
        Scheduler.replenish(.englishToGerman, state: &s)
        let id = s.words[0].id
        try grade(id, state: &s)
        try db.save(s)
        s.words[0].german = "der Schlüssel"
        try db.save(s)
        XCTAssertEqual(try db.load(), s)
        try grade(id, state: &s)
        try db.save(s)
        XCTAssertEqual(try db.load().reviews.count, 2)
        s.words.removeAll { $0.id == id }
        s.progress = s.progress.filter { $0.value.wordID != id }
        s.reviews.removeAll { $0.wordID == id }
        try db.save(s)
        XCTAssertEqual(try db.load(), s)
    }

    func testCustomReinforceDelaysRescheduleAndSurviveBackup() throws {
        var s = state(count: 1, target: 1)
        Scheduler.replenish(.englishToGerman, state: &s)
        let id = s.words[0].id
        Scheduler.setReinforceDelays(.englishToGerman, firstDays: 2, secondDays: 7, state: &s)
        try grade(id, correct: false, state: &s)
        try grade(id, correct: false, state: &s)
        try grade(id, state: &s)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.dueAt, now.addingTimeInterval(2 * 86_400))
        Scheduler.setReinforceDelays(.englishToGerman, firstDays: 4, state: &s)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.dueAt, now.addingTimeInterval(4 * 86_400))
        let firstReview = now.addingTimeInterval(4 * 86_400)
        try grade(id, state: &s, at: firstReview)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.dueAt, firstReview.addingTimeInterval(7 * 86_400))
        Scheduler.setReinforceDelays(.englishToGerman, secondDays: 2, state: &s)
        XCTAssertEqual(s.progressFor(id, .englishToGerman)?.dueAt, firstReview.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(s.configuration(.germanToEnglish).firstReviewDays, 1)
        XCTAssertEqual(s.configuration(.mixed).secondReviewDays, 3)
        let restored = try ProgressCSV.restore(ProgressCSV.export(s), into: s)
        XCTAssertEqual(restored.settings, s.settings)
        XCTAssertEqual(restored.progress, s.progress)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try Database(url: folder.appendingPathComponent("test.sqlite"))
        try database.save(s)
        XCTAssertEqual(try database.load().settings, s.settings)
    }

    func testLegacySettingsKeepDefaultReinforceDelays() throws {
        let data = Data(#"{"limit":20,"target":5,"turn":12}"#.utf8)
        let config = try JSONDecoder().decode(PoolSettings.self, from: data)
        XCTAssertEqual(config.firstReviewDays, 1)
        XCTAssertEqual(config.secondReviewDays, 3)
        XCTAssertEqual(config.turn, 12)
    }

    func testTypingPoolHasIndependentProgressAndBackup() throws {
        var s = state(count: 2, limit: 1)
        Scheduler.replenish(.typeGerman, state: &s)
        let word = try XCTUnwrap(Scheduler.next(.typeGerman, state: s))
        for _ in 0..<5 { try grade(word.id, pool: .typeGerman, state: &s) }
        XCTAssertEqual(s.progressFor(word.id, .typeGerman)?.status, .mastered)
        XCTAssertNil(s.progressFor(word.id, .englishToGerman))
        XCTAssertNil(s.progressFor(word.id, .germanToEnglish))
        XCTAssertFalse(s.eligible(word, for: .mixed), "Typing does not change the original Mixed eligibility rule")
        XCTAssertEqual(s.activeCount(.typeGerman), 1)
        XCTAssertNotEqual(Scheduler.next(.typeGerman, state: s)?.id, word.id)
        XCTAssertTrue(s.reviews.allSatisfy { $0.direction == .englishToGerman && $0.pool == .typeGerman })
        let restored = try ProgressCSV.restore(ProgressCSV.export(s), into: s)
        XCTAssertEqual(restored.progress, s.progress)
        XCTAssertEqual(restored.reviews, s.reviews)
        XCTAssertEqual(restored.settings, s.settings)
    }

    func testLegacyThreePoolBackupAndDatabaseGainTypingDefaults() throws {
        var s = state(count: 1)
        Scheduler.replenish(.englishToGerman, state: &s)
        try grade(s.words[0].id, state: &s)
        var rows = try CSV.parse(ProgressCSV.export(s))
        rows.removeAll { $0.count == ProgressCSV.header.count && $0[1] == "settings" && $0[5] == Pool.typeGerman.rawValue }
        for i in 1..<rows.count { rows[i][0] = "1" }
        let restored = try ProgressCSV.restore(CSV.encode(rows), into: s)
        XCTAssertEqual(restored.configuration(.typeGerman), PoolSettings())
        XCTAssertEqual(restored.progress, s.progress)
        XCTAssertEqual(restored.reviews, s.reviews)
        // A current backup missing its new settings is damaged, not an old backup.
        for i in 1..<rows.count { rows[i][0] = "2" }
        XCTAssertThrowsError(try ProgressCSV.restore(CSV.encode(rows), into: s))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let db = try Database(url: folder.appendingPathComponent("test.sqlite"))
        s.settings.removeValue(forKey: Pool.typeGerman.rawValue)
        try db.save(s)
        let loaded = try db.load()
        XCTAssertEqual(loaded.configuration(.typeGerman), PoolSettings())
        XCTAssertEqual(loaded.progress, s.progress)
    }

    func testTypingRequiresEnglishToGermanDirection() throws {
        var s = state(count: 1)
        Scheduler.replenish(.typeGerman, state: &s)
        XCTAssertThrowsError(try Scheduler.grade(wordID: s.words[0].id, pool: .typeGerman, direction: .germanToEnglish, correct: true, state: &s))
        XCTAssertTrue(s.reviews.isEmpty)
        XCTAssertFalse(Pool.mixed.accepts(direction: .typeGerman))
    }

    func testTwoColumnVocabularyRoundTripAndProgressRestore() throws {
        var source = state(count: 1)
        source.words[0].german = "der Tisch"
        source.words[0].english = "the table"
        Scheduler.replenish(.englishToGerman, state: &source)
        try grade(source.words[0].id, state: &source)
        let csv = VocabularyCSV.export(source)
        XCTAssertEqual(try CSV.parse(csv), [["german", "english"], ["der Tisch", "the table"]])
        let entries = try VocabularyCSV.parse(csv)
        XCTAssertNotEqual(entries[0].id, source.words[0].id)
        XCTAssertNotNil(VocabularyCSV.exactMatch(entries[0], in: source))
        var other = AppState()
        other.words = entries.map { WordPair(id: $0.id, german: $0.german, english: $0.english) }
        let restored = try ProgressCSV.restore(ProgressCSV.export(source), into: other)
        XCTAssertEqual(restored.progressFor(other.words[0].id, .englishToGerman)?.streak, 1)
        XCTAssertEqual(restored.reviews[0].wordID, other.words[0].id)
        let legacy = try VocabularyCSV.parse("id,german,english\nold-id,der Tisch,the table")
        XCTAssertEqual(legacy[0].german, "der Tisch")
        XCTAssertEqual(legacy[0].english, "the table")
    }

    func testMissedWordHasSpacingWhenAlternativesExist() throws {
        var s = state(count: 5); Scheduler.replenish(.englishToGerman, state: &s)
        let word = try XCTUnwrap(Scheduler.next(.englishToGerman, state: s))
        try grade(word.id, correct: false, state: &s)
        XCTAssertNotEqual(Scheduler.next(.englishToGerman, state: s, excluding: word.id)?.id, word.id)
    }
}
