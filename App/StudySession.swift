import SwiftUI

struct StudySession: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = SpeechController()
    let pool: Pool
    @State private var word: WordPair?
    @State private var direction = Pool.englishToGerman
    @State private var typedAnswer = ""
    @FocusState private var typingFocused: Bool
    @State private var revealed = false
    @State private var answered = 0
    @State private var correct = 0
    @State private var feedback: String?
    @State private var finished = false
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if finished {
                        Image(systemName: "hands.clap.fill").font(.system(size: 58)).foregroundStyle(.teal).padding(.top, 40)
                        Text("A little progress, saved.").font(.title.bold()).multilineTextAlignment(.center)
                        Text("\(answered) answers · \(correct) correct").foregroundStyle(.secondary)
                        Button("Another session") { speech.stop(); dismiss() }
                            .buttonStyle(PrimaryButtonStyle(color: pool.color))
                        Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle(color: .teal))
                    } else if let word {
                        HStack {
                            Label("\(answered) answered", systemImage: "checkmark.circle")
                            Spacer()
                            Text("\(model.state.activeCount(pool))/\(model.state.configuration(pool).limit) pairs")
                        }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        if let feedback {
                            Text(feedback).font(.subheadline.weight(.semibold)).foregroundStyle(pool.color)
                                .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.updatesFrequently)
                        }
                        VStack(spacing: 24) {
                            HStack {
                                Text(direction == .englishToGerman ? "ENGLISH → GERMAN" : "GERMAN → ENGLISH")
                                    .font(.caption.weight(.bold)).tracking(1)
                                Spacer()
                                if model.state.progressFor(word.id, pool)?.status == .reinforce {
                                    Label("Reinforce", systemImage: "arrow.clockwise").font(.caption.bold())
                                }
                            }.foregroundStyle(pool.color)
                            Text(direction == .englishToGerman ? word.english : word.german)
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 100)
                                .accessibilityLabel("Translate: \(direction == .englishToGerman ? word.english : word.german)")
                            if revealed {
                                Divider()
                                Text(direction == .englishToGerman ? word.german : word.english)
                                    .font(.title2.weight(.semibold)).foregroundStyle(pool.color).multilineTextAlignment(.center)
                                    .accessibilityLabel("Answer: \(direction == .englishToGerman ? word.german : word.english)")
                            } else {
                                Text(pool == .typeGerman ? "Type the German translation." : "Say it aloud, or think it through.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            let streak = model.state.progressFor(word.id, pool)?.streak ?? 0
                            Text("\(streak) consecutive correct · target \(model.state.configuration(pool).target)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(24).frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(pool.color.opacity(0.20)))

                        if pool == .typeGerman {
                            if revealed {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("YOUR ANSWER").font(.caption.bold()).foregroundStyle(.secondary)
                                    Text(typedAnswer.isEmpty ? "—" : typedAnswer).font(.title3)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                    .background(pool.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            } else {
                                TextField("German answer", text: $typedAnswer)
                                    .font(.title3).textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($typingFocused).submitLabel(.done)
                                    .accessibilityLabel("Your German translation")
                                    .onSubmit { if !typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { revealAnswer() } }
                            }
                        }
                        if !speech.transcript.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("YOU SAID").font(.caption.bold()).foregroundStyle(.secondary)
                                Text(speech.transcript).font(.title3)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                .background(pool.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                        if let message = speech.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        if !revealed {
                            if pool == .typeGerman {
                                Button("Check answer") { revealAnswer() }
                                    .buttonStyle(PrimaryButtonStyle(color: pool.color))
                                    .disabled(typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("I don’t know") { revealAnswer() }.font(.subheadline)
                            } else {
                                Button {
                                    if speech.isRecording { speech.finish() }
                                    else { Task { await speech.start(direction: direction) } }
                                } label: {
                                    Label(speech.isStarting ? "Preparing microphone…" : speech.isRecording ? "Stop listening" : speech.transcript.isEmpty ? "Speak your answer" : "Try speaking again", systemImage: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                }.disabled(speech.isStarting).buttonStyle(.bordered).tint(pool.color)
                                Button("Reveal answer") { revealAnswer() }
                                    .buttonStyle(PrimaryButtonStyle(color: pool.color))
                            }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { gradeButtons }
                                VStack(spacing: 12) { gradeButtons }
                            }
                        }
                        Button { speech.stop(); model.pause(word); loadNext(excluding: word.id) } label: {
                            Label("Pause this word", systemImage: "pause.circle")
                        }.font(.footnote).foregroundStyle(.secondary)
                        Text("Only your green or red choice changes your progress.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else {
                        emptyState
                    }
                }.padding(22)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(pool.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !finished { Button("Finish") { typingFocused = false; speech.stop(); finished = true } }
                }
            }
            .onAppear { loadNext() }
            .onDisappear { speech.stop() }
            .onChange(of: scenePhase) { phase in
                if phase != .active { speech.stop() }
                else if word == nil && !finished { loadNext() }
            }
            .onReceive(refresh) { _ in if word == nil && !finished { loadNext() } }
        }
    }
    @ViewBuilder private var gradeButtons: some View {
        Button { submit(false) } label: { Label("Missed it", systemImage: "xmark") }
            .buttonStyle(PrimaryButtonStyle(color: .red))
        Button { submit(true) } label: { Label("Got it", systemImage: "checkmark") }
            .buttonStyle(PrimaryButtonStyle(color: .green))
    }
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 54)).foregroundStyle(pool.color).padding(.top, 40)
            Text("A good place to pause.").font(.title.bold()).multilineTextAlignment(.center)
            let nextDue = model.state.progress.values.filter { $0.pool == pool && $0.active && $0.status == .reinforce }.compactMap(\.dueAt).min()
            if let nextDue {
                Text("Your active pairs are resting. Next Reinforce review: \(nextDue.formatted(date: .abbreviated, time: .shortened)).")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else if pool == .mixed && !model.state.words.contains(where: { model.state.eligible($0, for: .mixed) }) {
                Text("Study a pair in either directional exercise first. It will then be available here.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text("No cards are ready in this pool. Add words, reactivate paused words, or enjoy your progress.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Another session") { speech.stop(); dismiss() }
                .buttonStyle(PrimaryButtonStyle(color: pool.color))
            Button("Finish session") { typingFocused = false; speech.stop(); finished = true }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }
    private func loadNext(excluding: UUID? = nil) {
        speech.clear(); revealed = false; typedAnswer = ""; typingFocused = false
        word = Scheduler.next(pool, state: model.state, excluding: excluding)
        direction = pool == .mixed ? (Bool.random() ? .englishToGerman : .germanToEnglish) : pool == .typeGerman ? .englishToGerman : pool
    }
    private func revealAnswer() {
        typingFocused = false
        speech.stop()
        revealed = true
    }
    private func submit(_ result: Bool) {
        guard revealed, let word else { return }
        speech.stop()
        if model.grade(word, pool: pool, direction: direction, correct: result) {
            answered += 1; if result { correct += 1 }
            let status = model.state.progressFor(word.id, pool)?.status
            feedback = status == .mastered ? "Graduated! A new pair can take its place." : status == .reinforce ? "Saved for a Reinforce review." : result ? "Nice recall. Keep going!" : "Back in the pile. You’ll see it again."
            loadNext(excluding: word.id)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17).padding(.horizontal, 12)
            .foregroundStyle(.white).background(color.gradient, in: RoundedRectangle(cornerRadius: 17))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
