import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = AppState()
    @Published var error: String?
    @Published var notice: String?
    @Published var isReady = false
    private var database: Database?

    init() {
        do {
            var folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Sprechen", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            database = try Database(url: folder.appendingPathComponent("sprechen.sqlite"))
            state = try database!.load()
            isReady = true
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func update(_ change: (inout AppState) throws -> Void) -> Bool {
        guard let database, isReady else { error = "Local storage is unavailable. Reopen Sprechen to try again."; return false }
        do {
            var next = state
            try change(&next)
            try database.save(next)
            state = next
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func start(_ pool: Pool) -> Bool { update { Scheduler.replenish(pool, state: &$0) } }
    func grade(_ word: WordPair, pool: Pool, direction: Pool, correct: Bool) -> Bool {
        update { try Scheduler.grade(wordID: word.id, pool: pool, direction: direction, correct: correct, state: &$0) }
    }
    func pause(_ word: WordPair) { update { Scheduler.setPaused(!word.paused, wordID: word.id, state: &$0) } }
    func saveWord(id: UUID?, german: String, english: String) -> Bool {
        let de = german.trimmingCharacters(in: .whitespacesAndNewlines)
        let en = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !de.isEmpty && !en.isEmpty else { error = "Please enter both words."; return false }
        return update { state in
            try VocabularyCSV.validateUniqueGerman(de, excluding: id, in: state)
            if let id, let index = state.words.firstIndex(where: { $0.id == id }) {
                state.words[index].german = de; state.words[index].english = en
            } else { state.words.append(WordPair(german: de, english: en)) }
        }
    }
    func configure(_ pool: Pool, limit: Int? = nil, target: Int? = nil) {
        update { state in
            var settings = state.configuration(pool)
            if let limit { settings.limit = min(500, max(1, limit)) }
            if let target { settings.target = min(50, max(1, target)) }
            state.settings[pool.rawValue] = settings
            Scheduler.replenish(pool, state: &state)
        }
    }
    func configureReinforce(_ pool: Pool, firstDays: Int? = nil, secondDays: Int? = nil) {
        update { Scheduler.setReinforceDelays(pool, firstDays: firstDays, secondDays: secondDays, state: &$0) }
    }
    func readCSV(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count <= 20_000_000 else { throw SprechenError.message("Please choose a CSV smaller than 20 MB.") }
        guard let text = String(data: data, encoding: .utf8) else { throw SprechenError.message("Save this CSV using UTF-8 encoding so German characters are preserved.") }
        return text
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String = "") { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
