package repository

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrEntryNotFound      = errors.New("entry not found")
	ErrSeedImageNotFound  = errors.New("seed image not found")
)

type Entry struct {
	ID               uuid.UUID         `json:"id"`
	CollectionID     *uuid.UUID        `json:"collection_id,omitempty"`
	TypeID           *uuid.UUID        `json:"type_id,omitempty"`
	UserID           uuid.UUID         `json:"user_id"`
	Title            string            `json:"title"`
	Description      string            `json:"description"`
	Score            int               `json:"score"`
	Date             time.Time         `json:"date"`
	AdditionalFields map[string]string `json:"additional_fields"`
	CreatedAt        time.Time         `json:"created_at"`
	UpdatedAt        time.Time         `json:"updated_at"`
}

type EntryImage struct {
	ID        uuid.UUID `json:"id"`
	EntryID   uuid.UUID `json:"entry_id"`
	ImageData []byte    `json:"-"`
	IsCover   bool      `json:"is_cover"`
	Position  int       `json:"position"`
	CreatedAt time.Time `json:"created_at"`
}

type ImageMeta struct {
	ID       uuid.UUID `json:"id"`
	IsCover  bool      `json:"is_cover"`
	Position int       `json:"position"`
}

type EntryRepository struct {
	db *pgxpool.Pool
}

func NewEntryRepository(db *pgxpool.Pool) *EntryRepository {
	return &EntryRepository{db: db}
}

// CreateEntry creates a new entry
func (r *EntryRepository) CreateEntry(
	ctx context.Context,
	userID uuid.UUID,
	collectionID *uuid.UUID,
	typeID *uuid.UUID,
	title, description string,
	score int,
	date time.Time,
	additionalFields map[string]string,
) (*Entry, error) {
	additionalFieldsJSON, err := json.Marshal(additionalFields)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal additional fields: %w", err)
	}

	query := `
		INSERT INTO entries (user_id, collection_id, type_id, title, description, score, date, additional_fields)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id, collection_id, type_id, user_id, title, description, score, date, additional_fields, created_at, updated_at
	`

	var entry Entry
	var additionalFieldsStr string
	err = r.db.QueryRow(ctx, query, userID, collectionID, typeID, title, description, score, date, additionalFieldsJSON).Scan(
		&entry.ID,
		&entry.CollectionID,
		&entry.TypeID,
		&entry.UserID,
		&entry.Title,
		&entry.Description,
		&entry.Score,
		&entry.Date,
		&additionalFieldsStr,
		&entry.CreatedAt,
		&entry.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create entry: %w", err)
	}

	if err := json.Unmarshal([]byte(additionalFieldsStr), &entry.AdditionalFields); err != nil {
		return nil, fmt.Errorf("failed to unmarshal additional fields: %w", err)
	}

	return &entry, nil
}

// GetEntriesByUserID retrieves entries for a user with optional filters
func (r *EntryRepository) GetEntriesByUserID(
	ctx context.Context,
	userID uuid.UUID,
	collectionID *uuid.UUID,
	limit, offset int,
) ([]*Entry, error) {
	query := `
		SELECT id, collection_id, type_id, user_id, title, description, score, date, additional_fields, created_at, updated_at
		FROM entries
		WHERE user_id = $1
		AND ($2::uuid IS NULL OR collection_id = $2)
		ORDER BY created_at DESC
		LIMIT $3 OFFSET $4
	`

	rows, err := r.db.Query(ctx, query, userID, collectionID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to query entries: %w", err)
	}
	defer rows.Close()

	var entries []*Entry
	for rows.Next() {
		var entry Entry
		var additionalFieldsStr string
		err := rows.Scan(
			&entry.ID,
			&entry.CollectionID,
			&entry.TypeID,
			&entry.UserID,
			&entry.Title,
			&entry.Description,
			&entry.Score,
			&entry.Date,
			&additionalFieldsStr,
			&entry.CreatedAt,
			&entry.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan entry: %w", err)
		}

		if err := json.Unmarshal([]byte(additionalFieldsStr), &entry.AdditionalFields); err != nil {
			return nil, fmt.Errorf("failed to unmarshal additional fields: %w", err)
		}

		entries = append(entries, &entry)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating entries: %w", err)
	}

	return entries, nil
}

// GetEntryByID retrieves a single entry by ID
func (r *EntryRepository) GetEntryByID(
	ctx context.Context,
	id uuid.UUID,
) (*Entry, error) {
	query := `
		SELECT id, collection_id, type_id, user_id, title, description, score, date, additional_fields, created_at, updated_at
		FROM entries
		WHERE id = $1
	`

	var entry Entry
	var additionalFieldsStr string
	err := r.db.QueryRow(ctx, query, id).Scan(
		&entry.ID,
		&entry.CollectionID,
		&entry.TypeID,
		&entry.UserID,
		&entry.Title,
		&entry.Description,
		&entry.Score,
		&entry.Date,
		&additionalFieldsStr,
		&entry.CreatedAt,
		&entry.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrEntryNotFound
		}
		return nil, fmt.Errorf("failed to get entry: %w", err)
	}

	if err := json.Unmarshal([]byte(additionalFieldsStr), &entry.AdditionalFields); err != nil {
		return nil, fmt.Errorf("failed to unmarshal additional fields: %w", err)
	}

	return &entry, nil
}

// UpdateEntry updates an entry
func (r *EntryRepository) UpdateEntry(
	ctx context.Context,
	id uuid.UUID,
	collectionID *uuid.UUID,
	typeID *uuid.UUID,
	title, description string,
	score int,
	date time.Time,
	additionalFields map[string]string,
) (*Entry, error) {
	additionalFieldsJSON, err := json.Marshal(additionalFields)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal additional fields: %w", err)
	}

	query := `
		UPDATE entries
		SET collection_id = $2, type_id = $3, title = $4, description = $5, score = $6, date = $7, additional_fields = $8, updated_at = NOW()
		WHERE id = $1
		RETURNING id, collection_id, type_id, user_id, title, description, score, date, additional_fields, created_at, updated_at
	`

	var entry Entry
	var additionalFieldsStr string
	err = r.db.QueryRow(ctx, query, id, collectionID, typeID, title, description, score, date, additionalFieldsJSON).Scan(
		&entry.ID,
		&entry.CollectionID,
		&entry.TypeID,
		&entry.UserID,
		&entry.Title,
		&entry.Description,
		&entry.Score,
		&entry.Date,
		&additionalFieldsStr,
		&entry.CreatedAt,
		&entry.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrEntryNotFound
		}
		return nil, fmt.Errorf("failed to update entry: %w", err)
	}

	if err := json.Unmarshal([]byte(additionalFieldsStr), &entry.AdditionalFields); err != nil {
		return nil, fmt.Errorf("failed to unmarshal additional fields: %w", err)
	}

	return &entry, nil
}

// DeleteEntry deletes an entry
func (r *EntryRepository) DeleteEntry(
	ctx context.Context,
	id uuid.UUID,
) error {
	query := `DELETE FROM entries WHERE id = $1`

	result, err := r.db.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to delete entry: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrEntryNotFound
	}

	return nil
}

// SaveEntryImages saves images for an entry (replaces existing)
func (r *EntryRepository) SaveEntryImages(
	ctx context.Context,
	entryID uuid.UUID,
	images []EntryImage,
) error {
	// Start transaction
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Delete existing images
	deleteQuery := `DELETE FROM entry_images WHERE entry_id = $1`
	_, err = tx.Exec(ctx, deleteQuery, entryID)
	if err != nil {
		return fmt.Errorf("failed to delete existing images: %w", err)
	}

	// Insert new images
	if len(images) > 0 {
		insertQuery := `
			INSERT INTO entry_images (entry_id, image_data, is_cover, position)
			VALUES ($1, $2, $3, $4)
		`
		for _, img := range images {
			_, err = tx.Exec(ctx, insertQuery, entryID, img.ImageData, img.IsCover, img.Position)
			if err != nil {
				return fmt.Errorf("failed to insert image: %w", err)
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

// GetEntryImages retrieves images for an entry
func (r *EntryRepository) GetEntryImages(
	ctx context.Context,
	entryID uuid.UUID,
) ([]EntryImage, error) {
	query := `
		SELECT id, entry_id, image_data, is_cover, position, created_at
		FROM entry_images
		WHERE entry_id = $1
		ORDER BY position ASC
	`

	rows, err := r.db.Query(ctx, query, entryID)
	if err != nil {
		return nil, fmt.Errorf("failed to query images: %w", err)
	}
	defer rows.Close()

	var images []EntryImage
	for rows.Next() {
		var img EntryImage
		err := rows.Scan(
			&img.ID,
			&img.EntryID,
			&img.ImageData,
			&img.IsCover,
			&img.Position,
			&img.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan image: %w", err)
		}
		images = append(images, img)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating images: %w", err)
	}

	return images, nil
}

// GetEntryImageMetas returns image metadata for an entry, ordered by position
func (r *EntryRepository) GetEntryImageMetas(
	ctx context.Context,
	entryID uuid.UUID,
) ([]ImageMeta, error) {
	query := `
		SELECT id, is_cover, position FROM entry_images
		WHERE entry_id = $1
		ORDER BY position ASC
	`

	rows, err := r.db.Query(ctx, query, entryID)
	if err != nil {
		return nil, fmt.Errorf("failed to query image metas: %w", err)
	}
	defer rows.Close()

	var metas []ImageMeta
	for rows.Next() {
		var m ImageMeta
		if err := rows.Scan(&m.ID, &m.IsCover, &m.Position); err != nil {
			return nil, fmt.Errorf("failed to scan image meta: %w", err)
		}
		metas = append(metas, m)
	}

	return metas, rows.Err()
}

// GetImageByID retrieves a single image by its ID
func (r *EntryRepository) GetImageByID(
	ctx context.Context,
	imageID uuid.UUID,
) (*EntryImage, error) {
	query := `
		SELECT id, entry_id, image_data, is_cover, position, created_at
		FROM entry_images
		WHERE id = $1
	`

	var img EntryImage
	err := r.db.QueryRow(ctx, query, imageID).Scan(
		&img.ID,
		&img.EntryID,
		&img.ImageData,
		&img.IsCover,
		&img.Position,
		&img.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, fmt.Errorf("image not found")
		}
		return nil, fmt.Errorf("failed to get image: %w", err)
	}

	return &img, nil
}

// GetImageMetasByEntryIDs returns a map of entry ID -> image metadata for multiple entries
func (r *EntryRepository) GetImageMetasByEntryIDs(
	ctx context.Context,
	entryIDs []uuid.UUID,
) (map[uuid.UUID][]ImageMeta, error) {
	if len(entryIDs) == 0 {
		return make(map[uuid.UUID][]ImageMeta), nil
	}

	query := `
		SELECT entry_id, id, is_cover, position FROM entry_images
		WHERE entry_id = ANY($1)
		ORDER BY entry_id, position ASC
	`

	rows, err := r.db.Query(ctx, query, entryIDs)
	if err != nil {
		return nil, fmt.Errorf("failed to query image metas: %w", err)
	}
	defer rows.Close()

	result := make(map[uuid.UUID][]ImageMeta)
	for rows.Next() {
		var entryID uuid.UUID
		var m ImageMeta
		if err := rows.Scan(&entryID, &m.ID, &m.IsCover, &m.Position); err != nil {
			return nil, fmt.Errorf("failed to scan: %w", err)
		}
		result[entryID] = append(result[entryID], m)
	}

	return result, rows.Err()
}

// SearchEntries searches entries by title or description
func (r *EntryRepository) SearchEntries(
	ctx context.Context,
	userID uuid.UUID,
	searchQuery string,
	limit, offset int,
) ([]*Entry, error) {
	query := `
		SELECT id, collection_id, type_id, user_id, title, description, score, date, additional_fields, created_at, updated_at
		FROM entries
		WHERE user_id = $1
		AND (title ILIKE $2 OR description ILIKE $2)
		ORDER BY created_at DESC
		LIMIT $3 OFFSET $4
	`

	searchPattern := "%" + searchQuery + "%"
	rows, err := r.db.Query(ctx, query, userID, searchPattern, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to search entries: %w", err)
	}
	defer rows.Close()

	var entries []*Entry
	for rows.Next() {
		var entry Entry
		var additionalFieldsStr string
		err := rows.Scan(
			&entry.ID,
			&entry.CollectionID,
			&entry.TypeID,
			&entry.UserID,
			&entry.Title,
			&entry.Description,
			&entry.Score,
			&entry.Date,
			&additionalFieldsStr,
			&entry.CreatedAt,
			&entry.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan entry: %w", err)
		}

		if err := json.Unmarshal([]byte(additionalFieldsStr), &entry.AdditionalFields); err != nil {
			return nil, fmt.Errorf("failed to unmarshal additional fields: %w", err)
		}

		entries = append(entries, &entry)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating entries: %w", err)
	}

	return entries, nil
}

// GetSeedImageByID retrieves a seed image by its fixed UUID (no user ownership check).
func (r *EntryRepository) GetSeedImageByID(ctx context.Context, imageID uuid.UUID) (*EntryImage, error) {
	var img EntryImage
	err := r.db.QueryRow(ctx,
		`SELECT id, image_data FROM seed_images WHERE id = $1`,
		imageID,
	).Scan(&img.ID, &img.ImageData)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSeedImageNotFound
		}
		return nil, fmt.Errorf("failed to get seed image: %w", err)
	}
	img.IsCover = true
	img.Position = 0
	return &img, nil
}

// UpsertSeedImages inserts seed images with fixed UUIDs, ignoring conflicts.
func (r *EntryRepository) UpsertSeedImages(ctx context.Context, images map[uuid.UUID][]byte) error {
	for id, data := range images {
		_, err := r.db.Exec(ctx,
			`INSERT INTO seed_images (id, image_data) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING`,
			id, data,
		)
		if err != nil {
			return fmt.Errorf("failed to upsert seed image %s: %w", id, err)
		}
	}
	return nil
}

// CopySeedImagesToEntry copies seed images into entry_images for a specific entry.
func (r *EntryRepository) CopySeedImagesToEntry(ctx context.Context, entryID uuid.UUID, seedImageIDs []uuid.UUID) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	for i, seedID := range seedImageIDs {
		var data []byte
		err := tx.QueryRow(ctx, `SELECT image_data FROM seed_images WHERE id = $1`, seedID).Scan(&data)
		if err != nil {
			return fmt.Errorf("seed image %s not found: %w", seedID, err)
		}

		isCover := i == 0
		_, err = tx.Exec(ctx,
			`INSERT INTO entry_images (entry_id, image_data, is_cover, position) VALUES ($1, $2, $3, $4)`,
			entryID, data, isCover, i,
		)
		if err != nil {
			return fmt.Errorf("failed to insert entry image: %w", err)
		}
	}

	return tx.Commit(ctx)
}
