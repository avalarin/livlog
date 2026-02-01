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
	ID        uuid.UUID `json:"id"`
	UserID    uuid.UUID `json:"user_id"`
	Name      string    `json:"name"`
	Icon      string    `json:"icon"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
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
		RETURNING id, user_id, name, icon, created_at, updated_at
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, userID, name, icon).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.CreatedAt,
		&collection.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create collection: %w", err)
	}

	return &collection, nil
}

// GetCollectionsByUserID retrieves all collections for a user
func (r *CollectionRepository) GetCollectionsByUserID(
	ctx context.Context,
	userID uuid.UUID,
) ([]*Collection, error) {
	query := `
		SELECT id, user_id, name, icon, created_at, updated_at
		FROM collections
		WHERE user_id = $1
		ORDER BY created_at ASC
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

// GetCollectionByID retrieves a single collection by ID
func (r *CollectionRepository) GetCollectionByID(
	ctx context.Context,
	id uuid.UUID,
) (*Collection, error) {
	query := `
		SELECT id, user_id, name, icon, created_at, updated_at
		FROM collections
		WHERE id = $1
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, id).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
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
		RETURNING id, user_id, name, icon, created_at, updated_at
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, id, name, icon).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
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

// CreateDefaultCollections creates default collections for a new user
func (r *CollectionRepository) CreateDefaultCollections(
	ctx context.Context,
	userID uuid.UUID,
) ([]*Collection, error) {
	defaultCollections := []struct {
		Name string
		Icon string
	}{
		{"Movies", "🎬"},
		{"Books", "📚"},
		{"Games", "🎮"},
	}

	// Start transaction
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var collections []*Collection

	query := `
		INSERT INTO collections (user_id, name, icon)
		VALUES ($1, $2, $3)
		RETURNING id, user_id, name, icon, created_at, updated_at
	`

	for _, dc := range defaultCollections {
		var collection Collection
		err := tx.QueryRow(ctx, query, userID, dc.Name, dc.Icon).Scan(
			&collection.ID,
			&collection.UserID,
			&collection.Name,
			&collection.Icon,
			&collection.CreatedAt,
			&collection.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to create default collection %s: %w", dc.Name, err)
		}
		collections = append(collections, &collection)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return collections, nil
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
