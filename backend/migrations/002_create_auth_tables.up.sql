-- Create user_auth_providers table
CREATE TABLE user_auth_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_auth_provider UNIQUE (provider, provider_user_id)
);

-- Fast lookup by user
CREATE INDEX idx_auth_providers_user_id
    ON user_auth_providers(user_id);

-- Fast lookup for login
CREATE INDEX idx_auth_providers_lookup
    ON user_auth_providers(provider, provider_user_id);

-- Create user_tokens table
CREATE TABLE user_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(64) NOT NULL,
    device_info JSONB,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMP WITH TIME ZONE
);

-- Find tokens by user
CREATE INDEX idx_user_tokens_user_id
    ON user_tokens(user_id);

-- Token lookup (only active tokens)
CREATE INDEX idx_user_tokens_hash
    ON user_tokens(refresh_token_hash)
    WHERE revoked_at IS NULL;

-- Cleanup expired tokens
CREATE INDEX idx_user_tokens_cleanup
    ON user_tokens(expires_at)
    WHERE revoked_at IS NULL;
