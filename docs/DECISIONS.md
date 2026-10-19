# Product decisions

- Name: Sprechen. Intended for an iPhone 11 and an iPhone 14 Pro.
- iOS 16 minimum; native iPhone SwiftUI app; SQLite storage.
- Local-only runtime and independent data/settings per device. No cloud backups.
- Four exercise tiles selected at session start: English → German, German → English, Mixed, and Type German. All four pools are independent.
- Each pool starts with a configurable limit of 20 word pairs and target of five consecutive correct answers.
- Directional pools can use different pairs. Mixed requires a graded appearance in either directional pool, not both. It never pads its pool with unseen words to meet the limit.
- Mixed is a third exercise with its own progress; it does not alter either directional exercise's streak.
- Automatic replenishment on graduation. Pausing also frees active space.
- Difficult pairs use Reinforce (two delayed reviews). Two misses is the initial difficulty threshold.
- Articles remain in the German text. Users decide whether an omitted article was incorrect.
- Reveal then self-grade with labeled green and red buttons.
- Optional local-only speech transcription, with retry and silent study supported. No pronunciation scoring.
- Add/edit words manually; import/export vocabulary CSV. Exact duplicates skipped; conflicts explicitly reviewed.
- Separate progress/settings CSV with history and stable identities. Vocabulary can be shared independently.
- Pause/reactivate without losing history. Reactivation resets current streaks.
- Short sessions, immediate saving, system light/dark appearance, clean interface with playful color accents.
- No categories, accounts, notifications, subscriptions, leaderboards, or automatic syncing.

- Type German shows English, accepts a typed German answer, then reveals the stored translation for self-grading. It has independent settings and progress and does not affect Mixed eligibility.
