# Data model (Stage 1)

Implemented by migration `v1-people-clubs-rosters` in `Packages/FDBKit/Sources/FDBPersistence/LibrarySchema.swift`.

## Entities

| Table | Key | Relationships | Notes |
| --- | --- | --- | --- |
| `country` | `id` (UUID derived from the ISO 3166-1 code) | none | Seeded with 249 sovereign countries. `iso_code` is unique and external only. |
| `player` | `id` | optional birth country | `display_name` required. `birth_date` is text: `YYYY`, `YYYY-MM`, or `YYYY-MM-DD`. Height 50–260 cm. Foot: right, left, both. |
| `player_alias` | (`player_id`, `alias`) | player (cascade) | Trimmed; duplicates ignoring case and accents are dropped on save. |
| `player_citizenship` | (`player_id`, `country_id`) | player (cascade), country | Many-to-many. |
| `player_position` | (`player_id`, `position_code`) | player (cascade) | Codes: gk, cb, lb, rb, dm, cm, am, lw, rw, cf, unspecified. At most one primary position per player (partial unique index). |
| `club` | `id` | optional country | `display_name` required. `founded_date` is partial. |
| `team` | `id` | club | Category: senior, reserve, youth, other. Gender: mens, womens, mixed, unspecified. A new club gets one `Senior` team. |
| `roster_membership` | `id` | player, team | Shirt number 1–99. Status: current, former, uncertain. |

Matching and sorting use `search_key` and `sort_key` columns: lowercase, diacritic-free text computed on save. Display text is stored unchanged.

## Rules

- Foreign keys are enforced on every connection and use `RESTRICT`. Only link tables cascade when a player row is removed. The app never removes players; it archives them.
- Archive hides a record from default lists. It removes no relationships and rewrites no history.
- Removing a player from a team ends the membership: `end_date` is set and status becomes `former`. The player and the history stay.

## Date semantics

- Exact dates carry no timezone. System timestamps are stored as UTC.
- A partial date keeps its precision. A year-only date never becomes January 1.
- `end_date` is the first day no longer on the roster. Membership spans are `start <= date < end`.
- A start must be before its end when both are exact days. Equal dates are refused.
- The same player cannot have overlapping memberships in the same team. Missing bounds are open. Memberships in different teams may overlap.
- Ages are computed from exact birth dates only. Unknown ages show no value.

## Media (migration v2, 01-06)

| Table | Key | Relationships | Notes |
| --- | --- | --- | --- |
| `media_asset` | `id` (first 16 bytes of `sha256`) | none | `sha256` is unique and names the managed file. Only JPEG and PNG, after metadata removal and orientation. |
| `player_portrait` | `player_id` | player (cascade), asset (restrict) | At most one portrait per player. |
| `club_badge` | `club_id` | club (cascade), asset (restrict) | At most one badge per club. |

Original files live in `media/originals/<sha256>.<ext>`. Thumbnails are cached in `media/thumbnails/` and can be rebuilt. A save writes the file first and then the reference, in one transaction.

## Backups (01-08)

A backup is a folder `FDB-<label>-<timestamp>.fdbbackup` with `manifest.json`, a SQLite snapshot (`database.sqlite`), and the originals the snapshot references. The manifest records the format version (1), the library ID, the applied migrations, the snapshot SHA-256, and the media file names. Newer formats, damaged snapshots, newer schemas, and missing or mismatched originals are refused before anything changes.

## Not in Stage 1

Competitions, editions, matches, and venues.
