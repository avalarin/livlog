-- Create users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255),
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    display_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Unique email only for active users
CREATE UNIQUE INDEX idx_users_email
    ON users(email)
    WHERE email IS NOT NULL AND deleted_at IS NULL;

-- For finding soft-deleted users (cleanup jobs)
CREATE INDEX idx_users_deleted_at
    ON users(deleted_at)
    WHERE deleted_at IS NOT NULL;
