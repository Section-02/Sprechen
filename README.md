# Sprechen

A local-only German vocabulary app for iPhone, built with SwiftUI and SQLite. Deployment target: iOS 16.0. No dependencies, account, server, analytics, cloud sync, or cloud backup.

## Open and run

1. Open `Sprechen.xcodeproj` in Xcode.
2. Select the **Sprechen** target → **Signing & Capabilities** → your Apple Developer team. The initial bundle identifier is `com.section02.Sprechen`; change it if your team needs a different one.
3. Choose an iPhone simulator or your connected iPhone and run. Enable Developer Mode on the physical phone if Xcode requests it.
4. Repeat for the second iPhone. Each installation has independent progress and settings.

The app targets iOS 16 and uses availability-compatible APIs. The first build was compiled with Xcode 26.6 / iOS 26.5 SDK. Actual iOS 16 and physical-device speech checks are still required; setting a deployment target is not a substitute for those checks.

## Study

The home screen has **English → German**, **German → English**, **Mixed**, and **Type German** tiles. Each pool independently defaults to 20 active pairs and a five-answer consecutive-correct target. Change these per pool in Settings (1–500 pairs, 1–50 consecutive correct answers).

- **Type German** shows an English prompt and a text field for the German answer, including the article. Tap Check answer (or the keyboard’s Done key), compare your answer, then self-grade. Autocorrection is disabled; this exercise has no microphone button. Its pool, streaks, Reinforce timing, and settings are independent. Typing alone does not make a word eligible for Mixed.
- Each directional pool independently chooses from the vocabulary list; their pairs may overlap or differ.
- Mixed can use a pair after **at least one graded answer in either directional pool**, even if that answer was incorrect. Merely opening/revealing a card does not count.
- Mixed uses its own streak and graduation state, with a randomly selected translation direction on each card. Its streak spans both directions.
- A pool with fewer eligible pairs than its limit uses all eligible pairs. A limit of 50 with 30 eligible pairs means 30 active pairs.
- Correct answers increase spacing. Incorrect answers reset the streak and return the pair after other cards where possible. If only one pair is available, it can repeat immediately.
- Two lifetime misses in a pool mark a pair as difficult. At the streak target it enters **Reinforce**: first review after 1 day, then a second review 3 days after passing the first by default. Both intervals are adjustable per pool from 1–365 days. Changes reschedule waiting reviews from their last graded answer. A miss resets the streak and returns it to Learning. No early Reinforce reviews.
- Other pairs graduate immediately at the target. A graduated pair stops appearing only in its own pool, which fills the vacancy from eligible words.
- Reinforce pairs count toward the active limit. A fully resting pool shows its next review time.
- Lowering a limit parks surplus pairs and preserves progress. Raising it resumes parked work before introducing new pairs.
- Graduation target changes take effect on the next answer; already graduated pairs stay graduated. Reinforce interval changes update waiting review dates immediately.
- Pause hides a word from all pools. Reactivate preserves answer history and total counts, resets streaks, and makes previously used pools eligible to resume it.
- Every graded answer is saved before advancing. End a session whenever you like.

## Vocabulary and backups

Add and edit pairs manually in **Words**, or import UTF-8 CSV in **Settings**:

```csv
german,english
der Schlüssel,the key
das Fenster,the window
lernen,to learn
```

Vocabulary CSVs have only `german` and `english` columns. IDs are generated internally; any legacy ID column is ignored on import. Quoted fields, commas, multiline text, UTF-8 BOM, and German characters are supported. Exact text-pair duplicates are skipped automatically. A shared German word or English translation creates a conflict for the user to edit, replace, or skip. Imports are staged until confirmed, and invalid files cannot partially overwrite data. Replacing a pair retains its existing identifier and learning history.

Two CSV files form a full manual backup:

- **Vocabulary CSV:** transferable words, with no progress/settings.
- **Progress CSV:** pause state, creation dates, all four pools, settings, and full answer history. Its versioned CSV envelope uses JSON in the `data` column to preserve record types and precision. Version 2 includes Type German. Version 1 backups from before this exercise still restore, giving the new pool its default settings. Import the corresponding vocabulary first. Restore matches exact word-pair text even when identifiers differ across phones, validates the entire file, and asks before replacing local progress/settings. Extra vocabulary already on the device remains.

Choose **On My iPhone** or another local destination when exporting. iOS's Files picker can offer external/cloud destinations; an explicit exported copy is outside the app's storage and backup control. Sprechen itself never initiates a network transfer. Keep copies on a local Mac if desired. Share only the vocabulary CSV to give another device the words while keeping progress independent.

## Privacy and speech

- SQLite lives in Application Support/Sprechen. Both its containing folder and database file have Apple's backup-exclusion attribute. All app settings are in SQLite, not cloud-backed preferences.
- No iCloud entitlements, networking client, remote package dependencies, telemetry, background sync, or retained audio files.
- Speech checks `supportsOnDeviceRecognition` and sets `requiresOnDeviceRecognition = true`. There is no server fallback.
- German answers use `de-DE`; English answers use `en-US`. Microphone and speech authorization are requested only when the user taps Speak.
- A device without the required local recognition support gets an explanation and can continue silently. Local speech assets must already be available; the app does not download models.
- Transcription never grades an answer. Only the user's green/red choice changes progress.
- Recording stops on navigation, backgrounding, revealing, or after 20 seconds.
- The app follows the iPhone's light/dark setting and uses text/icons as well as button colors.

## Development

Core code in `Sources/SprechenCore` is shared directly by the Xcode app and a dependency-free Swift package for macOS tests. UI and microphone code are in `App`.

```sh
swift test
xcodebuild -project Sprechen.xcodeproj -scheme Sprechen \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

After adding source files, regenerate the checked-in project with `python3 scripts/generate_project.py`. The script does not set a signing team. `scripts/make_icon.swift` generates the included icon using native drawing primitives.

See `docs/TESTING.md` for device acceptance checks and `docs/DECISIONS.md` for the agreed feature scope.
