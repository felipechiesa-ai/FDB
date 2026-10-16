# 0002: Restore follows the charter: staging, recovery copy, swap, and recovery at launch

- Status: accepted by the owner on 2026-10-16. It replaces the in-place approach proposed earlier the same day.
- Relates to: AGENTS.md §5 "Restore", 01-08

## Decision

Restoring a backup:

1. Validate the backup before touching anything: manifest, format version, snapshot checksum, `PRAGMA integrity_check`, `PRAGMA foreign_key_check`, known migrations, and every listed original's checksum.
2. Copy the backup into a staging folder beside the active library (`Restoring-<timestamp>-<id>`). Open the staged database, which migrates an older snapshot, and check that it passes integrity and foreign-key checks and that every referenced original exists. A failure removes the staging folder.
3. Write a complete backup of the current library into the recovery folder. A failure removes the staging folder.
4. Close the active library. The app replaces its store with an empty in-memory one, so the file-backed database is released before any folder moves.
5. Write a marker file (`restore-in-progress.json`) that names the active, replaced, and staging folders. Move the active library into the recovery folder as `Replaced-<timestamp>-<id>`, then move the staged library into the active place.
6. Reopen the library. On success, remove the marker. If it does not open, move the restored library into the recovery folder as `Failed-Restore-<timestamp>-<id>`, put the previous library back, and reopen it.
7. If neither library opens, the app stays covered by a message to quit and reopen. Nothing is written in the meantime.

### Recovery at launch

Before a library opens, a leftover marker is settled:

| State found at launch | Result |
| --- | --- |
| Active folder missing, previous library in the recovery folder | Previous library moved back |
| Active folder missing, previous library gone, staged library present | Staged library moved into place |
| Active folder present | Kept as is; a leftover staging folder is removed |

The marker is removed last, so an interrupted recovery runs again at the next launch.

## Why

- A failed or cancelled restore leaves the original usable: nothing changes until the staged library is complete and checked. The cancel point is the confirmation dialog; no restore starts without it.
- The previous library is never deleted. It stays in the recovery folder next to a recovery backup.
- Every folder move stays on the same volume and is recorded in the marker first, so an interrupted swap can always be settled at launch.

## Trade-offs

- While the swap runs, the app shows an empty in-memory placeholder under a busy overlay that blocks editing. Nothing is written to disk through it.
- Once staging starts, the restore cannot be cancelled from the UI; it finishes or fails.
- If the app stops after both folders moved but before the restore finished, the restored library stays in place without a success message. The previous library is in the recovery folder.
- Each restore keeps a replaced folder and a recovery backup. Disk use grows with restores. Cleanup is a later decision.

## Tests

`LibraryBackupTests` runs the procedure on real folders: a full restore that keeps the replaced library, a rollback, the three launch-recovery states, a staging failure that leaves no trace, a newer format, a tampered snapshot, and a broken relationship.
