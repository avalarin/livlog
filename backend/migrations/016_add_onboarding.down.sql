-- Remove template entries and collections
DELETE FROM entries WHERE collection_id IN (SELECT id FROM collections WHERE is_template = true);
DELETE FROM collections WHERE is_template = true;

-- Remove template fields from collections
DROP INDEX IF EXISTS idx_collections_slug;
ALTER TABLE collections DROP COLUMN IF EXISTS description;
ALTER TABLE collections DROP COLUMN IF EXISTS slug;
ALTER TABLE collections DROP COLUMN IF EXISTS is_template;
ALTER TABLE collections ALTER COLUMN user_id SET NOT NULL;

-- Restore entries user_id NOT NULL
ALTER TABLE entries ALTER COLUMN user_id SET NOT NULL;

-- Remove onboarding_completed from users
ALTER TABLE users DROP COLUMN IF EXISTS onboarding_completed;
