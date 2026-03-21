-- Catalog of available statistic types
CREATE TABLE statistic_definitions (
    id VARCHAR(50) PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    description VARCHAR(255) NOT NULL DEFAULT '',
    stat_type VARCHAR(20) NOT NULL DEFAULT 'builtin',  -- 'builtin' or 'field_aggregation'
    field_key VARCHAR(50),        -- for field_aggregation: which additional_field key
    aggregation VARCHAR(20),      -- 'count_top', 'min', 'max', 'avg', 'count_distinct'
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Which stats each collection shows + order
CREATE TABLE collection_statistic_configs (
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    statistic_id VARCHAR(50) NOT NULL REFERENCES statistic_definitions(id) ON DELETE CASCADE,
    position INT NOT NULL DEFAULT 0,
    PRIMARY KEY (collection_id, statistic_id)
);

-- Cached computed values (replaces collection_statistics)
CREATE TABLE collection_statistic_values (
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    statistic_id VARCHAR(50) NOT NULL REFERENCES statistic_definitions(id) ON DELETE CASCADE,
    display_value VARCHAR(255) NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (collection_id, statistic_id)
);

-- Seed built-in stat definitions
INSERT INTO statistic_definitions (id, title, description, stat_type, is_default) VALUES
    ('total_entries', 'Total', 'Total number of entries', 'builtin', true),
    ('backlog', 'Backlog', 'Entries not yet rated', 'builtin', true),
    ('last_entry', 'Last Entry', 'Date of the most recent entry', 'builtin', true);

-- Seed field-based stat definitions
INSERT INTO statistic_definitions (id, title, description, stat_type, field_key, aggregation, is_default) VALUES
    ('top_genre', 'Top Genre', 'Most frequent genre', 'field_aggregation', 'Genre', 'count_top', false),
    ('min_year', 'Earliest Year', 'Earliest year in collection', 'field_aggregation', 'Year', 'min', false),
    ('max_year', 'Latest Year', 'Latest year in collection', 'field_aggregation', 'Year', 'max', false),
    ('top_author', 'Top Author', 'Most frequent author', 'field_aggregation', 'Author', 'count_top', false),
    ('top_platform', 'Top Platform', 'Most frequent platform', 'field_aggregation', 'Platform', 'count_top', false),
    ('unique_genres', 'Unique Genres', 'Number of distinct genres', 'field_aggregation', 'Genre', 'count_distinct', false),
    ('avg_score', 'Avg Score', 'Average rating (excluding unrated)', 'builtin', NULL, NULL, false),
    ('rated_pct', 'Rated %', 'Percentage of rated entries', 'builtin', NULL, NULL, false);

-- Migrate existing collection_statistics data to new format
-- For each collection that has data in collection_statistics, create default configs
INSERT INTO collection_statistic_configs (collection_id, statistic_id, position)
SELECT cs.collection_id, sd.id,
    CASE sd.id
        WHEN 'total_entries' THEN 0
        WHEN 'backlog' THEN 1
        WHEN 'last_entry' THEN 2
    END
FROM collection_statistics cs
CROSS JOIN statistic_definitions sd
WHERE sd.is_default = true
ON CONFLICT DO NOTHING;

-- Migrate cached values
INSERT INTO collection_statistic_values (collection_id, statistic_id, display_value, updated_at)
SELECT collection_id, 'total_entries', total_entries::text, updated_at FROM collection_statistics
UNION ALL
SELECT collection_id, 'backlog', backlog_entries::text, updated_at FROM collection_statistics
UNION ALL
SELECT collection_id, 'last_entry', COALESCE(to_char(last_entry_date, 'Mon DD, YYYY'), '—'), updated_at FROM collection_statistics;

-- Drop old table
DROP TABLE collection_statistics;
