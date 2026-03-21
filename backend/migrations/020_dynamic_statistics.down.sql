-- Recreate old table
CREATE TABLE collection_statistics (
    collection_id UUID PRIMARY KEY REFERENCES collections(id) ON DELETE CASCADE,
    total_entries INT NOT NULL DEFAULT 0,
    backlog_entries INT NOT NULL DEFAULT 0,
    last_entry_date DATE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
DROP TABLE collection_statistic_values;
DROP TABLE collection_statistic_configs;
DROP TABLE statistic_definitions;
