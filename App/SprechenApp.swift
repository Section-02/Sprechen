import SwiftUI

@main
struct SprechenApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(.teal)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if model.isReady {
                TabView {
                    StudyHome().tabItem { Label("Study", systemImage: "rectangle.stack.fill") }
                    WordsView().tabItem { Label("Words", systemImage: "text.book.closed.fill") }
                    SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                    Text("Your words are staying put").font(.title2.bold())
                    Text("Sprechen couldn’t open its local storage. Close and reopen the app to try again.").multilineTextAlignment(.center)
                }.padding()
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

extension Pool {
    var color: Color {
        switch self { case .englishToGerman: return .teal; case .germanToEnglish: return .indigo; case .mixed: return .orange }
    }
    var symbol: String {
        switch self { case .englishToGerman: return "bubble.left.and.text.bubble.right.fill"; case .germanToEnglish: return "text.bubble.fill"; case .mixed: return "shuffle" }
    }
}

struct StudyHome: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: Pool?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A few words.\nA little closer.").font(.largeTitle.bold())
                            Text("Choose today’s exercise.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.teal).accessibilityHidden(true)
                    }.padding(.top, 12)
                    ForEach(Pool.allCases) { pool in
                        Button {
                            if model.start(pool) { selection = pool }
                        } label: { PoolTile(pool: pool) }.buttonStyle(.plain)
                    }
                    if model.state.words.isEmpty {
                        Text("Start in Words: add a pair yourself or import a vocabulary CSV.")
                            .font(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.teal.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                    }
                }.padding(22)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $selection) { pool in StudySession(pool: pool).environmentObject(model) }
        }
    }
}

struct PoolTile: View {
    @EnvironmentObject private var model: AppModel
    let pool: Pool
    var body: some View {
        let eligible = model.state.words.filter { model.state.eligible($0, for: pool) }
        let mastered = eligible.filter { model.state.progressFor($0.id, pool)?.status == .mastered }.count
        HStack(spacing: 16) {
            Image(systemName: pool.symbol).font(.title2).foregroundStyle(pool.color)
                .frame(width: 54, height: 64).background(pool.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 7) {
                Text(pool.title).font(.headline).foregroundStyle(.primary)
                Text(pool.subtitle).font(.subheadline).foregroundStyle(.secondary)
                Text("\(eligible.count) eligible · \(mastered) graduated")
                    .font(.caption).foregroundStyle(pool.color)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right").foregroundStyle(pool.color).accessibilityHidden(true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(pool.color.opacity(0.12)))
    }
}
