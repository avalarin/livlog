-- Create AI search usage tracking table for rate limiting
CREATE TABLE IF NOT EXISTS ai_search_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    search_count INT NOT NULL DEFAULT 0,
    period_start TIMESTAMP NOT NULL DEFAULT NOW(),
    period_end TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Index for fast lookups by user_id
CREATE INDEX idx_ai_search_usage_user_id ON ai_search_usage(user_id);

-- Index for finding expired periods
CREATE INDEX idx_ai_search_usage_period_end ON ai_search_usage(period_end);
