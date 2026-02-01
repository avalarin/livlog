-- Drop index
DROP INDEX IF EXISTS idx_users_ai_usage_policy;

-- Remove column
ALTER TABLE users DROP COLUMN IF EXISTS ai_usage_policy;

-- Drop enum type
DROP TYPE IF EXISTS ai_usage_policy;
