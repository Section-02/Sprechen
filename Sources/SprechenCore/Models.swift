import Foundation

public enum Pool: String, Codable, CaseIterable, Identifiable {
    case englishToGerman, germanToEnglish, mixed, typeGerman
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .englishToGerman: return "English → German"
        case .germanToEnglish: return "German → English"
        case .mixed: return "Mixed"
        case .typeGerman: return "Type German"
        }
    }
    public var subtitle: String {
        switch self {
        case .englishToGerman: return "Find your German words"
        case .germanToEnglish: return "Make the meaning click"
        case .mixed: return "A little of both"
        case .typeGerman: return "English prompt, German spelling"
        }
    }
    public var shortTitle: String {
        switch self {
        case .englishToGerman: return "EN→DE"
        case .germanToEnglish: return "DE→EN"
        case .mixed: return "Mix"
        case .typeGerman: return "Type"
        }
    }
    public func accepts(direction: Pool) -> Bool {
        switch self {
        case .englishToGerman, .typeGerman: return direction == .englishToGerman
        case .germanToEnglish: return direction == .germanToEnglish
        case .mixed: return direction == .englishToGerman || direction == .germanToEnglish
        }
    }

}

public struct WordPair: Codable, Identifiable, Equatable {
    public var id: UUID
    public var german: String
    public var english: String
    public var createdAt: Date
    public var paused: Bool
    public init(id: UUID = UUID(), german: String, english: String, createdAt: Date = Date(), paused: Bool = false) {
        self.id = id; self.german = german; self.english = english
        self.createdAt = createdAt; self.paused = paused
    }
}

public enum LearningStatus: String, Codable {
    case learning, reinforce, mastered
    public var title: String { rawValue.capitalized }
}

public struct Progress: Codable, Equatable {
    public var wordID: UUID
    public var pool: Pool
    public var status: LearningStatus = .learning
    public var streak = 0
    public var misses = 0
    public var attempts = 0
    public var correct = 0
    public var nextTurn = 0
    public var reinforceStep = 0
    public var dueAt: Date?
    public var lastSeen: Date?
    public var active = true
    public var key: String { "\(wordID.uuidString):\(pool.rawValue)" }
    public init(wordID: UUID, pool: Pool) { self.wordID = wordID; self.pool = pool }
}

public struct PoolSettings: Codable, Equatable {
    public var limit = 20
    public var target = 5
    public var turn = 0
    public var firstReviewDays = 1
    public var secondReviewDays = 3
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case limit, target, turn, firstReviewDays, secondReviewDays
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        limit = try values.decode(Int.self, forKey: .limit)
        target = try values.decode(Int.self, forKey: .target)
        turn = try values.decode(Int.self, forKey: .turn)
        // Existing databases and older progress CSVs keep the original intervals.
        firstReviewDays = try values.decodeIfPresent(Int.self, forKey: .firstReviewDays) ?? 1
        secondReviewDays = try values.decodeIfPresent(Int.self, forKey: .secondReviewDays) ?? 3
    }
}

public struct Review: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var wordID: UUID
    public var pool: Pool
    public var direction: Pool
    public var correct: Bool
    public var date: Date
    public init(wordID: UUID, pool: Pool, direction: Pool, correct: Bool, date: Date) {
        self.wordID = wordID; self.pool = pool; self.direction = direction
        self.correct = correct; self.date = date
    }
}

public struct AppState: Codable, Equatable {
    public var words: [WordPair] = []
    public var progress: [String: Progress] = [:]
    public var settings: [String: PoolSettings] = Dictionary(uniqueKeysWithValues: Pool.allCases.map { ($0.rawValue, PoolSettings()) })
    public var reviews: [Review] = []
    public init() {}
    public func configuration(_ pool: Pool) -> PoolSettings { settings[pool.rawValue] ?? PoolSettings() }
    public func progressFor(_ word: UUID, _ pool: Pool) -> Progress? { progress["\(word.uuidString):\(pool.rawValue)"] }
    public func eligible(_ word: WordPair, for pool: Pool) -> Bool {
        guard !word.paused else { return false }
        return pool != .mixed || [Pool.englishToGerman, .germanToEnglish].contains {
            (progressFor(word.id, $0)?.attempts ?? 0) > 0
        }
    }
    public func activeCount(_ pool: Pool) -> Int {
        words.filter { eligible($0, for: pool) && progressFor($0.id, pool)?.active == true && progressFor($0.id, pool)?.status != .mastered }.count
    }
}

public enum SprechenError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
