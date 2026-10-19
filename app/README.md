# VocabApp — offline beta 0.2

Flutter application for Android and Windows. The first implementation covers the local learning loop; the product specification is in `../docs/`.

## Implemented

- English → Vietnamese manual vocabulary; distinct senses; drafts and explicit approval.
- Paste up to 500 lines as drafts, with duplicate detection and atomic writes.
- Create/rename/archive groups; attach an entry to multiple groups or remove membership without resetting progress.
- Search terms/meanings, draft filter, pause/resume cards.
- Reveal-first flashcards, four ratings, baseline scheduler v1, due cards before new cards.
- Daily new-card limit, day boundaries in Asia/Ho_Chi_Minh, 20-card sessions.
- SQLite persistence, foreign keys, atomic review events and schedule updates; review retries are idempotent.
- Responsive navigation and keyboard shortcuts in review: Space reveals, 1–4 rates after reveal.

Reopening a session recomputes its queue from persisted card state; the exact order of an interrupted session is not stored. No sample words are inserted into the personal library automatically.

## Run

From WSL:

```bash
source ../scripts/dev-env.sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter run -d <android-device-id>
```

From Windows PowerShell, with Visual Studio C++ tooling installed:

```powershell
. ..\scripts\dev-env.ps1
flutter pub get
flutter run -d windows
```

Use a Windows-local source checkout for native builds rather than a WSL UNC working directory. Flutter dependencies are locked in `pubspec.lock`. Windows and Android use the same domain and repository code; Android uses the platform SQLite plugin and Windows uses the FFI adapter.

## Build Android alpha

From the repository root in WSL:

```bash
./scripts/build-android-alpha.sh
```

This runs analysis and tests before building an **arm64 debug APK** in `../artifacts/`. The APK uses the local Android debug signing key and is intended for personal testing. Production signing, update distribution and Windows packaging will be configured separately. Android's automatic OS backup is disabled in this alpha to match its local storage behavior.

## Data

`vocabulary.db` is saved under the OS application-support directory. Database schema version: 1. Application ID: `dev.vocabapp.vocabapp`. Do not uninstall or clear application data if you want to retain this alpha library. Use Settings → Backup to export a complete library snapshot. Restore replaces the library with confirmation and keeps a recovery snapshot. See `../docs/12-releases-and-backups.md`.

Tests cover real SQLite reopen, transaction rollback, duplicate/conflict handling, multiple senses/groups, optimistic concurrency, daily limits, suspension, review interactions, and mobile layout with 150% text scaling.

## Following milestones

API configuration and secure key storage, Azure/OpenAI enrichment, CEFR passage extraction, CSV/XLSX/JSON import and Parquet conversion remain on the product backlog. Settings can check GitHub Releases and open the download page; automated in-app download/install is still pending. This alpha does not yet implement those workflows.

## Windows alpha bundle

The Windows release has passed all 16 tests on the development host and has been opened successfully from the extracted ZIP. Run `../scripts/build-windows-alpha.ps1` in Windows PowerShell to recreate the build snapshot and bundle. Extract the whole ZIP and run `vocabapp.exe`; keep `data/` and all DLLs alongside it. This bundle is unsigned and has only been smoke-tested on the development host with the VC++ runtime installed. Installer/update distribution remains on the backlog.

## CI releases

Push to main automatically builds and versions releases; PRs run checks without signing secrets. Download the latest APK, Windows ZIP or installer from https://github.com/chimsedibui/vocabapp/releases/latest. The CI key is stable and matches the local beta certificate; no signing keys are committed. See `../docs/12-releases-and-backups.md` for version rules and backup format.
