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
	ErrTagNotFound = errors.New("tag not found")
)

// Tag represents a tag that can be applied to entries.
// System tags have a nil UserID.
type Tag struct {
	ID        uuid.UUID  `json:"id"`
	Name      string     `json:"name"`
	UserID    *uuid.UUID `json:"user_id,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

type TagRepository struct {
	db *pgxpool.Pool
}

func NewTagRepository(db *pgxpool.Pool) *TagRepository {
	return &TagRepository{db: db}
}

// GetSystemTagByName finds a tag where user_id IS NULL (system tag).
func (r *TagRepository) GetSystemTagByName(ctx context.Context, name string) (*Tag, error) {
	query := `
		SELECT id, name, user_id, created_at
		FROM tags
		WHERE name = $1 AND user_id IS NULL
	`

	var tag Tag
	err := r.db.QueryRow(ctx, query, name).Scan(
		&tag.ID,
		&tag.Name,
		&tag.UserID,
		&tag.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrTagNotFound
		}
		return nil, fmt.Errorf("failed to get system tag %q: %w", name, err)
	}

	return &tag, nil
}

// AddTagToEntry inserts a row into entry_tags. Conflicts are silently ignored.
func (r *TagRepository) AddTagToEntry(ctx context.Context, entryID, tagID uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		`INSERT INTO entry_tags (entry_id, tag_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		entryID, tagID,
	)
	if err != nil {
		return fmt.Errorf("failed to add tag %s to entry %s: %w", tagID, entryID, err)
	}
	return nil
}
