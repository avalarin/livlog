package repository

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
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

// GetLastAttemptTime returns the created_at of the most recent attempt for this email
// within the given window. Returns nil if no recent attempt exists.
func (r *VerificationAttemptRepository) GetLastAttemptTime(ctx context.Context, email string, window time.Duration) (*time.Time, error) {
	since := time.Now().Add(-window)

	var t time.Time
	err := r.pool.QueryRow(ctx,
		`SELECT created_at FROM verification_attempts
		 WHERE email = $1 AND created_at > $2
		 ORDER BY created_at DESC
		 LIMIT 1`,
		email, since,
	).Scan(&t)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &t, nil
}

// CountDistinctEmailsByDevice counts the number of distinct emails attempted
// from the given device within the window.
func (r *VerificationAttemptRepository) CountDistinctEmailsByDevice(ctx context.Context, deviceID string, window time.Duration) (int, error) {
	since := time.Now().Add(-window)

	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(DISTINCT email) FROM verification_attempts
		 WHERE device_id = $1 AND created_at > $2`,
		deviceID, since,
	).Scan(&count)
	return count, err
}

// GetOldestAttemptTimeByDevice returns the created_at of the oldest attempt
// from this device within the given window. Returns nil if no attempt exists.
func (r *VerificationAttemptRepository) GetOldestAttemptTimeByDevice(ctx context.Context, deviceID string, window time.Duration) (*time.Time, error) {
	since := time.Now().Add(-window)

	var t time.Time
	err := r.pool.QueryRow(ctx,
		`SELECT created_at FROM verification_attempts
		 WHERE device_id = $1 AND created_at > $2
		 ORDER BY created_at ASC
		 LIMIT 1`,
		deviceID, since,
	).Scan(&t)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &t, nil
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
