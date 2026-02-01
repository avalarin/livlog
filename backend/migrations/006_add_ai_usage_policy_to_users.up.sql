-- Create enum type for AI usage policy
CREATE TYPE ai_usage_policy AS ENUM ('basic', 'pro', 'unlimited');

-- Add ai_usage_policy column to users table
ALTER TABLE users ADD COLUMN ai_usage_policy ai_usage_policy NOT NULL DEFAULT 'basic';

-- Create index for querying users by policy
CREATE INDEX idx_users_ai_usage_policy ON users(ai_usage_policy);
