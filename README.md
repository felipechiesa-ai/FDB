# FDB

FDB is an offline, native macOS app for keeping a personal football (soccer) reference library: players, clubs, teams, and rosters. It is designed to work without a network connection. The data stays on your Mac in one managed library.

FDB is open source under the [MIT license](LICENSE). Third-party components keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

**Status:** Stage 1 is in progress and not yet released. Players, clubs, teams, rosters, portraits and badges, backup, and restore are implemented and tested. Several screens still need checks on a real Mac; see [docs/verification](docs/verification).

## Requirements

- macOS 26 on Apple silicon. Verified on macOS 26.6.2 (arm64).
- Xcode 27.0 with the Swift 6.4 toolchain. Other versions are untested.

## Build and test

From the repository root, run the package tests:

```bash
swift test --package-path Packages/FDBKit
```

Build the app:

```bash
xcodebuild -project FDB.xcodeproj -scheme FDB -destination 'platform=macOS' build
```

Build the app and run its UI tests, which launch the app, several of them with fictional demo data:

```bash
xcodebuild -project FDB.xcodeproj -scheme FDB -destination 'platform=macOS' test
```

Measure the Stage 1 performance budgets on a synthetic library of 10,000 players and 500 clubs:

```bash
FDB_PERFORMANCE=1 swift test --package-path Packages/FDBKit --filter LibraryPerformanceTests
```

The timings are printed to the test log and recorded in [docs/verification/01-09.md](docs/verification/01-09.md).

## Run the app

Open `FDB.xcodeproj` in Xcode, choose the **FDB** scheme and **My Mac**, and press Run.

The first launch creates an empty library. To look around with fictional data, add the launch argument `-FDBDemoLibrary` to the FDB scheme (Edit Scheme, then Run, then Arguments). The demo uses its own folder and never touches your library.

## Your data

FDB is sandboxed, so the library lives in the app's container:

```
~/Library/Containers/com.pipachiesa.FDB/Data/Library/Application Support/com.pipachiesa.FDB/Library/
```

The folder holds `database.sqlite`, a `manifest.json`, and `media/` with your portraits and badges. Do not edit these files while FDB is open.

## Backup and restore

- **Library, then Back Up Library…** writes a backup folder named `FDB-Backup-<timestamp>.fdbbackup`. It holds the database, a manifest, and every image the library references. Pick any folder you can write to.
- **Library, then Restore Library…** checks the backup first. If the backup passes, FDB asks for confirmation and then replaces the current library. Before it does, FDB keeps a recovery backup and the replaced library in `Recovery/` inside `com.pipachiesa.FDB`.
- A backup that is damaged, incomplete, or made by a newer version of FDB is refused, and the current library does not change.

The restore procedure is described in [docs/decisions/0002-restore-procedure.md](docs/decisions/0002-restore-procedure.md).

## Project layout

- `App/`: SwiftUI screens, app composition, and shared views.
- `Packages/FDBKit/`: domain rules (`FDBDomain`), the SQLite store (`FDBPersistence`), and library files, backup, and restore (`FDBLibrary`), with their tests.
- `docs/`: data model, decisions, and verification notes for each substage.
- `AGENTS.md`: the implementation charter and the substage ledger.

## Known gaps

- Not yet checked on screen: the photo picker, the team and membership editors, the Library menu, and the busy and blocked overlays during a restore.
- No accessibility audit yet: VoiceOver, keyboard-only use, dark mode, and small windows.
- No continuous integration yet.
- Each restore keeps the replaced library in `Recovery/`. Nothing removes those copies yet.
