package service

import (
	"context"
	"time"

	"github.com/google/uuid"

	"github.com/avalarin/livlog/backend/internal/repository"
)

// UserRepository defines methods used by auth services for user operations
type UserRepository interface {
	GetUserByEmail(ctx context.Context, email string) (*repository.User, error)
	FindUserByProvider(ctx context.Context, provider, providerUserID string) (*repository.User, error)
	CreateUserWithProvider(ctx context.Context, email, displayName string, emailVerified bool, provider, providerUserID string) (*repository.User, error)
	CreateAuthProvider(ctx context.Context, userID uuid.UUID, provider, providerUserID string) error
	SaveRefreshToken(ctx context.Context, userID uuid.UUID, token string, expiresAt time.Time) error
	GetUserAuthProviders(ctx context.Context, userID uuid.UUID) ([]string, error)
}

// VerificationCodeRepository defines methods for verification code operations
type VerificationCodeRepository interface {
	CreateVerificationCode(ctx context.Context, email, code string, expiresAt time.Time) (*repository.VerificationCode, error)
	FindVerificationCode(ctx context.Context, email, code string) (*repository.VerificationCode, error)
	MarkCodeAsUsed(ctx context.Context, id uuid.UUID) error
}

// VerificationAttemptRepository defines methods for rate limiting
type VerificationAttemptRepository interface {
	RecordAttempt(ctx context.Context, email, deviceID, ipAddress string) error
	HasRecentAttempt(ctx context.Context, email, deviceID, ipAddress string, cooldown time.Duration) (bool, error)
	CountRecentAttempts(ctx context.Context, email string, window time.Duration) (int, error)
	GetLastAttemptTime(ctx context.Context, email string, window time.Duration) (*time.Time, error)
	CountDistinctEmailsByDevice(ctx context.Context, deviceID string, window time.Duration) (int, error)
	GetOldestAttemptTimeByDevice(ctx context.Context, deviceID string, window time.Duration) (*time.Time, error)
}

// JWTProvider defines methods for JWT token operations
type JWTProvider interface {
	GenerateAccessToken(userID, email string) (string, error)
	GenerateRefreshToken() (string, error)
	GetAccessTokenLifetime() time.Duration
	GetRefreshTokenLifetime() time.Duration
}

// EmailProvider defines methods for sending emails
type EmailProvider interface {
	SendVerificationCode(ctx context.Context, email string, code string) error
	IsEnabled() bool
}
