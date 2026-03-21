package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrCollectionNotFound = errors.New("collection not found")
	ErrAlreadyMember      = errors.New("user is already a member")
	ErrLastOwner          = errors.New("cannot remove the last owner from a collection")
)

type Collection struct {
	ID                uuid.UUID   `json:"id"`
	UserID            *uuid.UUID  `json:"user_id,omitempty"`
	Name              string      `json:"name"`
	Icon              string      `json:"icon"`
	Color             string      `json:"color"`
	IsTemplate        bool        `json:"is_template"`
	Slug              *string     `json:"slug,omitempty"`
	Description       string      `json:"description"`
	AllowedEntryTypes []uuid.UUID `json:"allowed_entry_types"`
	EntryCount        int         `json:"entry_count"`
	MemberCount       int         `json:"member_count"`
	MyRole            string      `json:"my_role"`
	SharedBy          *string     `json:"shared_by,omitempty"`
	CreatedAt         time.Time   `json:"created_at"`
	UpdatedAt         time.Time   `json:"updated_at"`
}

type CollectionMember struct {
	UserID      uuid.UUID
	Email       *string
	DisplayName *string
	Role        string
	InvitedBy   uuid.UUID
	CreatedAt   time.Time
}

type CollectionRepository struct {
	db *pgxpool.Pool
}

func NewCollectionRepository(db *pgxpool.Pool) *CollectionRepository {
	return &CollectionRepository{db: db}
}

// CreateCollection creates a new collection and adds the creator as owner in collection_shares.
func (r *CollectionRepository) CreateCollection(
	ctx context.Context,
	userID uuid.UUID,
	name, icon, color string,
	allowedEntryTypes []uuid.UUID,
) (*Collection, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if allowedEntryTypes == nil {
		allowedEntryTypes = []uuid.UUID{}
	}

	insertQuery := `
		INSERT INTO collections (user_id, name, icon, color, allowed_entry_types)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, user_id, name, icon, color, COALESCE(allowed_entry_types, '{}'), created_at, updated_at
	`

	var collection Collection
	err = tx.QueryRow(ctx, insertQuery, userID, name, icon, color, allowedEntryTypes).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.Color,
		&collection.AllowedEntryTypes,
		&collection.CreatedAt,
		&collection.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create collection: %w", err)
	}

	shareQuery := `
		INSERT INTO collection_shares (collection_id, owner_id, shared_with_user_id, permission_level)
		VALUES ($1, $2, $3, 'owner')
	`
	_, err = tx.Exec(ctx, shareQuery, collection.ID, userID, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to add owner share: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	collection.EntryCount = 0
	collection.MemberCount = 1
	collection.MyRole = "owner"
	return &collection, nil
}

// GetCollectionsByUserID retrieves all collections accessible by the user via collection_shares.
// The shared_by field is populated with the inviter's display name (falling back to email)
// when the current user is not the collection creator.
func (r *CollectionRepository) GetCollectionsByUserID(
	ctx context.Context,
	userID uuid.UUID,
) ([]*Collection, error) {
	query := `
		SELECT c.id, c.user_id, c.name, c.icon, c.color, COUNT(DISTINCT e.id) AS entry_count,
		       (SELECT COUNT(*) FROM collection_shares cs2 WHERE cs2.collection_id = c.id) AS member_count,
		       cs.permission_level AS my_role, c.created_at, c.updated_at,
		       CASE WHEN c.user_id = $1 THEN NULL
		            ELSE (SELECT COALESCE(u.display_name, u.email) FROM users u WHERE u.id = cs.owner_id)
		       END AS shared_by,
		       COALESCE(c.allowed_entry_types, '{}') AS allowed_entry_types
		FROM collections c
		JOIN collection_shares cs ON cs.collection_id = c.id AND cs.shared_with_user_id = $1
		LEFT JOIN entries e ON e.collection_id = c.id
		GROUP BY c.id, cs.permission_level, cs.owner_id
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
			&collection.Color,
			&collection.EntryCount,
			&collection.MemberCount,
			&collection.MyRole,
			&collection.CreatedAt,
			&collection.UpdatedAt,
			&collection.SharedBy,
			&collection.AllowedEntryTypes,
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

// GetCollectionByID retrieves a single collection by ID, verifying the user has access via collection_shares.
func (r *CollectionRepository) GetCollectionByID(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) (*Collection, error) {
	query := `
		SELECT c.id, c.user_id, c.name, c.icon, c.color, COUNT(DISTINCT e.id) AS entry_count,
		       (SELECT COUNT(*) FROM collection_shares cs2 WHERE cs2.collection_id = c.id) AS member_count,
		       cs.permission_level AS my_role, c.created_at, c.updated_at,
		       COALESCE(c.allowed_entry_types, '{}') AS allowed_entry_types
		FROM collections c
		JOIN collection_shares cs ON cs.collection_id = c.id
		LEFT JOIN entries e ON e.collection_id = c.id
		WHERE c.id = $1 AND cs.shared_with_user_id = $2
		GROUP BY c.id, cs.permission_level
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, id, userID).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.Color,
		&collection.EntryCount,
		&collection.MemberCount,
		&collection.MyRole,
		&collection.CreatedAt,
		&collection.UpdatedAt,
		&collection.AllowedEntryTypes,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCollectionNotFound
		}
		return nil, fmt.Errorf("failed to get collection: %w", err)
	}

	return &collection, nil
}

// GetUserRole returns the permission level for a user in a collection.
func (r *CollectionRepository) GetUserRole(
	ctx context.Context,
	collectionID, userID uuid.UUID,
) (string, error) {
	query := `
		SELECT permission_level FROM collection_shares
		WHERE collection_id = $1 AND shared_with_user_id = $2
	`

	var role string
	err := r.db.QueryRow(ctx, query, collectionID, userID).Scan(&role)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrCollectionNotFound
		}
		return "", fmt.Errorf("failed to get user role: %w", err)
	}

	return role, nil
}

// GetCollectionMembers returns all members of a collection.
func (r *CollectionRepository) GetCollectionMembers(
	ctx context.Context,
	collectionID uuid.UUID,
) ([]*CollectionMember, error) {
	query := `
		SELECT cs.shared_with_user_id, u.email, COALESCE(u.display_name, u.email) AS display_name,
		       cs.permission_level, cs.owner_id, cs.created_at
		FROM collection_shares cs
		JOIN users u ON u.id = cs.shared_with_user_id
		WHERE cs.collection_id = $1
		ORDER BY cs.created_at ASC
	`

	rows, err := r.db.Query(ctx, query, collectionID)
	if err != nil {
		return nil, fmt.Errorf("failed to query members: %w", err)
	}
	defer rows.Close()

	var members []*CollectionMember
	for rows.Next() {
		var m CollectionMember
		err := rows.Scan(
			&m.UserID,
			&m.Email,
			&m.DisplayName,
			&m.Role,
			&m.InvitedBy,
			&m.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan member: %w", err)
		}
		members = append(members, &m)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating members: %w", err)
	}

	return members, nil
}

// AddCollectionShare adds a new member to a collection.
func (r *CollectionRepository) AddCollectionShare(
	ctx context.Context,
	collectionID, inviterID, inviteeID uuid.UUID,
	role string,
) error {
	query := `
		INSERT INTO collection_shares (collection_id, owner_id, shared_with_user_id, permission_level)
		VALUES ($1, $2, $3, $4)
	`

	_, err := r.db.Exec(ctx, query, collectionID, inviterID, inviteeID, role)
	if err != nil {
		// Check for unique constraint violation (pgx error code 23505)
		if isUniqueViolation(err) {
			return ErrAlreadyMember
		}
		return fmt.Errorf("failed to add collection share: %w", err)
	}

	return nil
}

// RemoveCollectionShare removes a user from a collection within a single transaction.
// The last owner is allowed to leave; the collection becomes orphaned.
func (r *CollectionRepository) RemoveCollectionShare(
	ctx context.Context,
	collectionID, userID uuid.UUID,
) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Verify membership exists before deleting.
	var exists bool
	err = tx.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM collection_shares
		 WHERE collection_id = $1 AND shared_with_user_id = $2
		 FOR UPDATE)`,
		collectionID, userID,
	).Scan(&exists)
	if err != nil {
		return fmt.Errorf("failed to check membership: %w", err)
	}
	if !exists {
		return ErrCollectionNotFound
	}

	_, err = tx.Exec(ctx,
		`DELETE FROM collection_shares WHERE collection_id = $1 AND shared_with_user_id = $2`,
		collectionID, userID,
	)
	if err != nil {
		return fmt.Errorf("failed to remove collection share: %w", err)
	}

	return tx.Commit(ctx)
}

// UpdateCollectionShare changes a user's permission level in a collection.
// Returns ErrLastOwner if trying to demote the last owner.
// Returns ErrCollectionNotFound if the membership does not exist.
func (r *CollectionRepository) UpdateCollectionShare(
	ctx context.Context,
	collectionID, userID uuid.UUID,
	newRole string,
) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Lock the target row to prevent concurrent updates racing.
	var targetRole string
	err = tx.QueryRow(ctx,
		`SELECT permission_level FROM collection_shares
		 WHERE collection_id = $1 AND shared_with_user_id = $2
		 FOR UPDATE`,
		collectionID, userID,
	).Scan(&targetRole)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrCollectionNotFound
		}
		return fmt.Errorf("failed to get target role: %w", err)
	}

	// If demoting an owner, ensure at least one other owner remains.
	if targetRole == "owner" && newRole != "owner" {
		var ownerCount int
		err = tx.QueryRow(ctx,
			`SELECT COUNT(*) FROM collection_shares
			 WHERE collection_id = $1 AND permission_level = 'owner'`,
			collectionID,
		).Scan(&ownerCount)
		if err != nil {
			return fmt.Errorf("failed to count owners: %w", err)
		}
		if ownerCount <= 1 {
			return ErrLastOwner
		}
	}

	_, err = tx.Exec(ctx,
		`UPDATE collection_shares SET permission_level = $3
		 WHERE collection_id = $1 AND shared_with_user_id = $2`,
		collectionID, userID, newRole,
	)
	if err != nil {
		return fmt.Errorf("failed to update collection share: %w", err)
	}

	return tx.Commit(ctx)
}

// UpdateCollection updates a collection's name, icon, color, and allowed entry types.
func (r *CollectionRepository) UpdateCollection(
	ctx context.Context,
	id uuid.UUID,
	name, icon, color string,
	allowedEntryTypes []uuid.UUID,
) (*Collection, error) {
	if allowedEntryTypes == nil {
		allowedEntryTypes = []uuid.UUID{}
	}

	query := `
		UPDATE collections
		SET name = $2, icon = $3, color = $4, allowed_entry_types = $5, updated_at = NOW()
		WHERE id = $1
		RETURNING id, user_id, name, icon, color, COALESCE(allowed_entry_types, '{}'), created_at, updated_at
	`

	var collection Collection
	err := r.db.QueryRow(ctx, query, id, name, icon, color, allowedEntryTypes).Scan(
		&collection.ID,
		&collection.UserID,
		&collection.Name,
		&collection.Icon,
		&collection.Color,
		&collection.AllowedEntryTypes,
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

// CreateDefaultCollections creates the default "My List" collection for a new user.
func (r *CollectionRepository) CreateDefaultCollections(
	ctx context.Context,
	userID uuid.UUID,
) ([]*Collection, error) {
	collection, err := r.CreateCollection(ctx, userID, "My List", "system:folder", "dodger-blue", []uuid.UUID{})
	if err != nil {
		return nil, fmt.Errorf("failed to create default collection: %w", err)
	}

	return []*Collection{collection}, nil
}

// HasCollections checks if user has any collections.
func (r *CollectionRepository) HasCollections(
	ctx context.Context,
	userID uuid.UUID,
) (bool, error) {
	query := `SELECT EXISTS(SELECT 1 FROM collection_shares WHERE shared_with_user_id = $1)`

	var exists bool
	err := r.db.QueryRow(ctx, query, userID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check collections: %w", err)
	}

	return exists, nil
}

// GetTemplateCollections returns all template collections ordered by name.
func (r *CollectionRepository) GetTemplateCollections(
	ctx context.Context,
) ([]*Collection, error) {
	query := `
		SELECT id, name, icon, color, slug, description, COALESCE(allowed_entry_types, '{}'), created_at, updated_at
		FROM collections
		WHERE is_template = true
		ORDER BY created_at ASC
	`

	rows, err := r.db.Query(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("failed to query template collections: %w", err)
	}
	defer rows.Close()

	var collections []*Collection
	for rows.Next() {
		var c Collection
		err := rows.Scan(
			&c.ID,
			&c.Name,
			&c.Icon,
			&c.Color,
			&c.Slug,
			&c.Description,
			&c.AllowedEntryTypes,
			&c.CreatedAt,
			&c.UpdatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan template collection: %w", err)
		}
		c.IsTemplate = true
		collections = append(collections, &c)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating template collections: %w", err)
	}

	return collections, nil
}

// GetTemplateBySlug retrieves a template collection by its slug.
func (r *CollectionRepository) GetTemplateBySlug(
	ctx context.Context,
	slug string,
) (*Collection, error) {
	query := `
		SELECT id, name, icon, color, slug, description, COALESCE(allowed_entry_types, '{}'), created_at, updated_at
		FROM collections
		WHERE is_template = true AND slug = $1
	`

	var c Collection
	err := r.db.QueryRow(ctx, query, slug).Scan(
		&c.ID,
		&c.Name,
		&c.Icon,
		&c.Color,
		&c.Slug,
		&c.Description,
		&c.AllowedEntryTypes,
		&c.CreatedAt,
		&c.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCollectionNotFound
		}
		return nil, fmt.Errorf("failed to get template by slug: %w", err)
	}
	c.IsTemplate = true

	return &c, nil
}

// isUniqueViolation checks if an error is a PostgreSQL unique constraint violation (code 23505).
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
