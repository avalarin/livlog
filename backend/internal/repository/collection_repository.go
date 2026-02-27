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
	ErrCollectionNotFound = errors.New("collection not found")
)

type Collection struct {
	ID         uuid.UUID `json:"id"`
	UserID     uuid.UUID `json:"user_id"`
	Name       string    `json:"name"`
	Icon       string    `json:"icon"`
	EntryCount int       `json:"entry_count"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type CollectionRepository struct {
	db *pgxpool.Pool
}

func NewCollectionRepository(db *pgxpool.Pool) *CollectionRepository {
	return &CollectionRepository{db: db}
}

// CreateCollection creates a new collection
func (r *CollectionRepository) CreateCollection(
	ctx context.Context,
	userID uuid.UUID,
	name, icon string,
) (*Collection, error) {
	query := `
		INSERT INTO collections (user_id, name, icon)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, name, icon, 0 AS entry_count, created_at, updated_at
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, userID, name, icon).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.EntryCount,
		&collection.CreatedAt,
		&collection.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create collection: %w", err)
	}

	return &collection, nil
}

// GetCollectionsByUserID retrieves all collections for a user with entry counts.
func (r *CollectionRepository) GetCollectionsByUserID(
	ctx context.Context,
	userID uuid.UUID,
) ([]*Collection, error) {
	query := `
		SELECT c.id, c.user_id, c.name, c.icon, COUNT(e.id) AS entry_count, c.created_at, c.updated_at
		FROM collections c
		LEFT JOIN entries e ON e.collection_id = c.id
		WHERE c.user_id = $1
		GROUP BY c.id
		ORDER BY c.created_at ASC
	`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to query collections: %w", err)
	}
	defer rows.Close()

	var collections []*Collection
	for rows.Next() {
		var collection Collection
		err := rows.Scan(
			&collection.ID,
			&collection.UserID,
			&collection.Name,
			&collection.Icon,
			&collection.EntryCount,
			&collection.CreatedAt,
			&collection.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan collection: %w", err)
		}
		collections = append(collections, &collection)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating collections: %w", err)
	}

	return collections, nil
}

// GetCollectionByID retrieves a single collection by ID with entry count.
func (r *CollectionRepository) GetCollectionByID(
	ctx context.Context,
	id uuid.UUID,
) (*Collection, error) {
	query := `
		SELECT c.id, c.user_id, c.name, c.icon, COUNT(e.id) AS entry_count, c.created_at, c.updated_at
		FROM collections c
		LEFT JOIN entries e ON e.collection_id = c.id
		WHERE c.id = $1
		GROUP BY c.id
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, id).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.EntryCount,
		&collection.CreatedAt,
		&collection.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCollectionNotFound
		}
		return nil, fmt.Errorf("failed to get collection: %w", err)
	}

	return &collection, nil
}

// UpdateCollection updates a collection's name and/or icon
func (r *CollectionRepository) UpdateCollection(
	ctx context.Context,
	id uuid.UUID,
	name, icon string,
) (*Collection, error) {
	query := `
		UPDATE collections
		SET name = $2, icon = $3, updated_at = NOW()
		WHERE id = $1
		RETURNING id, user_id, name, icon, 0 AS entry_count, created_at, updated_at
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, id, name, icon).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.EntryCount,
		&collection.CreatedAt,
		&collection.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCollectionNotFound
		}
		return nil, fmt.Errorf("failed to update collection: %w", err)
	}

	return &collection, nil
}

// DeleteCollection deletes a collection (cascade deletes entries)
func (r *CollectionRepository) DeleteCollection(
	ctx context.Context,
	id uuid.UUID,
) error {
	query := `DELETE FROM collections WHERE id = $1`

	result, err := r.db.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to delete collection: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrCollectionNotFound
	}

	return nil
}

// CreateDefaultCollections creates the default "My List" collection for a new user.
func (r *CollectionRepository) CreateDefaultCollections(
	ctx context.Context,
	userID uuid.UUID,
) ([]*Collection, error) {
	query := `
		INSERT INTO collections (user_id, name, icon)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, name, icon, 0 AS entry_count, created_at, updated_at
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, userID, "My List", "📋").Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.EntryCount,
		&collection.CreatedAt,
		&collection.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create default collection: %w", err)
	}

	return []*Collection{&collection}, nil
}

// HasCollections checks if user has any collections
func (r *CollectionRepository) HasCollections(
	ctx context.Context,
	userID uuid.UUID,
) (bool, error) {
	query := `SELECT EXISTS(SELECT 1 FROM collections WHERE user_id = $1)`

	var exists bool
	err := r.db.QueryRow(ctx, query, userID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check collections: %w", err)
	}

	return exists, nil
}
