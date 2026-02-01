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
	ErrVerificationCodeNotFound = errors.New("verification code not found")
	ErrVerificationCodeExpired  = errors.New("verification code expired")
	ErrVerificationCodeUsed     = errors.New("verification code already used")
)

type VerificationCode struct {
	ID        uuid.UUID  `json:"id"`
	Email     string     `json:"email"`
	CodeHash  string     `json:"-"`
	CreatedAt time.Time  `json:"created_at"`
	ExpiresAt time.Time  `json:"expires_at"`
	UsedAt    *time.Time `json:"used_at,omitempty"`
}

type VerificationCodeRepository struct {
	db *pgxpool.Pool
}

func NewVerificationCodeRepository(db *pgxpool.Pool) *VerificationCodeRepository {
	return &VerificationCodeRepository{db: db}
}

// hashCode returns SHA256 hash of the verification code
func hashCode(code string) string {
	hash := sha256.Sum256([]byte(code))
	return hex.EncodeToString(hash[:])
}

// CreateVerificationCode creates a new verification code
// It automatically invalidates any previous unused codes for the same email
func (r *VerificationCodeRepository) CreateVerificationCode(
	ctx context.Context,
	email, code string,
	expiresAt time.Time,
) (*VerificationCode, error) {
	codeHash := hashCode(code)

	// Start transaction to invalidate previous codes and create new one
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Invalidate all previous unused codes for this email
	invalidateQuery := `
		UPDATE verification_codes
		SET used_at = NOW()
		WHERE email = $1 AND used_at IS NULL
	`
	_, err = tx.Exec(ctx, invalidateQuery, email)
	if err != nil {
		return nil, fmt.Errorf("failed to invalidate previous codes: %w", err)
	}

	// Create new verification code
	query := `
		INSERT INTO verification_codes (email, code_hash, expires_at)
		VALUES ($1, $2, $3)
		RETURNING id, email, code_hash, created_at, expires_at, used_at
	`

	var verificationCode VerificationCode
	err = tx.QueryRow(ctx, query, email, codeHash, expiresAt).Scan(
		&verificationCode.ID,
		&verificationCode.Email,
		&verificationCode.CodeHash,
		&verificationCode.CreatedAt,
		&verificationCode.ExpiresAt,
		&verificationCode.UsedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create verification code: %w", err)
	}

	// Commit transaction
	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return &verificationCode, nil
}

// FindVerificationCode finds an unused, non-expired verification code
func (r *VerificationCodeRepository) FindVerificationCode(
	ctx context.Context,
	email, code string,
) (*VerificationCode, error) {
	codeHash := hashCode(code)

	query := `
		SELECT id, email, code_hash, created_at, expires_at, used_at
		FROM verification_codes
		WHERE email = $1 AND code_hash = $2 AND used_at IS NULL
		ORDER BY created_at DESC
		LIMIT 1
	`

	var verificationCode VerificationCode
	err := r.db.QueryRow(ctx, query, email, codeHash).Scan(
		&verificationCode.ID,
		&verificationCode.Email,
		&verificationCode.CodeHash,
		&verificationCode.CreatedAt,
		&verificationCode.ExpiresAt,
		&verificationCode.UsedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrVerificationCodeNotFound
		}
		return nil, fmt.Errorf("failed to find verification code: %w", err)
	}

	// Check if code is expired
	if time.Now().After(verificationCode.ExpiresAt) {
		return nil, ErrVerificationCodeExpired
	}

	return &verificationCode, nil
}

// MarkCodeAsUsed marks a verification code as used
func (r *VerificationCodeRepository) MarkCodeAsUsed(ctx context.Context, id uuid.UUID) error {
	query := `
		UPDATE verification_codes
		SET used_at = NOW()
		WHERE id = $1 AND used_at IS NULL
	`

	result, err := r.db.Exec(ctx, query, id)
	if err != nil {
		return fmt.Errorf("failed to mark code as used: %w", err)
	}

	rowsAffected := result.RowsAffected()
	if rowsAffected == 0 {
		return ErrVerificationCodeUsed
	}

	return nil
}

// InvalidatePreviousCodes marks all previous codes for this email as used
// This is useful when a new code is requested
func (r *VerificationCodeRepository) InvalidatePreviousCodes(ctx context.Context, email string) error {
	query := `
		UPDATE verification_codes
		SET used_at = NOW()
		WHERE email = $1 AND used_at IS NULL
	`

	_, err := r.db.Exec(ctx, query, email)
	if err != nil {
		return fmt.Errorf("failed to invalidate previous codes: %w", err)
	}

	return nil
}

// CleanupExpiredCodes removes codes older than the retention period
// This should be called periodically by a background job
func (r *VerificationCodeRepository) CleanupExpiredCodes(
	ctx context.Context,
	retentionPeriod time.Duration,
) (int64, error) {
	query := `
		DELETE FROM verification_codes
		WHERE created_at < NOW() - $1::interval
	`

	result, err := r.db.Exec(ctx, query, retentionPeriod)
	if err != nil {
		return 0, fmt.Errorf("failed to cleanup expired codes: %w", err)
	}

	return result.RowsAffected(), nil
}
