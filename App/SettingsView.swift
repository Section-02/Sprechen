import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false
    @State private var importProgress = false
    @State private var entries: [VocabularyEntry] = []
    @State private var showVocabularyReview = false
    @State private var progressRestore: AppState?
    @State private var confirmRestore = false
    @State private var exporting = false
    @State private var document = CSVDocument()
    @State private var filename = "Sprechen-vocabulary"
    @State private var resultMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                ForEach(Pool.allCases) { pool in
                    Section(pool.title) {
                        Stepper(value: Binding(get: { model.state.configuration(pool).limit }, set: { model.configure(pool, limit: $0) }), in: 1...500) {
                            Text("Active word pairs: \(model.state.configuration(pool).limit)")
                        }
                        Stepper(value: Binding(get: { model.state.configuration(pool).target }, set: { model.configure(pool, target: $0) }), in: 1...50) {
                            Text("Consecutive correct: \(model.state.configuration(pool).target)")
                        }
                        Stepper(value: Binding(get: { model.state.configuration(pool).firstReviewDays }, set: { model.configureReinforce(pool, firstDays: $0) }), in: 1...365) {
                            Text("First Reinforce: \(dayLabel(model.state.configuration(pool).firstReviewDays))")
                        }
                        Stepper(value: Binding(get: { model.state.configuration(pool).secondReviewDays }, set: { model.configureReinforce(pool, secondDays: $0) }), in: 1...365) {
                            Text("Second Reinforce: \(dayLabel(model.state.configuration(pool).secondReviewDays))")
                        }
                    }
                }
                Section("Vocabulary CSV") {
                    Button { importProgress = false; importing = true } label: { Label("Import vocabulary", systemImage: "square.and.arrow.down") }
                    Button { export(progress: false) } label: { Label("Export vocabulary", systemImage: "square.and.arrow.up") }
                }
                Section("Progress CSV") {
                    Button { export(progress: true) } label: { Label("Export progress and settings", systemImage: "square.and.arrow.up") }
                    Button { importProgress = true; importing = true } label: { Label("Restore progress and settings", systemImage: "arrow.counterclockwise") }
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let text = try model.readCSV(url)
                    if importProgress {
                        progressRestore = try ProgressCSV.restore(text, into: model.state); confirmRestore = true
                    } else {
                        entries = try VocabularyCSV.parse(text); showVocabularyReview = true
                    }
                } catch { model.error = error.localizedDescription }
            }
            .sheet(isPresented: $showVocabularyReview) { VocabularyImportView(entries: entries).environmentObject(model) }
            .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText, defaultFilename: filename) { result in
                switch result {
                case .success: resultMessage = "CSV exported."
                case .failure(let error): model.error = error.localizedDescription
                }
            }
            .alert("Replace this phone’s progress?", isPresented: $confirmRestore) {
                Button("Restore", role: .destructive) {
                    if let restored = progressRestore, model.update({ $0 = restored }) { resultMessage = "Progress and settings restored." }
                    progressRestore = nil
                }
                Button("Cancel", role: .cancel) { progressRestore = nil }
            } message: { Text("Your vocabulary stays. Current streaks, history, pause states for backed-up words, and settings will be replaced by this backup.") }
            .alert("Saved", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                Button("OK", role: .cancel) { resultMessage = nil }
            } message: { Text(resultMessage ?? "") }
        }
    }
    private func dayLabel(_ days: Int) -> String { "\(days) \(days == 1 ? "day" : "days")" }
    private func export(progress: Bool) {
        do {
            document = CSVDocument(text: try progress ? ProgressCSV.export(model.state) : VocabularyCSV.export(model.state))
            filename = progress ? "Sprechen-progress" : "Sprechen-vocabulary"
            exporting = true
        } catch { model.error = error.localizedDescription }
    }
}

struct VocabularyImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entries: [VocabularyEntry]
    @State private var staged = AppState()
    @State private var index = 0
    @State private var added = 0
    @State private var skipped = 0
    @State private var changed = 0
    @State private var german = ""
    @State private var english = ""
    @State private var conflicts: [WordPair] = []
    @State private var validation: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Import preview") {
                    Text("\(added) new · \(changed) changed · \(skipped) skipped")
                    Text("\(index) of \(entries.count) rows reviewed").foregroundStyle(.secondary)
                }
                if index < entries.count {
                    Section("Resolve this conflict") {
                        Text("This German word already has a different translation. Change the incoming text, replace a listed pair, or skip this row.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("German", text: $german).autocorrectionDisabled().textInputAutocapitalization(.never)
                        TextField("English", text: $english).autocorrectionDisabled().textInputAutocapitalization(.never)
                        if let validation { Text(validation).font(.footnote).foregroundStyle(.red) }
                        Button("Check changed pair") { resolveEdited() }
                        Button("Skip this row") { skipped += 1; advance() }
                    }
                    Section("Existing pairs") {
                        ForEach(conflicts) { word in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(word.german) — \(word.english)").font(.headline)
                                Button("Replace this pair with the text above") { replace(word) }
                                    .font(.subheadline)
                                Text("Keeps this pair’s learning history.").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                } else {
                    Section {
                        Label("Ready to import", systemImage: "checkmark.circle.fill").foregroundStyle(.teal)
                        Text("Nothing is saved until you tap Import.").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Review vocabulary").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { if model.update({ $0 = staged }) { dismiss() } }.disabled(index < entries.count)
                }
            }
            .onAppear { staged = model.state; process() }
        }
    }
    private func process() {
        conflicts = []; validation = nil
        while index < entries.count {
            let entry = entries[index]
            if VocabularyCSV.exactMatch(entry, in: staged) != nil { skipped += 1; index += 1; continue }
            let matches = VocabularyCSV.conflicts(entry, in: staged)
            if !matches.isEmpty {
                german = entry.german; english = entry.english; conflicts = matches; return
            }
            staged.words.append(WordPair(id: entry.id, german: entry.german, english: entry.english))
            added += 1; index += 1
        }
    }
    private func advance() { index += 1; process() }
    private func editedEntry() -> VocabularyEntry? {
        let de = german.trimmingCharacters(in: .whitespacesAndNewlines), en = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !de.isEmpty && !en.isEmpty else { validation = "Both fields are required."; return nil }
        return VocabularyEntry(id: entries[index].id, german: de, english: en)
    }
    private func resolveEdited() {
        guard let entry = editedEntry() else { return }
        if VocabularyCSV.exactMatch(entry, in: staged) != nil { skipped += 1; advance(); return }
        let matches = VocabularyCSV.conflicts(entry, in: staged)
        if !matches.isEmpty { conflicts = matches; validation = "There is still a conflict. Replace a listed pair or skip this row."; return }
        staged.words.append(WordPair(id: entry.id, german: entry.german, english: entry.english))
        added += 1; advance()
    }
    private func replace(_ word: WordPair) {
        guard let entry = editedEntry(), let target = staged.words.firstIndex(where: { $0.id == word.id }) else { return }
        do { try VocabularyCSV.validateUniqueGerman(entry.german, excluding: word.id, in: staged) }
        catch { validation = error.localizedDescription; return }
        staged.words[target].german = entry.german; staged.words[target].english = entry.english
        changed += 1; advance()
    }
}
