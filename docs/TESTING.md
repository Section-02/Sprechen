# Verification

## Automated coverage

The Swift package tests cover independent pool graduation and automatic refill; Mixed eligibility from either directional pool and 50/30 capacity behavior; streak reset; Reinforce timing and failure; pause/reactivation; lowering/raising limits; CSV quotes, newlines, Unicode and malformed rows; progress transfers across word identifiers; SQLite reopen/rollback; and backup exclusion.

## Physical-device acceptance checklist

Run on iPhone 11 and iPhone 14 Pro. Include an actual iOS 16 device/runtime if available. The development machine currently has only the iOS 26.5 simulator runtime.

1. Add a noun with an article and umlaut. Edit it. Relaunch and verify persistence.
2. Import `docs/sample-vocabulary.csv`. Repeat: exact duplicates should be skipped. Import a conflicting translation: check edit, replace, skip, and cancel-without-saving.
3. Study each directional pool and confirm distinct streaks. Graduate in one and confirm the other remains available.
4. Enter Mixed before any grading (empty), then after one directional answer (eligible). Configure 50 with fewer eligible pairs and confirm it uses the smaller number.
5. Miss twice, build the target streak, and verify Reinforce is unavailable until due. Automated tests cover timing without changing the device clock.
6. Pause/reactivate, verifying retained answer totals and reset streaks.
7. End a short session and force-close/reopen; the last answer should persist.
8. Export both CSVs to a local destination. Import vocabulary on the other phone; no progress should arrive. Restore progress separately and confirm settings/history.
9. In airplane mode, try German and English transcription. Check microphone-denied and speech-denied states, retry, backgrounding while recording, and leaving the card. A missing local speech model must never cause a network fallback.
10. Check dark mode, larger text, VoiceOver, portrait layout, and the smallest supported display. Green/red buttons must retain their labels and icons.

## Known verification limits

A successful build verifies API availability for the iOS 16 deployment target but does not prove runtime behavior on every iOS release. Real microphone recognition cannot be validated from the simulator. Interactive simulator control was unavailable during initial development, so visual and touch acceptance remain to be completed.

## Initial build results — October 19, 2026

- 11 core tests passed with no failures, including incremental edits/deletions and rollback.
- Simulator build succeeded; initial app launched on the iPhone 11 / iOS 26.5 simulator.
- Unsigned physical-iPhone build succeeded with minimum deployment target iOS 16.0.
- Property lists and Xcode project validated.
- App icon rendering inspected and corrected.
- Signing team selection, installation on the two physical phones, microphone checks, and interactive visual acceptance remain.
