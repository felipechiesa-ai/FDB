# FDB — implementation charter and agent instructions

Planning baseline: 2026-10-15. This file describes the intended application; it does not assert that any application code exists. The current deliverable is planning only. Do not begin implementation until the owner requests it.

## 1. Product purpose and confirmed decisions

FDB is an open-source, GUI-driven football (soccer) database for macOS, historically called OS X. It helps a person build, browse, edit, preserve, and explore a football reference library: players, clubs, teams, competitions, seasons, matches, and statistics.

Transfermarkt is a reference for useful information and relationships, not a specification to copy. FDB must develop its own interface, data model, terminology where appropriate, and workflows. Page layouts and scraped structures are evidence about a public information model, not proof of Transfermarkt's internal database schema.

The owner has confirmed:

- Native macOS application using SwiftUI and SQLite.
- Personal, offline operation, with import/export; no shared editing requirement.
- One managed local library for the first release, with backup/import/export.
- MIT license for FDB's code. Third-party data, dependencies, and images retain their own applicable licenses and attribution.
- Stage 1 must deliver a runnable GUI for browsing, creating, and editing player and club profiles, including player headshots, team rosters, and basic biographical organization.
- Planning must have 3–5 implementation stages; this plan uses five.

All routine reading and editing must work without a network connection, a service account, a hosted backend, or a paid data feed. Start with an empty usable library and an optional explicitly selected fictional demo library. Never require sample data to operate the application.

### Scope boundaries

Include factual sporting history, including dated team membership and loans when supported by records. Membership changes are useful career information; they do not require a transfer-market product.

Exclude market valuations, valuation predictions, transfer rumors, news feeds, advertising, betting, agent marketplaces, social features, and transfer-fee/wage analytics from these five stages. Contracts, medical/injury records, scouting ratings, and full staff/referee databases are also deferred. A membership end date must never be presented as a contract expiry date.

Do not add a web server, cloud synchronization, multiplayer editing, public publishing, automatic scraping, mobile clients, or a plugin marketplace without a separate product decision. Do not build a generic sports platform. The schema should accommodate men's, women's, senior, reserve, and youth football without requiring five different implementations.

## 2. Reference evidence and how to use it

The original request mentions scraped page structures and schemas. No separate scrape files or schema dump were available in the inspected workspace. The owner subsequently supplied the competition URL below. Three public pages were inspected in a browser on 2026-10-15; the direct text-fetch service returned HTTP 403 for the competition, but ordinary browser access succeeded.

| Inspected reference | Observed structure | FDB implication |
| --- | --- | --- |
| [Copa LPF Proyección competition](https://www.transfermarkt.us/copa-lpf-proyeccion-final/startseite/wettbewerb/CLPF) | Season selector, participating reserve teams, squad sizes/ages, fixtures/results, two standings tables, scorer list, and a subsequent-competition link | Model competition editions, team participation, groups/phases, and match-derived summaries; do not assume a single flat league table. |
| [CA Boca Juniors II team page](https://www.transfermarkt.us/club-atletico-boca-juniors-ii/startseite/verein/14831/saison_id/2025) | Season-selectable squad, player portraits, positions, birth dates, multiple nationalities, stadium information, and internal team movements | Distinguish club organization from playing team; relate players through dated memberships; support multiple citizenships and team categories. |
| [Benjamín Sagüés Barreiro profile](https://www.transfermarkt.us/benjamin-sagues-barreiro/profil/spieler/1253295) | Portrait, birth date/place, citizenships, height, position, preferred foot, current team, joined date, and separate contract fields | Separate biographical attributes, team history, and derived displays; retain useful sporting information while excluding commercial fields. |

These observations establish feature requirements, not verified database internals or a complete survey of the site. Do not infer official competition rules from a standings widget. The team URL included `saison_id/2025` while its visible selector showed 2026; the player header and detailed citizenship area also exposed different amounts of information. These are reasons to verify source context and completeness, not to invent conversion rules or discard additional citizenships.

When additional owner-provided reference material becomes available, record it in `docs/reference-inventory.md`: artifact/path or URL, access date, observed entity, field, relationships, uncertainty, FDB destination, and accepted/deferred/excluded status. Record schema proposals as proposals. Reconcile new findings with this plan before changing implementation scope.

Do not distribute scraped production datasets or portraits as fixtures by default. Use fictional records and original or explicitly redistributable images for development. External identifiers and source links may be retained as provenance; they must not become FDB's primary keys. Source-specific terminology must not leak into general domain APIs.

## 3. Architecture and technology decisions

### Selected direction and remaining implementation decisions

| Decision | Planning position | When to settle details |
| --- | --- | --- |
| Interface/platform | Confirmed: native macOS with SwiftUI; use small AppKit bridges where native file handling or table behavior needs them | Stage 1 scaffold |
| Database | Confirmed: SQLite. Recommended access library: GRDB through Swift Package Manager, with explicit migrations and relational queries | Validate and record a compatible release in 01-01 |
| Library lifecycle | Confirmed: one managed local library; explicit Save/Cancel for record editing; full-library backup and restore | Stage 1 |
| Minimum OS | Proposed default: macOS 14 or later; record supported Xcode/Swift and hardware architectures after an actual build | Confirm in 01-01; ask owner if older Mac support changes this baseline |
| Distribution | Proposed: direct-download application, initially developer builds; signed/notarized public release when credentials are available | Stage 5; App Store is not required |
| Data supply | Manual entry and local files; optional source-specific importers only under a later scoped request | Generic interchange in Stage 4 |
| Statistics authority | Match records generate computed totals; externally published aggregate totals remain separately labeled evidence | Stage 3 design, extended in Stage 4 |
| Code license | Confirmed: MIT | Add license and notices when implementation starts |

Use GRDB because inspectable SQL, explicit constraints, migration control, and aggregate queries fit this application's relational needs. Its documentation describes observation, concurrency, migrations, and Swift Package Manager integration. Verify the chosen version against the actual macOS build environment; do not track the repository's moving default branch. [GRDB documentation](https://github.com/groue/GRDB.swift/blob/master/README.md)

Use SwiftUI for windows, navigation, tables, forms, and commands. The selected product is a managed-library application, so a normal window lifecycle is the starting point; do not introduce document-based autosave around a live SQLite store just to obtain file menus. [Apple SwiftUI application overview](https://developer.apple.com/documentation/technologyoverviews/swiftui)

Avoid combining GRDB with a second authoritative ORM/store such as SwiftData or Core Data. Avoid Electron/Tauri, Redux-like frameworks, dependency-injection frameworks, or a custom ORM unless a documented requirement justifies reconsidering the selected architecture. Keep dependencies few, maintained, license-compatible, and pinned through the committed resolution file.

### Layers and dependency direction

Use a modular monolith, not services or a web API:

```text
SwiftUI screens and presentation state
                  |
       Application use cases
          /              \
 Pure domain rules    Repository/media interfaces
                              |
                   SQLite + local filesystem
```

- **Domain:** typed IDs, value types, validation, temporal rules, and statistics definitions. Keep this layer independent of SwiftUI, AppKit, and GRDB.
- **Application:** workflows such as SavePlayer, AssignPlayerToTeam, RecordMatch, ImportPreview, and RestoreLibrary. Coordinate transactions here through narrow persistence APIs.
- **Persistence:** migrations, typed database records, repositories, indexed queries, and observation. Keep SQL out of views. Do not create a generic repository framework for hypothetical entities.
- **Media/library services:** managed paths, image validation, thumbnails, backups, recovery, and later interchange packaging. Keep platform-specific image decoding at the boundary.
- **UI:** feature-oriented views and small presentation models. Use native selection/navigation, visible validation, and explicit loading/error/empty states. No business rules hidden in button handlers.

Use a single controlled database writer and short transactions. Schedule database, image, and import work away from the UI thread; deliver UI state on the main actor. Cancel obsolete searches and prevent stale responses from replacing newer selections. Add a read pool only when measurements justify it. Multiple processes must not write the library simultaneously.

### Proposed repository layout

Create these paths as needed during implementation; this tree is not a request to generate empty modules now.

```text
FDB/
  AGENTS.md
  README.md
  LICENSE
  CONTRIBUTING.md
  THIRD_PARTY_NOTICES.md
  FDB.xcodeproj/                 # Checked-in app project and shared schemes
  App/
    FDBApp.swift
    Composition/                # Construct services and connect dependencies
    Features/
      Library/
      Players/
      Clubs/
      Rosters/
      Competitions/             # Introduce in Stage 2
      Matches/                  # Introduce in Stage 3
      Statistics/               # Introduce in Stage 3
      ImportExport/             # Basic backup UI first, interchange later
    SharedUI/
    Resources/Assets.xcassets/
  Packages/FDBKit/
    Package.swift
    Sources/
      FDBDomain/
      FDBApplication/
      FDBPersistence/
        Migrations/
        Records/
        Repositories/
        Queries/
      FDBLibrary/               # Filesystem, media, backup, interchange
    Tests/
      FDBDomainTests/
      FDBApplicationTests/
      FDBPersistenceTests/
      FDBLibraryTests/
      Fixtures/                 # Small, fictional, reproducible datasets
  UITests/
  docs/
    architecture.md
    data-model.md
    reference-inventory.md
    statistics-definitions.md
    import-format.md
    decisions/                  # Short architecture decision records
    verification/               # Evidence indexed by substage ID
  scripts/                      # Repeatable build, test, fixture, release tasks
  .github/workflows/            # macOS build/test; release workflow later
```

The app depends on the local package. Package targets follow the layer direction above. Tests exercise real temporary SQLite files where transactions, migration, or persistence behavior matters. Keep runtime databases, imported photos, build products, credentials, and personal libraries out of Git.

## 4. Relational model and invariants

The following is FDB's proposed logical model. It is not copied or reverse-engineered database DDL. Only create tables required by the current stage; preserve the distinctions below so later migrations remain additive where practical.

### Stage 1: people, organizations, playing teams, and media

| Entity | Minimum fields/relationships | Rules |
| --- | --- | --- |
| Player | Stable ID, display name, optional full name/aliases, birth date and precision, birthplace text/country, height in cm, preferred foot, notes, portrait reference, timestamps | Display name is required; names are not unique; age is computed. Unknown height/date/foot stays unknown. |
| Country or territory | Stable ID, display name, optional external code | Country of birth and citizenship are different facts. Avoid using flag emoji or an external code as the primary key. |
| Player citizenship | Player ID, country ID | Many-to-many; no comma-separated strings; no automatic sporting-eligibility inference. |
| Position / player position | Controlled position code/label, player ID, primary flag | Allow primary and secondary positions and unspecified position. At most one primary position. |
| Club | Stable ID, display/official names, optional short name, country/city, founded date/year with precision, notes, badge reference, timestamps | Organization identity, not a season entry or a particular playing squad. Similar names are valid. |
| Team | Stable ID, club ID, display name, category, optional age group, competition gender category | A club has one or more teams. Stage 1 creates a default team and permits named reserve/youth teams. Team category is not inferred from a name suffix. |
| Roster membership | Stable ID, player ID, team ID, optional start/end dates, date precision/context, shirt number, status/notes | Player-to-team relationship over time; no permanent `player.club_id` field as the source of truth. |
| Media asset | Stable ID, managed relative path, hash, MIME type, dimensions, optional source/credit/license | Player and club records reference assets with real foreign keys. Thumbnails are derived and rebuildable. |

Common records have creation/update timestamps and an archive flag where appropriate. Use UUID-based IDs independent of display names and source URLs. Use foreign keys and unique constraints on actual identities, not names. A pair table should prevent duplicate citizenship/position links. Apply the relevant checks both in use cases and, where expressible, in SQLite.

Support Unicode names, accents, mononyms, and aliases without forcing Western first-name/last-name fields. Store display text unchanged. Search normalization may fold case and diacritics, but must not change identity or silently merge records.

Store exact calendar dates without timezones; store system timestamps in UTC. For incomplete biographical dates use explicit year/month/day precision rather than inventing January 1. Exact ages require exact birth dates; otherwise display a qualified value or no age. Do not store age as a mutable database field.

For exact roster dates, use inclusive start and exclusive end (`start <= date < end`); label the UI's end field as the first day no longer on the roster. If a source supplies a last active day, translate it explicitly. Unknown start is not evidence of lifelong membership. An explicit current/former/uncertain status supports incomplete records; historical queries must label uncertain inclusion instead of treating missing dates as confirmed history. Invalid reversed ranges are errors. Overlap in the same player/team membership needs correction or review; membership in different teams can legitimately overlap. Shirt numbers belong to a membership context and need not be globally unique.

Archiving hides records from default directory results without deleting relationships or rewriting history. End a roster membership to remove a player from a team; do not delete the player. Restrict hard deletion of referenced entities. No automatic cascade may erase career or match history.

### Stage 2: competition organization and history

Introduce these explicit relationships:

```text
Club 1 ---- N Team
Player N -- N Team                  through dated RosterMembership
Competition 1 -- N CompetitionEdition
CompetitionEdition N -- N Team      through CompetitionEntry
CompetitionEdition 1 -- N Phase
Phase 1 -- N Group                  when the format uses groups
CompetitionEntry N -- N Phase/Group through explicit assignments
```

- A **competition** is the continuing sporting identity, with type (league/cup/mixed), category, organizer, and geographic context. A football association is distinct from a country; do not assume the two are interchangeable.
- A **competition edition** is one occurrence with a season label, actual date range where known, display name, and rules reference. Labels such as `2026`, `2026/27`, `Apertura 2026`, and `Clausura 2026` must coexist. Never derive all dates from a single global season year.
- A **competition entry** links one team to an edition. A team can enter multiple competitions concurrently; a club must not have one authoritative `league_id` column.
- **Phases and groups** describe league rounds, groups, and knockouts. Record explicit links between distinct editions when needed; do not automatically collapse a source's separately listed playoff into a phase or double-count its results.
- **Roster views** can show membership as of a date or membership overlapping an edition, with the difference labeled. Competition-specific registration, if implemented, is a separate eligibility relation, not a replacement for team membership or match appearances.
- Add **venues** and dated team-venue assignments when stadium detail is introduced. Club residence, competition organizer, home venue, and citizenship must not share one overloaded country field.
- Extend membership history with factual loan/return/promotion notes and links between related spells. Contract ownership and transfer fees remain outside scope.

Do not require fully known dates to enter historical records. Keep uncertain facts visibly uncertain. Preserve past names through aliases or effective-dated names when needed; club renames must not create a new identity automatically.

### Stage 3: matches and statistical facts

Use `Match` linked to an edition/phase and two distinct competition entries. Store optional kickoff date/time and timezone context, venue, status, round, scores, and evidence. Support scheduled, postponed, completed, abandoned, cancelled, and awarded outcomes. A scheduled match with no result is not a 0–0 draw. Use separate regulation/extra-time/shootout fields; shootout conversions do not increase ordinary goals scored.

Use `MatchSquadEntry` for a player named by a team, including starter, used substitute, unused substitute, and unknown participation status. Store played intervals or a clearly labeled reported minutes value. A bench selection is not an appearance. Match team affiliation is a historical fact and must not be recomputed from the player's current roster. Allow a match participant whose historical membership is incomplete, with a visible review warning.

Use typed `MatchEvent` records for goals, own goals, cards, and substitutions. Preserve period and added-time notation such as `45+2`; a raw integer minute alone is insufficient. Do not make a complete event log mandatory to record a verified final score. Event completeness and lineup completeness are separate attributes.

Define initial statistics in `docs/statistics-definitions.md`: appearances, starts, minutes, goals, assists where known, yellow cards, second-yellow dismissals, straight reds, and team played/won/drawn/lost/goals/points. Keep unknown separate from zero. Explain treatment of own goals, abandoned/awarded matches, extra time, and disciplinary counts. Defer xG, tracking data, possession models, and subjective player ratings.

There must be one explicit authoritative representation per match metric: event-derived when coverage is complete, otherwise a separately labeled reported match total. Do not add both together. Validate disagreements and preserve provenance. Seasonal and career totals are reproducible queries or rebuildable caches; do not let users silently edit a computed total independently of its facts.

Historical sources may provide only **published aggregate statistics**. Store those in a separate dataset with player/team, edition, optional phase, metric definition, period/scope, source, and coverage. Display published totals and totals computed from recorded matches distinctly. Never sum an aggregate over matches it already contains. Any future coverage reconciliation needs an explicit tested policy before combining datasets.

Standings calculations use edition/phase-specific rules. Initially support ordinary points tables with configurable win/draw/loss points and a documented supported tie-break sequence, plus basic knockout results. Store deductions/adjustments separately with reasons. Unsupported rules must produce a limitation notice rather than an invented official ranking; tied teams may remain unresolved. Persist a published table separately if users need to record an official table that the supported rule engine cannot reproduce.

## 5. Library durability, images, and interchange

### Managed storage

Locate the active library through the platform's Application Support API, not a hard-coded username or repository path. The proposed layout is:

```text
Application Support/<FDB bundle identifier>/Library/
  manifest.json             # Library identity and format version
  database.sqlite           # Authoritative structured facts
  media/originals/          # Managed, immutable image files
  media/thumbnails/         # Rebuildable cache
```

SQLite journal/WAL files may exist alongside the database. Enable and verify foreign-key enforcement on every connection; configure journal behavior intentionally. Use parameterized queries. Keep transactions short and fail clearly for disk-full, lock, permissions, or damaged-library conditions. [SQLite foreign-key documentation](https://www.sqlite.org/foreignkeys.html)

Migrations are ordered, versioned, and forward-only. Never edit an already released migration or reset a user's library to fix an upgrade. Back up before migration; preserve the original on failure. Reject unsupported newer formats safely. Reverting an application version does not imply a safe database downgrade: restore a compatible backup instead.

Backups must include a coherent database snapshot, its manifest, and all referenced original media. Use SQLite's backup facilities rather than copying a live database file. Temporarily coordinate application mutations and media cleanup so the database snapshot and referenced files agree. Write to a temporary destination, validate it, then atomically finalize. [SQLite backup documentation](https://sqlite.org/backup.html)

Restore into a separate temporary library, validate format/relationships/media, close the active database, preserve a recovery copy, then switch libraries. A cancelled or failed restore must leave the original usable. Test this using actual files, not only mocked calls. Stage 1 may use a documented backup directory/package; compression is not a prerequisite. Live network/shared-folder or cloud-folder editing is unsupported; export a closed backup for transport.

### Image workflow

Stage 1 supports selecting a local JPEG or PNG headshot or club badge, previewing it, replacing it, and removing the reference. Validate actual decoding, byte size, and pixel dimensions; handle orientation. Show a tasteful placeholder for missing images. Cropping controls and extra codecs are optional later refinements, not MVP gates.

Copy accepted images into managed storage. Do not retain the original external file path as the only copy. Use non-user-controlled filenames and relative references; never interpret an imported path as permission to read arbitrary files. Decode/downsample thumbnails off the UI thread and cache them by content identity.

Database and filesystem writes are not one atomic transaction. Stage an image, finalize its immutable managed file before committing its database reference, and retain old assets until safe cleanup. A crash may leave an unreferenced file, but must not leave a committed reference to an image that was never stored. Clean up orphan files conservatively; defer deletion while backups are reading them. Keep originals out of source control and include them in backup validation.

### Import/export contract

Stage 1 provides complete-library backup/export and restore/import into the managed library. It does not promise arbitrary CSV merging. Stage 4 adds structured interchange:

- UTF-8 CSV for flat datasets such as players, clubs, teams, memberships, and match records, with documented columns, ID references, date precision, units, and null representation.
- Versioned JSON plus referenced media for a relational exchange package. This is distinct from a full database backup and should remain readable independently of GRDB.
- GUI workflow: choose file, map columns, preview entities and relationships, inspect errors/duplicates/conflicts, choose resolutions, then commit. Cancellation before commit changes nothing.
- Source-scoped external IDs use a unique `(source, entity type, external ID)` mapping. Re-importing an unchanged dataset is idempotent. Missing rows do not imply deletion. Names alone never trigger an automatic merge.
- Do not overwrite manual corrections silently. Persist import provenance, source timestamps where available, and the user's resolution policy. Reject dangling references and malformed files before committing the accepted set.
- Import batches have IDs, summaries, and error reports. Use transactions and a pre-import backup. An undo may reverse a batch only if later edits can be preserved; otherwise offer explicit recovery from backup with a clear explanation.
- Exports preserve original text and identifiers, explain dataset scope, and avoid spreadsheet formula execution hazards in CSV intended for spreadsheet use. JSON provides a lossless alternative when CSV escaping changes display text.

Do not couple the generic import engine to Transfermarkt HTML. A future source adapter converts external files into the documented staging format, independently of core persistence and UI.

## 6. GUI and interaction requirements

FDB should feel like a Mac reference-library editor: a restrained sidebar, searchable sortable lists/tables, and a spacious detail pane with a portrait or badge and clear sections. Reuse native controls and system typography. Build an original information hierarchy without reproducing Transfermarkt's web chrome or dense commercial panels.

Stage 1 navigation includes Players, Clubs, and library/settings actions. Club details contain team selection and rosters; player details link back to memberships. Add Competitions in Stage 2, Matches/Statistics in Stage 3, and richer import/export in Stage 4. Avoid nonfunctional navigation placeholders.

Required interaction rules:

- Create, view, edit, save, cancel, archive, and restore archived player/club profiles through the GUI. Only the display name and necessary relationship context should be mandatory for a minimal record.
- Group player biography, citizenship, positions, notes, images, and memberships logically. Group club identity, location, badge, teams, and roster views logically.
- Search names/aliases; filter by position, country/citizenship, club/team, and archive status where relevant. Sort deterministically and paginate or incrementally load large result sets.
- Keep table selection and search/filter context when opening a linked profile or returning from an edit. Avoid resetting the whole screen after a database update.
- Unsaved form edits are drafts. Cancel leaves persistent state unchanged; navigating away asks whether to save or discard. Failed saves keep the user's draft visible.
- Provide keyboard navigation, standard menus/shortcuts, contextual labels, VoiceOver names, light/dark appearance, sensible resizing, and readable contrast. State must not be conveyed by color alone.
- Distinguish no data, no search results, loading, incomplete historical coverage, and actual errors. Do not display missing statistics as zero.
- Destructive actions show affected relationships. Bulk changes have previews. Archive is the normal removal path; it is reversible.

English is the initial UI language, but keep user-facing strings localizable and format dates/numbers for the user's locale. Preserve source units only as evidence; use normalized internal units and configurable display where useful.

## 7. Delivery strategy and stage gates

Deliver vertical slices. Each stage ends with an application people can run, not only a database schema or architectural framework. Finish and verify the Stage 1 profile/roster workflow before implementing matches, standings, bulk source adapters, or advanced history.

| Stage | Usable outcome | Release gate |
| --- | --- | --- |
| 1 — Personal football library | Browse/create/edit players and clubs, import local portraits/badges, organize teams and current rosters, search, persist, back up, and restore | Complete the end-to-end MVP scenario below on macOS; GUI build, persistence tests, and backup/media round trip pass. |
| 2 — Seasons and sporting history | Competitions and editions, team participation, historical rosters, basic phases/groups, venues, and linked career navigation | Represent a fictional reserve competition with two groups, multiple editions, and a player changing teams without rewriting previous history. |
| 3 — Matches and trustworthy statistics | Fixtures/results, lineups/events, player/team totals, supported standings, and separately labeled published historical totals | A small hand-calculated dataset agrees with all displayed totals; corrections propagate and incomplete coverage remains visible. |
| 4 — Data exchange and research | CSV/JSON interchange with preview, duplicate/conflict handling, provenance, saved filters, and focused comparisons | Export/import round trip preserves relationships/media; repeated imports do not duplicate; malformed/cancelled imports leave the library intact. |
| 5 — Public release and durability | Documented, accessible, tested, packaged open-source application with demonstrated upgrade/recovery paths | Fresh-machine build/install and upgrade/restore drills pass; license/notices and release documentation are complete; signing/notarization state is honestly reported. |

### Stage 1 acceptance scenario

On a supported Mac, from a fresh checkout and a new empty library:

1. Build and launch the actual desktop app using documented commands and the shared app scheme.
2. Create two fictional clubs, including a badge, and create a senior and reserve team under one club.
3. Create three players: one with two citizenships and multiple positions, one with a partial birth date, and one with only a name. Attach a local portrait to one player.
4. Add players to teams with membership dates and shirt numbers. Navigate from a club roster to a player and back. Permit legitimate membership in both senior and reserve teams.
5. Edit a profile and save; begin another edit and cancel. Search an accented name with an accent-insensitive query. Verify same-name players remain separate.
6. End a membership, archive/unarchive a profile, and confirm related records remain intact. Try an invalid date interval and verify a useful error with no partial write.
7. Quit and reopen. Verify profiles, memberships, images, and edits persist. Move/delete the originally selected image file outside FDB and confirm the managed portrait still works.
8. Export a complete backup; change a record; restore the backup through the GUI and verify the expected earlier state and media. Verify a malformed backup is refused without damaging the active library.
9. Repeat core navigation/editing with the network unavailable. Inspect keyboard access, VoiceOver labels, light/dark appearance, and an ordinary smaller window size.

This is the definition of the first useful release. A mockup, a command-line tool, an in-memory demo, or a form disconnected from durable storage does not satisfy it.

### Test and verification policy

Test important behavior and failure modes, not implementation details. Use pure domain tests for dates, identity, roster overlap, and statistical definitions; temporary on-disk SQLite tests for constraints, transactions, migrations, imports, and restore; macOS UI tests for a small set of critical user journeys.

Every schema-changing stage needs both fresh-database and upgrade-from-previous-stage checks. Retain fictional historical database fixtures for supported released formats. Test interruptions around image import, restore, and migration. Restore tests include relationship and media checks, not merely successful database opening.

Set provisional performance budgets and measure them on documented hardware: Stage 1 directory queries should normally complete within 200 ms on 10,000 synthetic players/500 clubs, and ordinary local saves within 500 ms excluding image decoding. Stage 5 expands to 100,000 players and 250,000 matches, with indexed filtered queries targeting 500 ms or less and no long UI-thread blocking. These are engineering targets, not achieved claims; record cold/warm conditions and adjust with evidence rather than silently weakening gates.

macOS GUI, SwiftUI/AppKit integration, signing, and notarization require an appropriate Mac environment. Work performed elsewhere may validate documentation, data design, and compatible pure logic, but cannot certify the native GUI. Explicitly record unrun checks and keep dependent milestone status incomplete until verified on macOS.

Implementation should establish and document working equivalents of these commands; they are intended interfaces, not commands verified by this planning task:

```sh
swift test --package-path Packages/FDBKit
xcodebuild -project FDB.xcodeproj -scheme FDB -destination 'platform=macOS' build
xcodebuild -project FDB.xcodeproj -scheme FDB -destination 'platform=macOS' test
```

Configure shared schemes and test plans so the app test command actually includes the intended UI tests. A successful build alone is not a UI test. Record toolchain versions, tested OS/architecture, commands, results, and manual verification evidence under `docs/verification/<substage-id>.md`.

## 8. Instructions for implementing agents

1. Read this file, applicable ancestor instructions, existing decision records, and the current substage before editing. Inspect the actual repository; this proposed layout may not yet exist.
2. State the substage being implemented and its observable acceptance criteria. Work in dependency order; avoid pulling later-stage features into the MVP.
3. Resolve routine implementation details autonomously within the confirmed direction. Return to the owner for changes to platform, local/shared operation, storage lifecycle, license, data acquisition, substantial scope, or minimum-OS support with meaningful user impact.
4. Keep UI, domain rules, persistence, and migrations aligned. Update `docs/data-model.md` with entities, relationship cardinalities, constraints, and date semantics when they change.
5. Preserve unrelated work and existing user data. Never treat a production library as a disposable test fixture. Demonstrations and tests use isolated fictional libraries.
6. Introduce the smallest dependency set needed for the current stage. Record version/license rationale and commit resolution files. Do not install an unneeded framework to satisfy a speculative future feature.
7. Protect already working user journeys. Run relevant checks, inspect the native UI for visible changes, and report failures or platform limitations accurately.
8. Document architecture decisions when they change a persistent format, statistical meaning, compatibility promise, or major workflow. Explain the tradeoff and migration implications.
9. Update the final ledger only when a substage's deliverables and acceptance checks are satisfied. Code presence, a schema sketch, or a successful compilation alone is insufficient.
10. Finish each implementation handoff with what changed, how to run/use it, validation performed, limitations, and the next eligible substage. Do not claim later stages are complete through partial groundwork.

### Completion ledger maintenance

The list below must remain the final section and final content of this file. Add new narrative, references, decision notes, and instructions above it. Keep IDs stable; append new substages within the appropriate stage without renumbering existing IDs. Use `[NOT COMPLETE]` until all acceptance criteria are verified, then `[COMPLETE]` with a link to evidence placed before the status marker. Blockers and partial progress belong in verification notes; they do not count as completion. All implementation substages are initially incomplete because this work is planning only.

## 9. Implementation substage ledger

- 01-01: Establish the project contract and native build scaffold. Record confirmed decisions, review the available reference inventory, validate GRDB/toolchain/minimum-OS compatibility, add the MIT license and dependency notices, and create the app project/local package/shared schemes. Acceptance: a fresh checkout builds and opens a native window on a supported Mac; record the exact environment. Dependencies: none after implementation is authorized. [Evidence](docs/verification/01-01.md) [COMPLETE]
- 01-02: Implement the managed library and initial relational schema. Add player, country/citizenship, position, club, team, membership, and media records with stable IDs, constraints, versioned migrations, repository APIs, and isolated test fixtures. Acceptance: valid records survive reopening, invalid relationships roll back, and empty-library creation is repeatable. Depends on 01-01. [NOT COMPLETE]
- 01-03: Build the working directory/navigation shell. Add Players and Clubs directories, native selection/detail navigation, search, deterministic sorting, basic filters, and useful loading/empty/error states using real persisted data. Acceptance: searching and switching records preserves context and works with an empty library and the synthetic dataset. Depends on 01-02. [NOT COMPLETE]
- 01-04: Deliver player profile browsing and editing. Implement minimal create/edit/save/cancel, biography, partial birth dates, multiple citizenships, positions, notes, aliases, archive/unarchive, and validation. Acceptance: same-name players remain distinct, cancelled edits leave no changes, and accepted changes persist after relaunch. Depends on 01-03. [NOT COMPLETE]
- 01-05: Deliver club profiles and team organization. Implement club create/edit/save/cancel, location/founding fields, notes, archive/unarchive, default team creation, and explicit senior/reserve/youth team identities. Acceptance: one club can contain two separately browsable teams without duplicating the club. Depends on 01-03. [NOT COMPLETE]
- 01-06: Add managed portraits and club badges. Implement local JPEG/PNG selection, validation, preview, replace/remove, managed copies, thumbnails, placeholders, and recoverable image/database write ordering. Acceptance: both profile types retain images after the source file disappears; invalid files and cancellation preserve the previous state. Depends on 01-04 and 01-05. [NOT COMPLETE]
- 01-07: Implement usable team rosters. Add/remove via dated membership, edit shirt numbers/status, distinguish current/former/uncertain memberships, and navigate both player-to-team and team-to-player. Acceptance: ending a membership preserves the player, concurrent senior/reserve membership works, and reversed dates fail without partial writes. Depends on 01-04 and 01-05. [NOT COMPLETE]
- 01-08: Deliver full-library backup/export and restore/import. Include database, manifest, and referenced original images; validate a staged restore, preserve recovery data, and surface errors through the GUI. Acceptance: round-trip a library with images and relationships; refuse invalid/newer formats without replacing the active library. Depends on 01-06 and 01-07. [NOT COMPLETE]
- 01-09: Verify and package the first runnable milestone. Complete the Stage 1 acceptance scenario, native keyboard/accessibility/appearance checks, focused automated tests, basic performance measurements, macOS CI, and README build/use instructions. Acceptance: a contributor can build and use the offline profile-and-roster app; record evidence and remaining nonblocking limitations. Depends on 01-01 through 01-08. [NOT COMPLETE]
- 02-01: Add competition and edition management. Implement geographic/association context, competition categories, flexible season labels, edition dates, and team entries without assigning a single league to each club. Acceptance: one team enters two competitions and multiple differently labeled editions; Stage 1 libraries upgrade without lost data. Depends on Stage 1. [NOT COMPLETE]
- 02-02: Add phase/group organization and edition relationships. Support simple league, grouped, and knockout structures, assignment of entries, and explicit related-edition links. Acceptance: represent a fictional reserve tournament with two groups and a related playoff without duplicating team identities or conflating stages. Depends on 02-01. [NOT COMPLETE]
- 02-03: Expose historical rosters and career timelines. Add date/edition selection, clear as-of versus participated-during views, and factual membership transitions including loan/return/promotion notes. Acceptance: moving a player between teams preserves earlier views, and uncertain dates remain labeled rather than fabricated. Depends on 02-01 and 01-07. [NOT COMPLETE]
- 02-04: Add venue profiles and historical identity context. Create venues and dated team-venue assignments; support aliases/effective names where needed for clubs and competitions. Acceptance: a shared stadium and a renamed club display correctly without rewriting historical identity or creating duplicate clubs. Depends on 02-01. [NOT COMPLETE]
- 02-05: Integrate competition browsing and historical navigation. Link competition editions, participating teams, rosters, player careers, and venues; show scoped squad counts and qualified age summaries without market metrics. Acceptance: navigate a complete edition-to-team-to-player path with filters preserved and coverage explained. Depends on 02-02 through 02-04. [NOT COMPLETE]
- 02-06: Verify the sporting-history milestone. Test temporal boundaries, legitimate overlaps, multiple citizenships, cross-year/split-season labels, reserve-team independence, and migrations from Stage 1. Acceptance: the Stage 2 release scenario works in the native GUI and regression journeys still pass. Depends on 02-05. [NOT COMPLETE]
- 03-01: Add fixtures, results, and match editing. Link matches to edition/phase entries, venues, dates/timezones, rounds, status, and separated regulation/extra-time/shootout scores. Acceptance: scheduled, postponed, completed, awarded, and cancelled fixtures behave distinctly; a team cannot play itself. Depends on Stage 2. [NOT COMPLETE]
- 03-02: Add match squads, appearances, and basic events. Implement starters/substitutes, played or reported minutes, goals/own goals, assists where supported, cards, substitutions, period/added-time notation, and completeness flags. Acceptance: an unused substitute is not an appearance and missing event detail does not prevent recording a result. Depends on 03-01. [NOT COMPLETE]
- 03-03: Implement reproducible player and team statistics. Document metric definitions and authority rules, derive match/edition/career summaries, label coverage, and refresh totals after corrections. Acceptance: a hand-calculated dataset including own goals, substitutions, and extra time agrees with displayed totals; unknown is not zero. Depends on 03-02. [NOT COMPLETE]
- 03-04: Add historical published statistics support. Store manual or later-imported aggregate datasets with explicit player/team/edition/phase scope, metric definitions, source, and coverage; display them separately from computed match totals. Acceptance: a published season total and its recorded matches coexist without double counting. Depends on 03-03. [NOT COMPLETE]
- 03-05: Implement supported standings and knockout results. Add configurable points/tie-break rules, group-specific tables, explicit deductions, and separated published standings where rules are unsupported. Acceptance: a known table recalculates after a result correction and an unsupported tie-break does not produce a falsely official ranking. Depends on 03-01 and 03-03. [NOT COMPLETE]
- 03-06: Integrate match and statistics browsing and verify the milestone. Add fixtures/results lists, match detail navigation, scorer tables and scoped player/team summaries; test abandoned/awarded matches, shootouts, incomplete data, and migration/regression paths. Acceptance: complete the Stage 3 release gate in the GUI with reproducible calculation evidence. Depends on 03-04 and 03-05. [NOT COMPLETE]
- 04-01: Define and implement portable exchange formats. Document versioned CSV/JSON schemas, null/date/unit/ID conventions, media manifests, and source mappings; implement exports separate from database backups. Acceptance: exported fictional datasets are readable without the app and retain relationship identities. Depends on Stage 3. [NOT COMPLETE]
- 04-02: Build the import preview and validation workflow. Add file selection, column mapping, staging, row/reference validation, useful error reports, progress, and cancel behavior. Acceptance: no persistent changes occur during preview; broken references and malformed dates are identified before commit. Depends on 04-01. [NOT COMPLETE]
- 04-03: Implement identity resolution, provenance, and safe import commits. Add source-scoped IDs, duplicate candidates, user-selected merges/conflict policies, manual-edit preservation, batch records, transactional writes, and pre-import recovery. Acceptance: unchanged re-import is idempotent; ambiguous names are not auto-merged; failed imports preserve the library. Depends on 04-02. [NOT COMPLETE]
- 04-04: Add focused research tools. Implement saved filters, configurable columns, and side-by-side player/team comparisons using existing fields and explicitly compatible statistic scopes. Acceptance: users can compare two players within the same edition/coverage context and export the displayed selection; incompatible or missing data is clearly identified. Depends on 04-01 and 03-06. [NOT COMPLETE]
- 04-05: Verify exchange and research workflows end to end. Round-trip biographies, memberships, editions, matches, aggregate datasets, and media; test Unicode, partial dates, duplicates, archive state, malformed input, cancellation, and recovery after conflict resolution. Acceptance: IDs/relationships and meanings survive exchange and core offline workflows still pass. Depends on 04-03 and 04-04. [NOT COMPLETE]
- 05-01: Harden migration, recovery, and data integrity. Test supported historical library versions, crash/interruption boundaries, missing media, disk/permission failures, unsupported newer formats, and backup restore on a clean installation. Acceptance: failures never silently reset or discard the user's library and recovery instructions are demonstrated. Depends on Stage 4. [NOT COMPLETE]
- 05-02: Complete accessibility, performance, and platform verification. Audit keyboard/VoiceOver/resizing/appearance, run documented large synthetic datasets, inspect slow queries and memory use, and verify every advertised OS/architecture. Acceptance: measured results satisfy documented budgets or an explicitly agreed revision; no untested platform support is claimed. Depends on Stage 4. [NOT COMPLETE]
- 05-03: Prepare contributor and user documentation. Finish installation, quick-start, schema/statistics/import guides, architecture decisions, troubleshooting, contribution workflow, MIT licensing, third-party notices, and fictional demo provenance. Acceptance: a new contributor can build/test and a new user can create, import, back up, and recover a library from the documentation. Depends on 05-01 and 05-02. [NOT COMPLETE]
- 05-04: Produce reproducible release artifacts. Automate versioned builds and packaging, document the toolchain, include release notes/checksums, and configure signing/notarization without storing credentials in Git. Acceptance: test the packaged application on a clean supported Mac; if signing credentials are unavailable, record the blocker and keep the signed-release requirement incomplete. Depends on 05-03. [NOT COMPLETE]
- 05-05: Complete the public-release readiness review. Re-run critical installation, upgrade, editing, statistics, interchange, and restore journeys; resolve release-blocking defects and record supported formats/platforms and known limitations. Acceptance: all stage gates have evidence and the release is ready for owner-authorized publication; publication itself requires a separate request. Depends on 05-04. [NOT COMPLETE]
