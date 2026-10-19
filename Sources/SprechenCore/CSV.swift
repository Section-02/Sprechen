import Foundation

public enum CSV {
    public static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map { value in
            if value.contains(where: { ",\"\n\r".contains($0) }) {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    public static func parse(_ text: String) throws -> [[String]] {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let chars = Array(text)
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false, index = 0
        while index < chars.count {
            let c = chars[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," {
                row.append(field); field = ""; closed = false
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []; field = ""; closed = false
                if c == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
            } else if c == "\"" && field.isEmpty && !closed { quoted = true }
            else {
                guard !closed && c != "\"" else { throw SprechenError.message("Invalid CSV quoting near row \(rows.count + 1).") }
                field.append(c)
            }
            index += 1
        }
        guard !quoted else { throw SprechenError.message("The CSV has an unfinished quoted field.") }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}

public struct VocabularyEntry: Identifiable {
    public var id: UUID
    public var german: String
    public var english: String
}

public enum VocabularyCSV {
    public static func export(_ state: AppState) -> String {
        CSV.encode([["german", "english"]] + state.words.map { [$0.german, $0.english] })
    }
    public static func parse(_ text: String) throws -> [VocabularyEntry] {
        let rows = try CSV.parse(text)
        guard let first = rows.first else { throw SprechenError.message("This CSV is empty.") }
        let header = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let german = header.firstIndex(of: "german"), let english = header.firstIndex(of: "english"), Set(header).count == header.count else {
            throw SprechenError.message("Use a CSV with german and english column headers.")
        }
        return try rows.dropFirst().enumerated().map { index, row in
            guard row.count == header.count else { throw SprechenError.message("Row \(index + 2) has the wrong number of columns.") }
            let de = row[german].trimmingCharacters(in: .whitespacesAndNewlines)
            let en = row[english].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !de.isEmpty && !en.isEmpty else { throw SprechenError.message("Row \(index + 2) needs both a German word and an English translation.") }
            // CSVs contain vocabulary, not device identifiers. Ignore legacy extra columns.
            return VocabularyEntry(id: UUID(), german: de, english: en)
        }
    }
    public static func sameText(_ lhs: String, _ rhs: String) -> Bool {
        func normalized(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "de_DE"))
        }
        return normalized(lhs) == normalized(rhs)
    }
    public static func validateUniqueGerman(_ german: String, excluding id: UUID? = nil, in state: AppState) throws {
        guard !state.words.contains(where: { $0.id != id && sameText($0.german, german) }) else {
            throw SprechenError.message("That German word already exists. Edit the existing word or skip this row.")
        }
    }
    public static func exactMatch(_ entry: VocabularyEntry, in state: AppState) -> WordPair? {
        state.words.first { sameText($0.german, entry.german) && sameText($0.english, entry.english) }
    }
    public static func conflicts(_ entry: VocabularyEntry, in state: AppState) -> [WordPair] {
        state.words.filter { sameText($0.german, entry.german) }
    }
}

/// A versioned CSV envelope keeps complete review history and settings lossless.
/// German/English columns permit progress to match vocabulary imported on another device.
public enum ProgressCSV {
    public static let header = ["version", "record_type", "word_id", "german", "english", "pool", "data"]
    public static func export(_ state: AppState) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        func row(_ type: String, _ wordID: UUID?, _ pool: String, _ data: String) -> [String] {
            let word = state.words.first { $0.id == wordID }
            return ["2", type, wordID?.uuidString ?? "", word?.german ?? "", word?.english ?? "", pool, data]
        }
        var rows = [header]
        for word in state.words { rows.append(row("word", word.id, "", try json(word))) }
        for pool in Pool.allCases { rows.append(row("settings", nil, pool.rawValue, try json(state.configuration(pool)))) }
        for p in state.progress.values.sorted(by: { $0.key < $1.key }) { rows.append(row("progress", p.wordID, p.pool.rawValue, try json(p))) }
        for review in state.reviews { rows.append(row("review", review.wordID, review.pool.rawValue, try json(review))) }
        return CSV.encode(rows)
    }

    /// Restore replaces progress/settings, never vocabulary. Validation completes before mutation.
    public static func restore(_ text: String, into original: AppState) throws -> AppState {
        let rows = try CSV.parse(text)
        guard rows.first == header else { throw SprechenError.message("Choose a Sprechen progress CSV. Import its vocabulary CSV first.") }
        let decoder = JSONDecoder()
        var result = original
        result.progress = [:]; result.reviews = []; result.settings = [:]
        var mapping: [UUID: UUID] = [:], seenWords = Set<UUID>(), seenReviews = Set<UUID>()
        let records = Array(rows.dropFirst())
        guard let version = records.first?.first, ["1", "2"].contains(version), records.allSatisfy({ $0.count == header.count && $0[0] == version }) else { throw SprechenError.message("Unsupported or damaged progress CSV.") }
        for row in records where row[1] == "word" {
            let word = try decoder.decode(WordPair.self, from: Data(row[6].utf8))
            guard row[2] == word.id.uuidString, row[3] == word.german, row[4] == word.english, seenWords.insert(word.id).inserted,
                  let index = result.words.firstIndex(where: { VocabularyCSV.sameText($0.german, word.german) && VocabularyCSV.sameText($0.english, word.english) }) else {
                throw SprechenError.message("A backed-up word is missing or differs from your vocabulary. Import the matching vocabulary CSV first.")
            }
            guard !mapping.values.contains(result.words[index].id) else { throw SprechenError.message("The progress CSV contains duplicate vocabulary.") }
            mapping[word.id] = result.words[index].id
            result.words[index].paused = word.paused
            result.words[index].createdAt = word.createdAt
        }
        for row in records {
            let data = Data(row[6].utf8)
            switch row[1] {
            case "word": break
            case "settings":
                guard let pool = Pool(rawValue: row[5]), result.settings[pool.rawValue] == nil else { throw SprechenError.message("Invalid or duplicate pool settings.") }
                let config = try decoder.decode(PoolSettings.self, from: data)
                guard (1...500).contains(config.limit), (1...50).contains(config.target), (1...365).contains(config.firstReviewDays), (1...365).contains(config.secondReviewDays), config.turn >= 0 && config.turn < 1_000_000_000 else { throw SprechenError.message("Invalid study settings in backup.") }
                result.settings[pool.rawValue] = config
            case "progress":
                var p = try decoder.decode(Progress.self, from: data)
                guard row[2] == p.wordID.uuidString, row[5] == p.pool.rawValue, let mapped = mapping[p.wordID],
                      p.streak >= 0, p.streak <= p.correct, p.misses >= 0, p.attempts >= 0, p.attempts < 1_000_000_000,
                      p.correct >= 0, p.correct <= p.attempts, p.misses == p.attempts - p.correct,
                      (0...2).contains(p.reinforceStep), p.nextTurn >= 0, p.nextTurn < 1_000_000_000,
                      p.status != .reinforce || p.dueAt != nil else { throw SprechenError.message("Invalid progress record.") }
                p.wordID = mapped
                guard result.progress[p.key] == nil else { throw SprechenError.message("Duplicate progress record.") }
                result.progress[p.key] = p
            case "review":
                var event = try decoder.decode(Review.self, from: data)
                guard row[2] == event.wordID.uuidString, row[5] == event.pool.rawValue, let mapped = mapping[event.wordID],
                      event.pool.accepts(direction: event.direction),
                      seenReviews.insert(event.id).inserted else { throw SprechenError.message("Invalid review history.") }
                event.wordID = mapped; result.reviews.append(event)
            default: throw SprechenError.message("Unknown record type in progress CSV.")
            }
        }
        // Version 1 predates Type German. Restore those backups with an empty new pool.
        if version == "1", result.settings[Pool.typeGerman.rawValue] == nil,
           !result.progress.values.contains(where: { $0.pool == .typeGerman }),
           !result.reviews.contains(where: { $0.pool == .typeGerman }) {
            result.settings[Pool.typeGerman.rawValue] = PoolSettings()
        }
        guard result.settings.count == Pool.allCases.count else { throw SprechenError.message("The backup is missing study settings.") }
        for pool in Pool.allCases {
            guard result.activeCount(pool) <= result.configuration(pool).limit else { throw SprechenError.message("The backup exceeds its active pool limit.") }
        }
        for p in result.progress.values where p.active {
            guard let word = result.words.first(where: { $0.id == p.wordID }), result.eligible(word, for: p.pool), p.status != .mastered else { throw SprechenError.message("The backup contains an ineligible active word.") }
        }
        return result
    }
}
