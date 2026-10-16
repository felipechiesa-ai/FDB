import GRDB

/// Ordered, forward-only migrations. Released migrations are never edited.
enum LibrarySchema {
    static let v1Identifier = "v1-people-clubs-rosters"
    static let v2Identifier = "v2-media"

    /// Every migration this build knows, in order.
    static var knownIdentifiers: [String] { [v1Identifier, v2Identifier] }

    static var migrator: DatabaseMigrator { makeMigrator(upTo: nil) }

    /// Migrations up to and including `identifier`. Tests use it to build older library versions.
    static func makeMigrator(upTo identifier: String?) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(v1Identifier) { db in
            try db.execute(sql: createTables)
            try seedCountries(db)
        }
        if identifier != v1Identifier {
            migrator.registerMigration(v2Identifier) { db in
                try db.execute(sql: createMediaTables)
            }
        }
        return migrator
    }

    private static let createMediaTables = """
    CREATE TABLE media_asset (
        id TEXT PRIMARY KEY NOT NULL,
        sha256 TEXT NOT NULL UNIQUE CHECK (length(sha256) = 64),
        file_extension TEXT NOT NULL CHECK (file_extension IN ('png', 'jpg')),
        mime_type TEXT NOT NULL CHECK (mime_type IN ('image/png', 'image/jpeg')),
        pixel_width INTEGER NOT NULL CHECK (pixel_width > 0),
        pixel_height INTEGER NOT NULL CHECK (pixel_height > 0),
        byte_size INTEGER NOT NULL CHECK (byte_size > 0),
        created_at TEXT NOT NULL
    );

    CREATE TABLE player_portrait (
        player_id TEXT PRIMARY KEY NOT NULL REFERENCES player (id) ON DELETE CASCADE,
        asset_id TEXT NOT NULL REFERENCES media_asset (id) ON DELETE RESTRICT
    );

    CREATE TABLE club_badge (
        club_id TEXT PRIMARY KEY NOT NULL REFERENCES club (id) ON DELETE CASCADE,
        asset_id TEXT NOT NULL REFERENCES media_asset (id) ON DELETE RESTRICT
    );
    """

    private static let createTables = """
    CREATE TABLE country (
        id TEXT PRIMARY KEY NOT NULL,
        iso_code TEXT NOT NULL UNIQUE CHECK (length(iso_code) = 2),
        display_name TEXT NOT NULL
    );

    CREATE TABLE player (
        id TEXT PRIMARY KEY NOT NULL,
        display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
        full_name TEXT,
        birth_date TEXT CHECK (birth_date IS NULL
            OR birth_date GLOB '[0-9][0-9][0-9][0-9]'
            OR birth_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
            OR birth_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        birth_city TEXT,
        birth_country_id TEXT REFERENCES country (id) ON DELETE RESTRICT,
        height_cm INTEGER CHECK (height_cm IS NULL OR height_cm BETWEEN 50 AND 260),
        preferred_foot TEXT CHECK (preferred_foot IS NULL OR preferred_foot IN ('right', 'left', 'both')),
        notes TEXT,
        search_key TEXT NOT NULL DEFAULT '',
        sort_key TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE INDEX player_sort_order ON player (sort_key, id);

    CREATE TABLE player_alias (
        player_id TEXT NOT NULL REFERENCES player (id) ON DELETE CASCADE,
        alias TEXT NOT NULL CHECK (length(trim(alias)) > 0),
        PRIMARY KEY (player_id, alias)
    );

    CREATE TABLE player_citizenship (
        player_id TEXT NOT NULL REFERENCES player (id) ON DELETE CASCADE,
        country_id TEXT NOT NULL REFERENCES country (id) ON DELETE RESTRICT,
        PRIMARY KEY (player_id, country_id)
    );

    CREATE TABLE player_position (
        player_id TEXT NOT NULL REFERENCES player (id) ON DELETE CASCADE,
        position_code TEXT NOT NULL CHECK (position_code IN
            ('gk', 'cb', 'lb', 'rb', 'dm', 'cm', 'am', 'lw', 'rw', 'cf', 'unspecified')),
        is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
        PRIMARY KEY (player_id, position_code)
    );
    CREATE UNIQUE INDEX player_single_primary_position ON player_position (player_id) WHERE is_primary = 1;

    CREATE TABLE club (
        id TEXT PRIMARY KEY NOT NULL,
        display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
        official_name TEXT,
        short_name TEXT,
        city TEXT,
        country_id TEXT REFERENCES country (id) ON DELETE RESTRICT,
        founded_date TEXT CHECK (founded_date IS NULL
            OR founded_date GLOB '[0-9][0-9][0-9][0-9]'
            OR founded_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
            OR founded_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        notes TEXT,
        search_key TEXT NOT NULL DEFAULT '',
        sort_key TEXT NOT NULL DEFAULT '',
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE INDEX club_sort_order ON club (sort_key, id);

    CREATE TABLE team (
        id TEXT PRIMARY KEY NOT NULL,
        club_id TEXT NOT NULL REFERENCES club (id) ON DELETE RESTRICT,
        display_name TEXT NOT NULL CHECK (length(trim(display_name)) > 0),
        category TEXT NOT NULL CHECK (category IN ('senior', 'reserve', 'youth', 'other')),
        age_group TEXT,
        gender_category TEXT NOT NULL CHECK (gender_category IN ('mens', 'womens', 'mixed', 'unspecified')),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE INDEX team_by_club ON team (club_id);

    CREATE TABLE roster_membership (
        id TEXT PRIMARY KEY NOT NULL,
        player_id TEXT NOT NULL REFERENCES player (id) ON DELETE RESTRICT,
        team_id TEXT NOT NULL REFERENCES team (id) ON DELETE RESTRICT,
        start_date TEXT CHECK (start_date IS NULL
            OR start_date GLOB '[0-9][0-9][0-9][0-9]'
            OR start_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
            OR start_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        end_date TEXT CHECK (end_date IS NULL
            OR end_date GLOB '[0-9][0-9][0-9][0-9]'
            OR end_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'
            OR end_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        shirt_number INTEGER CHECK (shirt_number IS NULL OR shirt_number BETWEEN 1 AND 99),
        status TEXT NOT NULL CHECK (status IN ('current', 'former', 'uncertain')),
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (start_date IS NULL OR end_date IS NULL
            OR length(start_date) < 10 OR length(end_date) < 10
            OR start_date < end_date)
    );
    CREATE INDEX membership_by_team ON roster_membership (team_id);
    CREATE INDEX membership_by_player ON roster_membership (player_id);
    """

    private static func seedCountries(_ db: Database) throws {
        for country in IsoCountries.all {
            try db.execute(
                sql: "INSERT INTO country (id, iso_code, display_name) VALUES (?, ?, ?)",
                arguments: [DeterministicID.countryUUID(isoCode: country.code).uuidString, country.code, country.name]
            )
        }
    }
}
