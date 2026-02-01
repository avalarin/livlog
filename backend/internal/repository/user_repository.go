package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrUserNotFound         = errors.New("user not found")
	ErrRefreshTokenNotFound = errors.New("refresh token not found")
)

type User struct {
	ID            uuid.UUID  `json:"id"`
	Email         *string    `json:"email"`
	EmailVerified bool       `json:"email_verified"`
	DisplayName   *string    `json:"display_name"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	DeletedAt     *time.Time `json:"deleted_at,omitempty"`
}

type RefreshToken struct {
	ID               uuid.UUID  `json:"id"`
	UserID           uuid.UUID  `json:"user_id"`
	RefreshTokenHash string     `json:"-"`
	DeviceInfo       *string    `json:"device_info,omitempty"`
	ExpiresAt        time.Time  `json:"expires_at"`
	CreatedAt        time.Time  `json:"created_at"`
	RevokedAt        *time.Time `json:"revoked_at,omitempty"`
}

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

// Users

func (r *UserRepository) CreateUser(ctx context.Context, email, displayName string, emailVerified bool) (*User, error) {
	query := `
		INSERT INTO users (email, email_verified, display_name)
		VALUES ($1, $2, $3)
		RETURNING id, email, email_verified, display_name, created_at, updated_at, deleted_at
	`

	var user User
	err := r.db.QueryRow(ctx, query, email, emailVerified, displayName).Scan(
		&user.ID,
		&user.Email,
		&user.EmailVerified,
		&user.DisplayName,
		&user.CreatedAt,
		&user.UpdatedAt,
		&user.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	return &user, nil
}

func (r *UserRepository) GetUserByID(ctx context.Context, id uuid.UUID) (*User, error) {
	query := `
		SELECT id, email, email_verified, display_name, created_at, updated_at, deleted_at
		FROM users
		WHERE id = $1 AND deleted_at IS NULL
	`

	var user User
	err := r.db.QueryRow(ctx, query, id).Scan(
		&user.ID,
		&user.Email,
		&user.EmailVerified,
		&user.DisplayName,
		&user.CreatedAt,
		&user.UpdatedAt,
		&user.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	return &user, nil
}

func (r *UserRepository) GetUserByEmail(ctx context.Context, email string) (*User, error) {
	query := `
		SELECT id, email, email_verified, display_name, created_at, updated_at, deleted_at
		FROM users
		WHERE email = $1 AND deleted_at IS NULL
	`

	var user User
	err := r.db.QueryRow(ctx, query, email).Scan(
		&user.ID,
		&user.Email,
		&user.EmailVerified,
		&user.DisplayName,
		&user.CreatedAt,
		&user.UpdatedAt,
		&user.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("failed to get user by email: %w", err)
	}

	return &user, nil
}

func (r *UserRepository) DeleteUser(ctx context.Context, id uuid.UUID) error {
	query := `
		UPDATE users
		SET deleted_at = NOW()
		WHERE id = $1 AND deleted_at IS NULL
	`

	result, err := r.db.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to delete user: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrUserNotFound
	}

	return nil
}

// Auth Providers

func (r *UserRepository) FindUserByProvider(ctx context.Context, provider, providerUserID string) (*User, error) {
	query := `
		SELECT u.id, u.email, u.email_verified, u.display_name, u.created_at, u.updated_at, u.deleted_at
		FROM users u
		JOIN user_auth_providers p ON u.id = p.user_id
		WHERE p.provider = $1 AND p.provider_user_id = $2 AND u.deleted_at IS NULL
	`

	var user User
	err := r.db.QueryRow(ctx, query, provider, providerUserID).Scan(
		&user.ID,
		&user.Email,
		&user.EmailVerified,
		&user.DisplayName,
		&user.CreatedAt,
		&user.UpdatedAt,
		&user.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, fmt.Errorf("failed to find user by provider: %w", err)
	}

	return &user, nil
}

func (r *UserRepository) CreateAuthProvider(ctx context.Context, userID uuid.UUID, provider, providerUserID string) error {
	query := `
		INSERT INTO user_auth_providers (user_id, provider, provider_user_id)
		VALUES ($1, $2, $3)
	`

	_, err := r.db.Exec(ctx, query, userID, provider, providerUserID)
	if err != nil {
		return fmt.Errorf("failed to create auth provider: %w", err)
	}

	return nil
}

func (r *UserRepository) GetUserAuthProviders(ctx context.Context, userID uuid.UUID) ([]string, error) {
	query := `
		SELECT provider
		FROM user_auth_providers
		WHERE user_id = $1
		ORDER BY created_at
	`

	rows, err := r.db.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to get user auth providers: %w", err)
	}
	defer rows.Close()

	var providers []string
	for rows.Next() {
		var provider string
		if err := rows.Scan(&provider); err != nil {
			return nil, fmt.Errorf("failed to scan provider: %w", err)
		}
		providers = append(providers, provider)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}

	return providers, nil
}

// Tokens

func hashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}

func (r *UserRepository) SaveRefreshToken(ctx context.Context, userID uuid.UUID, token string, expiresAt time.Time) error {
	tokenHash := hashToken(token)

	query := `
		INSERT INTO user_tokens (user_id, refresh_token_hash, expires_at)
		VALUES ($1, $2, $3)
	`

	_, err := r.db.Exec(ctx, query, userID, tokenHash, expiresAt)
	if err != nil {
		return fmt.Errorf("failed to save refresh token: %w", err)
	}

	return nil
}

func (r *UserRepository) FindRefreshToken(ctx context.Context, token string) (*RefreshToken, error) {
	tokenHash := hashToken(token)

	query := `
		SELECT id, user_id, refresh_token_hash, device_info, expires_at, created_at, revoked_at
		FROM user_tokens
		WHERE refresh_token_hash = $1 AND revoked_at IS NULL AND expires_at > NOW()
	`

	var rt RefreshToken
	err := r.db.QueryRow(ctx, query, tokenHash).Scan(
		&rt.ID,
		&rt.UserID,
		&rt.RefreshTokenHash,
		&rt.DeviceInfo,
		&rt.ExpiresAt,
		&rt.CreatedAt,
		&rt.RevokedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrRefreshTokenNotFound
		}
		return nil, fmt.Errorf("failed to find refresh token: %w", err)
	}

	return &rt, nil
}

func (r *UserRepository) RevokeRefreshToken(ctx context.Context, token string) error {
	tokenHash := hashToken(token)

	query := `
		UPDATE user_tokens
		SET revoked_at = NOW()
		WHERE refresh_token_hash = $1 AND revoked_at IS NULL
	`

	result, err := r.db.Exec(ctx, query, tokenHash)
	if err != nil {
		return fmt.Errorf("failed to revoke refresh token: %w", err)
	}

	if result.RowsAffected() == 0 {
		return ErrRefreshTokenNotFound
	}

	return nil
}

func (r *UserRepository) RevokeAllUserTokens(ctx context.Context, userID uuid.UUID) error {
	query := `
		UPDATE user_tokens
		SET revoked_at = NOW()
		WHERE user_id = $1 AND revoked_at IS NULL
	`

	_, err := r.db.Exec(ctx, query, userID)
	if err != nil {
		return fmt.Errorf("failed to revoke all user tokens: %w", err)
	}

	return nil
}

// Transaction helper for creating user + auth provider atomically
func (r *UserRepository) CreateUserWithProvider(
	ctx context.Context,
	email, displayName string,
	emailVerified bool,
	provider, providerUserID string,
) (*User, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Create user
	userQuery := `
		INSERT INTO users (email, email_verified, display_name)
		VALUES ($1, $2, $3)
		RETURNING id, email, email_verified, display_name, created_at, updated_at, deleted_at
	`

	var user User
	err = tx.QueryRow(ctx, userQuery, email, emailVerified, displayName).Scan(
		&user.ID,
		&user.Email,
		&user.EmailVerified,
		&user.DisplayName,
		&user.CreatedAt,
		&user.UpdatedAt,
		&user.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	// Create auth provider
	providerQuery := `
		INSERT INTO user_auth_providers (user_id, provider, provider_user_id)
		VALUES ($1, $2, $3)
	`

	_, err = tx.Exec(ctx, providerQuery, user.ID, provider, providerUserID)
	if err != nil {
		return nil, fmt.Errorf("failed to create auth provider: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return &user, nil
}
