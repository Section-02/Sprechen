import Foundation

public enum Scheduler {
    /// Active membership persists. Lowering a limit parks surplus pairs without erasing progress.
    public static func replenish(_ pool: Pool, state: inout AppState) {
        let eligible = state.words.filter { state.eligible($0, for: pool) }
        let eligibleIDs = Set(eligible.map(\.id))
        for key in Array(state.progress.keys) where state.progress[key]?.pool == pool {
            if !eligibleIDs.contains(state.progress[key]!.wordID) || state.progress[key]?.status == .mastered {
                state.progress[key]?.active = false
            }
        }
        let limit = state.configuration(pool).limit
        let existing = state.progress.values.filter { $0.pool == pool && $0.active && $0.status != .mastered }
            .sorted { ($0.lastSeen ?? .distantPast, $0.key) < ($1.lastSeen ?? .distantPast, $1.key) }
        if existing.count > limit {
            for item in existing.prefix(existing.count - limit) { state.progress[item.key]?.active = false }
        }
        let capacity = max(0, limit - state.activeCount(pool))
        // Resume parked work before introducing fresh pairs. Shuffle fresh words independently per pool.
        let parked = eligible.filter { word in
            guard let progress = state.progressFor(word.id, pool) else { return false }
            return !progress.active && progress.status != .mastered
        }.sorted { $0.createdAt < $1.createdAt }
        let fresh = eligible.filter { state.progressFor($0.id, pool) == nil }.shuffled()
        for word in (parked + fresh).prefix(capacity) {
            var progress = state.progressFor(word.id, pool) ?? Progress(wordID: word.id, pool: pool)
            progress.active = true
            state.progress[progress.key] = progress
        }
    }

    public static func next(_ pool: Pool, state: AppState, now: Date = Date(), excluding: UUID? = nil) -> WordPair? {
        let turn = state.configuration(pool).turn
        let candidates = state.words.compactMap { word -> (WordPair, Progress)? in
            guard state.eligible(word, for: pool), let p = state.progressFor(word.id, pool), p.active, p.status != .mastered else { return nil }
            if p.status == .reinforce && (p.dueAt ?? .distantFuture) > now { return nil }
            return (word, p)
        }
        let alternatives = candidates.filter { $0.0.id != excluding }
        let available = alternatives.isEmpty ? candidates : alternatives
        return available.sorted { lhs, rhs in
            let left = lhs.1, right = rhs.1
            if left.status != right.status { return left.status == .reinforce }
            let l = max(turn, left.nextTurn), r = max(turn, right.nextTurn)
            if l != r { return l < r }
            if left.misses != right.misses { return left.misses > right.misses }
            return (left.lastSeen ?? .distantPast, left.key) < (right.lastSeen ?? .distantPast, right.key)
        }.first?.0
    }

    public static func grade(wordID: UUID, pool: Pool, direction: Pool, correct: Bool, state: inout AppState, now: Date = Date()) throws {
        guard let word = state.words.first(where: { $0.id == wordID }), state.eligible(word, for: pool),
              var progress = state.progressFor(wordID, pool), progress.active, progress.status != .mastered,
              pool.accepts(direction: direction) else {
            throw SprechenError.message("This card is no longer available for this exercise.")
        }
        if progress.status == .reinforce && (progress.dueAt ?? .distantFuture) > now {
            throw SprechenError.message("This Reinforce review is not due yet.")
        }
        var config = state.configuration(pool)
        config.turn = max(config.turn, progress.nextTurn) + 1
        progress.attempts += 1; progress.lastSeen = now
        if correct {
            progress.correct += 1; progress.streak += 1
            if progress.status == .reinforce {
                progress.reinforceStep += 1
                if progress.reinforceStep >= 2 {
                    progress.status = .mastered; progress.active = false; progress.dueAt = nil
                } else { progress.dueAt = now.addingTimeInterval(Double(config.secondReviewDays) * 86_400) }
            } else if progress.streak >= config.target {
                if progress.misses >= 2 {
                    progress.status = .reinforce; progress.reinforceStep = 0
                    progress.dueAt = now.addingTimeInterval(Double(config.firstReviewDays) * 86_400)
                } else { progress.status = .mastered; progress.active = false }
            } else { progress.nextTurn = config.turn + min(12, 1 << min(progress.streak, 4)) }
        } else {
            progress.streak = 0; progress.misses += 1; progress.status = .learning
            progress.reinforceStep = 0; progress.dueAt = nil; progress.nextTurn = config.turn + 3
        }
        state.settings[pool.rawValue] = config
        state.progress[progress.key] = progress
        state.reviews.append(Review(wordID: wordID, pool: pool, direction: direction, correct: correct, date: now))
        replenish(pool, state: &state)
    }

    public static func setReinforceDelays(_ pool: Pool, firstDays: Int? = nil, secondDays: Int? = nil, state: inout AppState) {
        var config = state.configuration(pool)
        if let firstDays { config.firstReviewDays = min(365, max(1, firstDays)) }
        if let secondDays { config.secondReviewDays = min(365, max(1, secondDays)) }
        state.settings[pool.rawValue] = config
        // Recalculate from the last graded answer, never from the time the setting changes.
        for key in Array(state.progress.keys) {
            guard let progress = state.progress[key], progress.pool == pool,
                  progress.status == .reinforce, let anchor = progress.lastSeen else { continue }
            let days = progress.reinforceStep == 0 ? config.firstReviewDays : config.secondReviewDays
            state.progress[key]?.dueAt = anchor.addingTimeInterval(Double(days) * 86_400)
        }
    }

    public static func setPaused(_ paused: Bool, wordID: UUID, state: inout AppState) {
        guard let index = state.words.firstIndex(where: { $0.id == wordID }) else { return }
        state.words[index].paused = paused
        for key in Array(state.progress.keys) where state.progress[key]?.wordID == wordID {
            state.progress[key]?.active = false
            if !paused {
                state.progress[key]?.streak = 0; state.progress[key]?.status = .learning
                state.progress[key]?.reinforceStep = 0; state.progress[key]?.dueAt = nil
                state.progress[key]?.nextTurn = 0
            }
        }
        for pool in Pool.allCases { replenish(pool, state: &state) }
    }
}
