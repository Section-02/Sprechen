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
        try Scheduler.grade(wordID: id, pool: pool, direction: pool == .mixed ? .germanToEnglish : pool, correct: correct, state: &state, now: at ?? now)
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

    func testMissedWordHasSpacingWhenAlternativesExist() throws {
        var s = state(count: 5); Scheduler.replenish(.englishToGerman, state: &s)
        let word = try XCTUnwrap(Scheduler.next(.englishToGerman, state: s))
        try grade(word.id, correct: false, state: &s)
        XCTAssertNotEqual(Scheduler.next(.englishToGerman, state: s, excluding: word.id)?.id, word.id)
    }
}
