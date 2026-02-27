ALTER TABLE entries DROP CONSTRAINT IF EXISTS entries_collection_id_fkey;
ALTER TABLE entries ADD CONSTRAINT entries_collection_id_fkey
    FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE SET NULL;
ALTER TABLE entries DROP COLUMN IF EXISTS type_id;
DROP TABLE IF EXISTS entry_types;
