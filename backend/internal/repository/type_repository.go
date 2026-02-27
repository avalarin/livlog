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
	ErrTypeNotFound = errors.New("entry type not found")
)

type EntryType struct {
	ID        uuid.UUID  `json:"id"`
	UserID    *uuid.UUID `json:"user_id,omitempty"`
	Name      string     `json:"name"`
	Icon      string     `json:"icon"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
}

type TypeRepository struct {
	db *pgxpool.Pool
}

func NewTypeRepository(db *pgxpool.Pool) *TypeRepository {
	return &TypeRepository{db: db}
}

// GetAllTypes returns system types (user_id IS NULL) plus the given user's own types.
func (r *TypeRepository) GetAllTypes(
	ctx context.Context,
	userID uuid.UUID,
) ([]*EntryType, error) {
	query := `
		SELECT id, user_id, name, icon, created_at, updated_at
		FROM entry_types
		WHERE user_id IS NULL OR user_id = $1
		ORDER BY created_at ASC
	`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to query entry types: %w", err)
	}
	defer rows.Close()

	var types []*EntryType
	for rows.Next() {
		var t EntryType
		err := rows.Scan(
			&t.ID,
			&t.UserID,
			&t.Name,
			&t.Icon,
			&t.CreatedAt,
			&t.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan entry type: %w", err)
		}
		types = append(types, &t)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating entry types: %w", err)
	}

	return types, nil
}

// GetTypeByID retrieves a single entry type by ID.
func (r *TypeRepository) GetTypeByID(
	ctx context.Context,
	id uuid.UUID,
) (*EntryType, error) {
	query := `
		SELECT id, user_id, name, icon, created_at, updated_at
		FROM entry_types
		WHERE id = $1
	`

	var t EntryType
	err := r.db.QueryRow(ctx, query, id).Scan(
		&t.ID,
		&t.UserID,
		&t.Name,
		&t.Icon,
		&t.CreatedAt,
		&t.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrTypeNotFound
		}
		return nil, fmt.Errorf("failed to get entry type: %w", err)
	}

	return &t, nil
}

// CreateType creates a new user-owned entry type.
func (r *TypeRepository) CreateType(
	ctx context.Context,
	userID *uuid.UUID,
	name, icon string,
) (*EntryType, error) {
	query := `
		INSERT INTO entry_types (user_id, name, icon)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, name, icon, created_at, updated_at
	`

	var t EntryType
	err := r.db.QueryRow(ctx, query, userID, name, icon).Scan(
		&t.ID,
		&t.UserID,
		&t.Name,
		&t.Icon,
		&t.CreatedAt,
		&t.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create entry type: %w", err)
	}

	return &t, nil
}
