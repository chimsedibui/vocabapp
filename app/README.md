# VocabApp — beta 0.3

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

`vocabulary.db` is saved under the OS application-support directory. Database schema version: 2; version 1 migrates without deleting vocabulary or reviews. Application ID: `dev.vocabapp.vocabapp`. Do not uninstall or clear application data if you want to retain this alpha library. Use Settings → Backup to export a complete library snapshot. Restore replaces the library with confirmation and keeps a recovery snapshot. See `../docs/12-releases-and-backups.md`.

Tests cover real SQLite reopen, transaction rollback, duplicate/conflict handling, multiple senses/groups, optimistic concurrency, daily limits, suspension, review interactions, and mobile layout with 150% text scaling.

## API and passage extraction

Settings → API: configure OpenAI key/model, or Azure key/resource endpoint/deployment using the v1 API. Keys/configuration use flutter_secure_storage on the device and are excluded from database backups. Optional fallback must be explicitly enabled. No automatic credential reuse from another project.

Library → Add words from passage: paste English, choose minimum CEFR (default B1) and max items (default 30). Review and edit meanings/levels, choose an existing sense or add a new sense, then approve into a group. No existing meaning or review schedule is overwritten. Compact JSON uses term/level/meaning only. Source grounding and CEFR threshold are checked locally; estimated CEFR still needs human review.

Jobs/results/usage persist locally. Identical successful requests use a 30-day cache; regenerate is explicit. Delete a passage to remove its text/results/usage while preserving accepted words. Backups now use format/DB version 2 with passage/provenance and can restore version 1 snapshots. A 0.2 app cannot open a migrated version 2 database.

See `../docs/13-api-and-passage.md` for budgets, limits, provider compatibility and verification.

## Following milestones

Single-word Azure/OpenAI enrichment, Google Translation fallback, CSV/XLSX/JSON import and Parquet conversion remain on the product backlog. Settings can check GitHub Releases and open the download page; automated in-app download/install is still pending. This alpha does not yet implement those workflows.

## Windows alpha bundle

The Windows release has passed all 16 tests on the development host and has been opened successfully from the extracted ZIP. Run `../scripts/build-windows-alpha.ps1` in Windows PowerShell to recreate the build snapshot and bundle. Extract the whole ZIP and run `vocabapp.exe`; keep `data/` and all DLLs alongside it. This bundle is unsigned and has only been smoke-tested on the development host with the VC++ runtime installed. Installer/update distribution remains on the backlog.

## CI releases

Push to main automatically builds and versions releases; PRs run checks without signing secrets. Download the latest APK, Windows ZIP or installer from https://github.com/chimsedibui/vocabapp/releases/latest. The CI key is stable and matches the local beta certificate; no signing keys are committed. See `../docs/12-releases-and-backups.md` for version rules and backup format.
