-- Up
CREATE TABLE verification_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    device_id TEXT,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_verification_attempts_email_created ON verification_attempts(email, created_at);
CREATE INDEX idx_verification_attempts_device_id_created ON verification_attempts(device_id, created_at);
CREATE INDEX idx_verification_attempts_ip_created ON verification_attempts(ip_address, created_at);
