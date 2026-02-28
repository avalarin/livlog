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
	ErrMCPNotFound = errors.New("mcp integration not found")
)

type MCPIntegration struct {
	ID         uuid.UUID `json:"id"`
	UserID     uuid.UUID `json:"user_id"`
	UniqueCode string    `json:"unique_code"`
	CreatedAt  time.Time `json:"created_at"`
}

type MCPRepository struct {
	db *pgxpool.Pool
}

func NewMCPRepository(db *pgxpool.Pool) *MCPRepository {
	return &MCPRepository{db: db}
}

// GetByUserID retrieves the MCP integration for a user.
func (r *MCPRepository) GetByUserID(ctx context.Context, userID uuid.UUID) (*MCPIntegration, error) {
	query := `
		SELECT id, user_id, unique_code, created_at
		FROM mcp_integrations
		WHERE user_id = $1
	`

	var integration MCPIntegration
	err := r.db.QueryRow(ctx, query, userID).Scan(
		&integration.ID,
		&integration.UserID,
		&integration.UniqueCode,
		&integration.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrMCPNotFound
		}
		return nil, fmt.Errorf("failed to get mcp integration: %w", err)
	}

	return &integration, nil
}

// GetByUniqueCode retrieves the MCP integration by unique code.
func (r *MCPRepository) GetByUniqueCode(ctx context.Context, uniqueCode string) (*MCPIntegration, error) {
	query := `
		SELECT id, user_id, unique_code, created_at
		FROM mcp_integrations
		WHERE unique_code = $1
	`

	var integration MCPIntegration
	err := r.db.QueryRow(ctx, query, uniqueCode).Scan(
		&integration.ID,
		&integration.UserID,
		&integration.UniqueCode,
		&integration.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrMCPNotFound
		}
		return nil, fmt.Errorf("failed to get mcp integration by code: %w", err)
	}

	return &integration, nil
}

// Upsert atomically creates or replaces the MCP integration for a user.
func (r *MCPRepository) Upsert(ctx context.Context, userID uuid.UUID, uniqueCode string) (*MCPIntegration, error) {
	query := `
		INSERT INTO mcp_integrations (user_id, unique_code)
		VALUES ($1, $2)
		ON CONFLICT (user_id) DO UPDATE SET unique_code = $2, created_at = NOW()
		RETURNING id, user_id, unique_code, created_at
	`

	var integration MCPIntegration
	err := r.db.QueryRow(ctx, query, userID, uniqueCode).Scan(
		&integration.ID,
		&integration.UserID,
		&integration.UniqueCode,
		&integration.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to upsert mcp integration: %w", err)
	}

	return &integration, nil
}

// DeleteByUserID deletes the MCP integration for a user.
func (r *MCPRepository) DeleteByUserID(ctx context.Context, userID uuid.UUID) error {
	query := `DELETE FROM mcp_integrations WHERE user_id = $1`

	result, err := r.db.Exec(ctx, query, userID)
	if err != nil {
		return fmt.Errorf("failed to delete mcp integration: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrMCPNotFound
	}

	return nil
}
