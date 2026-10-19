import SwiftUI

struct WordsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var filter = "All"
    @State private var adding = false
    @State private var editing: WordPair?
    var filtered: [WordPair] {
        model.state.words.filter { word in
            (filter == "All" || (filter == "Paused" ? word.paused : !word.paused)) &&
            (search.isEmpty || word.german.localizedCaseInsensitiveContains(search) || word.english.localizedCaseInsensitiveContains(search))
        }.sorted { $0.german.localizedStandardCompare($1.german) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show words", selection: $filter) {
                        Text("All").tag("All"); Text("Studying").tag("Studying"); Text("Paused").tag("Paused")
                    }.pickerStyle(.segmented).listRowBackground(Color.clear)
                }
                if filtered.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(model.state.words.isEmpty ? "Your first word starts here" : "No matching words", systemImage: "text.badge.plus").font(.headline)
                            Text("Add a pair with +, or import a vocabulary CSV in Settings.").foregroundStyle(.secondary)
                        }.padding(.vertical, 18)
                    }
                }
                ForEach(filtered) { word in
                    Button { editing = word } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(word.german).font(.headline).foregroundStyle(.primary)
                                Spacer()
                                if word.paused { Image(systemName: "pause.circle.fill").foregroundStyle(.secondary).accessibilityLabel("Paused") }
                            }
                            Text(word.english).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                ForEach(Pool.allCases) { pool in
                                    if let p = model.state.progressFor(word.id, pool) {
                                        Text("\(pool.shortTitle): \(p.status == .mastered ? "✓" : String(p.streak))")
                                            .font(.caption2.weight(.medium)).foregroundStyle(pool.color)
                                    }
                                }
                            }
                        }.padding(.vertical, 5)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { model.pause(word) } label: { Label(word.paused ? "Reactivate" : "Pause", systemImage: word.paused ? "play" : "pause") }.tint(.orange)
                    }
                }
            }
            .searchable(text: $search, prompt: "German or English")
            .navigationTitle("Your words")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add word pair") } }
            .sheet(isPresented: $adding) { WordEditor(word: nil).environmentObject(model) }
            .sheet(item: $editing) { word in WordEditor(word: word).environmentObject(model) }
        }
    }
}

struct WordEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let word: WordPair?
    @State private var german = ""
    @State private var english = ""
    @State private var showDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Word pair") {
                    TextField("German, including article", text: $german).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("English translation", text: $english).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section { Text("Keep articles with nouns, such as der Schlüssel. You decide whether a missing article counts as incorrect.").font(.footnote).foregroundStyle(.secondary) }
                if let word, let current = model.state.words.first(where: { $0.id == word.id }) {
                    Section("Progress by exercise") {
                        ForEach(Pool.allCases) { pool in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(pool.title).font(.headline)
                                if let p = model.state.progressFor(word.id, pool) {
                                    Text("\(p.status.title) · \(p.streak) consecutive · \(p.correct)/\(p.attempts) correct overall")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let due = p.dueAt { Text("Next review: \(due.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                                } else { Text("Not studied yet").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Section {
                        Button { model.pause(current); dismiss() } label: { Label(current.paused ? "Reactivate word" : "Pause word", systemImage: current.paused ? "play.circle" : "pause.circle") }
                        Text(current.paused ? "Reactivation preserves history and starts fresh streaks in each previously used pool." : "Pausing hides this pair from all exercises and preserves its history.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Section { Button("Delete word and its history", role: .destructive) { showDelete = true } }
                }
            }
            .navigationTitle(word == nil ? "New word" : "Edit word").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if model.saveWord(id: word?.id, german: german, english: english) { dismiss() } }
                        .disabled(german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { german = word?.german ?? ""; english = word?.english ?? "" }
            .alert("Delete this word?", isPresented: $showDelete) {
                Button("Delete", role: .destructive) {
                    guard let word else { return }
                    if model.update({ state in
                        state.words.removeAll { $0.id == word.id }
                        state.progress = state.progress.filter { $0.value.wordID != word.id }
                        state.reviews.removeAll { $0.wordID == word.id }
                        for pool in Pool.allCases { Scheduler.replenish(pool, state: &state) }
                    }) { dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This removes its progress in every pool. Pausing keeps its history instead.") }
        }
    }
}
