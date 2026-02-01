-- Create verification_codes table for email authentication
CREATE TABLE verification_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    code_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE
);

-- Fast lookup by email for active (unused) codes
CREATE INDEX idx_verification_codes_email
    ON verification_codes(email)
    WHERE used_at IS NULL;

-- Cleanup expired codes efficiently
CREATE INDEX idx_verification_codes_cleanup
    ON verification_codes(expires_at)
    WHERE used_at IS NULL;

-- Fast verification lookup by code hash
CREATE INDEX idx_verification_codes_hash
    ON verification_codes(code_hash)
    WHERE used_at IS NULL;

-- Ensure only one active verification code per email
-- This prevents multiple concurrent codes for the same email
CREATE UNIQUE INDEX idx_verification_codes_one_per_email
    ON verification_codes(email)
    WHERE used_at IS NULL;
