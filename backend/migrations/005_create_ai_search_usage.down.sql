-- Drop AI search usage table
DROP INDEX IF EXISTS idx_ai_search_usage_period_end;
DROP INDEX IF EXISTS idx_ai_search_usage_user_id;
DROP TABLE IF EXISTS ai_search_usage;
