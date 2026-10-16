# 0002: Restore runs in place, after a recovery copy

- Status: proposed, awaiting the owner's decision
- Date: 2026-10-16
- Relates to: AGENTS.md §5 "Restore", 01-08

## Context

The charter describes restore as: restore into a separate temporary library, validate it, close the active database, keep a recovery copy, then switch libraries. A failed restore must leave the original usable.

## Decision taken in code

1. Validate the backup before touching anything: manifest, format version, snapshot checksum, `PRAGMA integrity_check`, `PRAGMA foreign_key_check`, known migrations, and every referenced original's checksum.
2. Write a recovery copy of the current library as a backup (`FDB-Recovery-<timestamp>.fdbbackup`).
3. Copy the referenced originals that are missing into the library's `media/originals`.
4. Replace the contents of the open database with the snapshot, using SQLite's backup API. The backup API runs in one transaction on the destination, so a failure leaves the previous contents.
5. Apply any migrations the restored snapshot is missing.

## Difference from the charter

Steps 4 and 5 replace the database inside the open connection. The charter's "close, then switch libraries" is not done, and no staging library is built first.

## Trade-offs

- **Current approach:** no file swap, so the app never holds a stale file handle and needs no reopen logic. Failure inside the backup transaction rolls back. Cost: the restored database is written into the file the app already uses.
- **Charter approach:** build a staging library, validate it, close the store, rename folders, and reopen. Cost: the app must drop every reference to the old store before renaming, and a crash in the middle needs a recovery path on next launch.

## Decision needed

Keep the in-place approach, or implement the charter's staging and switch. If the charter's approach is required, 01-08 stays incomplete until it is built and tested.
