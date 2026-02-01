package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrRateLimitExceeded = errors.New("rate limit exceeded")
)

type AISearchUsage struct {
	ID          uuid.UUID `json:"id"`
	UserID      uuid.UUID `json:"user_id"`
	SearchCount int       `json:"search_count"`
	PeriodStart time.Time `json:"period_start"`
	PeriodEnd   time.Time `json:"period_end"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type AISearchUsageRepository struct {
	db *pgxpool.Pool
}

func NewAISearchUsageRepository(db *pgxpool.Pool) *AISearchUsageRepository {
	return &AISearchUsageRepository{db: db}
}

// CheckAndIncrementUsage checks if the user can make a search request and increments the counter
// Returns ErrRateLimitExceeded if the limit is exceeded
// Uses SELECT FOR UPDATE to prevent race conditions in multi-instance deployments
func (r *AISearchUsageRepository) CheckAndIncrementUsage(
	ctx context.Context,
	userID uuid.UUID,
	limit int,
	period time.Duration,
) error {
	// Start a transaction
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	now := time.Now()
	periodEnd := now.Add(period)

	// Get current usage with row lock
	query := `
		SELECT id, user_id, search_count, period_start, period_end, created_at, updated_at
		FROM ai_search_usage
		WHERE user_id = $1
		FOR UPDATE
	`

	var usage AISearchUsage
	err = tx.QueryRow(ctx, query, userID).Scan(
		&usage.ID,
		&usage.UserID,
		&usage.SearchCount,
		&usage.PeriodStart,
		&usage.PeriodEnd,
		&usage.CreatedAt,
		&usage.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		// First time user - create new usage record
		insertQuery := `
			INSERT INTO ai_search_usage (user_id, search_count, period_start, period_end)
			VALUES ($1, 1, $2, $3)
			RETURNING id, user_id, search_count, period_start, period_end, created_at, updated_at
		`

		err = tx.QueryRow(ctx, insertQuery, userID, now, periodEnd).Scan(
			&usage.ID,
			&usage.UserID,
			&usage.SearchCount,
			&usage.PeriodStart,
			&usage.PeriodEnd,
			&usage.CreatedAt,
			&usage.UpdatedAt,
		)
		if err != nil {
			return fmt.Errorf("failed to create usage record: %w", err)
		}

		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("failed to commit transaction: %w", err)
		}
		return nil
	} else if err != nil {
		return fmt.Errorf("failed to get usage: %w", err)
	}

	// Check if period has expired
	if now.After(usage.PeriodEnd) {
		// Reset the period
		updateQuery := `
			UPDATE ai_search_usage
			SET search_count = 1, period_start = $1, period_end = $2, updated_at = $1
			WHERE user_id = $3
		`

		_, err = tx.Exec(ctx, updateQuery, now, periodEnd, userID)
		if err != nil {
			return fmt.Errorf("failed to reset usage period: %w", err)
		}

		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("failed to commit transaction: %w", err)
		}
		return nil
	}

	// Check if limit is exceeded
	if usage.SearchCount >= limit {
		return ErrRateLimitExceeded
	}

	// Increment the counter
	updateQuery := `
		UPDATE ai_search_usage
		SET search_count = search_count + 1, updated_at = $1
		WHERE user_id = $2
	`

	_, err = tx.Exec(ctx, updateQuery, now, userID)
	if err != nil {
		return fmt.Errorf("failed to increment usage: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// GetUsage returns the current usage for a user
func (r *AISearchUsageRepository) GetUsage(
	ctx context.Context,
	userID uuid.UUID,
) (*AISearchUsage, error) {
	query := `
		SELECT id, user_id, search_count, period_start, period_end, created_at, updated_at
		FROM ai_search_usage
		WHERE user_id = $1
	`

	var usage AISearchUsage
	err := r.db.QueryRow(ctx, query, userID).Scan(
		&usage.ID,
		&usage.UserID,
		&usage.SearchCount,
		&usage.PeriodStart,
		&usage.PeriodEnd,
		&usage.CreatedAt,
		&usage.UpdatedAt,
	)

	if err == pgx.ErrNoRows {
		return nil, nil
	} else if err != nil {
		return nil, fmt.Errorf("failed to get usage: %w", err)
	}

	return &usage, nil
}
