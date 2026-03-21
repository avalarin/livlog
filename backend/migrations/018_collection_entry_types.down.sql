-- Rename "Album" back to "Music"
UPDATE entry_types SET name = 'Music' WHERE name = 'Album' AND user_id IS NULL;

-- Remove the allowed_entry_types column
ALTER TABLE collections DROP COLUMN IF EXISTS allowed_entry_types;
