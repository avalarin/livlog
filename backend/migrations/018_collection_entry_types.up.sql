-- Add allowed_entry_types column to collections (empty array = no restriction)
ALTER TABLE collections ADD COLUMN allowed_entry_types UUID[] NOT NULL DEFAULT '{}';

-- Rename "Music" entry type to "Album"
UPDATE entry_types SET name = 'Album' WHERE name = 'Music' AND user_id IS NULL;

-- Seed template collections with their allowed entry types
UPDATE collections
SET allowed_entry_types = ARRAY(
    SELECT id FROM entry_types WHERE name IN ('Movie', 'Show') AND user_id IS NULL
)
WHERE slug = 'movies' AND is_template = true;

UPDATE collections
SET allowed_entry_types = ARRAY(
    SELECT id FROM entry_types WHERE name = 'Book' AND user_id IS NULL
)
WHERE slug = 'books' AND is_template = true;

UPDATE collections
SET allowed_entry_types = ARRAY(
    SELECT id FROM entry_types WHERE name = 'Album' AND user_id IS NULL
)
WHERE slug = 'vinyl' AND is_template = true;

UPDATE collections
SET allowed_entry_types = ARRAY(
    SELECT id FROM entry_types WHERE name = 'Game' AND user_id IS NULL
)
WHERE slug = 'games' AND is_template = true;

UPDATE collections
SET allowed_entry_types = ARRAY(
    SELECT id FROM entry_types WHERE name = 'Other' AND user_id IS NULL
)
WHERE slug = 'places' AND is_template = true;
