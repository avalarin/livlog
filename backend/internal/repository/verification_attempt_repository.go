package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type VerificationAttemptRepository struct {
	pool *pgxpool.Pool
}

func NewVerificationAttemptRepository(pool *pgxpool.Pool) *VerificationAttemptRepository {
	return &VerificationAttemptRepository{pool: pool}
}

// RecordAttempt records a verification code send attempt
func (r *VerificationAttemptRepository) RecordAttempt(ctx context.Context, email, deviceID, ipAddress string) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO verification_attempts (email, device_id, ip_address) VALUES ($1, $2, $3)`,
		email, nullIfEmpty(deviceID), nullIfEmpty(ipAddress),
	)
	return err
}

// HasRecentAttempt checks if there's been an attempt within the cooldown period
// from the same email, device ID, or IP address
func (r *VerificationAttemptRepository) HasRecentAttempt(ctx context.Context, email, deviceID, ipAddress string, cooldown time.Duration) (bool, error) {
	since := time.Now().Add(-cooldown)

	query := `SELECT EXISTS(
        SELECT 1 FROM verification_attempts
        WHERE created_at > $1
        AND (email = $2 OR ($3::TEXT IS NOT NULL AND device_id = $3) OR ($4::TEXT IS NOT NULL AND ip_address = $4))
    )`

	var exists bool
	err := r.pool.QueryRow(ctx, query, since, email, nullIfEmpty(deviceID), nullIfEmpty(ipAddress)).Scan(&exists)
	return exists, err
}

// CountRecentAttempts counts attempts for a given email within a time window
func (r *VerificationAttemptRepository) CountRecentAttempts(ctx context.Context, email string, window time.Duration) (int, error) {
	since := time.Now().Add(-window)

	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM verification_attempts WHERE email = $1 AND created_at > $2`,
		email, since,
	).Scan(&count)
	return count, err
}

// CleanupOldAttempts removes attempts older than the given duration
func (r *VerificationAttemptRepository) CleanupOldAttempts(ctx context.Context, olderThan time.Duration) (int64, error) {
	cutoff := time.Now().Add(-olderThan)
	result, err := r.pool.Exec(ctx,
		`DELETE FROM verification_attempts WHERE created_at < $1`,
		cutoff,
	)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
