package service

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"time"

	"github.com/avalarin/livlog/backend/internal/repository"
)

const (
	// HardcodedVerificationCode is the verification code used in MVP
	// In production, this should be replaced with a randomly generated code
	HardcodedVerificationCode = "000000"

	// VerificationCodeExpiry is the time window for code verification
	VerificationCodeExpiry = 5 * time.Minute
)

var (
	ErrInvalidEmail          = errors.New("invalid email format")
	ErrInvalidCode           = errors.New("invalid verification code")
	ErrCodeExpired           = errors.New("verification code expired")
	ErrCodeAlreadyUsed       = errors.New("verification code already used")
	ErrRateLimitExceeded     = errors.New("too many requests, please wait")

	// Simple email regex for basic validation
	emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
)

type EmailAuthService struct {
	userRepo     *repository.UserRepository
	codeRepo     *repository.VerificationCodeRepository
	jwtService   *JWTService
	rateLimiter  *RateLimiter
}

func NewEmailAuthService(
	userRepo *repository.UserRepository,
	codeRepo *repository.VerificationCodeRepository,
	jwtService *JWTService,
	rateLimiter *RateLimiter,
) *EmailAuthService {
	return &EmailAuthService{
		userRepo:    userRepo,
		codeRepo:    codeRepo,
		jwtService:  jwtService,
		rateLimiter: rateLimiter,
	}
}

// SendVerificationCode generates and stores a verification code for the email
// For MVP, always uses hardcoded "000000"
func (s *EmailAuthService) SendVerificationCode(ctx context.Context, email string) error {
	// Validate email format
	if !isValidEmail(email) {
		return ErrInvalidEmail
	}

	// Generate code (hardcoded for MVP)
	code := HardcodedVerificationCode

	// Calculate expiry time
	expiresAt := time.Now().Add(VerificationCodeExpiry)

	// Create verification code (automatically invalidates previous codes)
	_, err := s.codeRepo.CreateVerificationCode(ctx, email, code, expiresAt)
	if err != nil {
		return fmt.Errorf("failed to create verification code: %w", err)
	}

	// In production, send email here
	// emailService.SendVerificationEmail(email, code)

	return nil
}

// ResendVerificationCode resends verification code with rate limiting
func (s *EmailAuthService) ResendVerificationCode(ctx context.Context, email string) error {
	// Validate email format
	if !isValidEmail(email) {
		return ErrInvalidEmail
	}

	// Check rate limit (1 request per minute per email)
	rateLimitKey := fmt.Sprintf("resend:%s", email)
	if !s.rateLimiter.Allow(rateLimitKey) {
		return ErrRateLimitExceeded
	}

	// Send new verification code
	return s.SendVerificationCode(ctx, email)
}

// VerifyCode verifies the code and returns auth response
// Creates user if doesn't exist
func (s *EmailAuthService) VerifyCode(ctx context.Context, email, code string) (*AuthResponse, error) {
	// Validate email format
	if !isValidEmail(email) {
		return nil, ErrInvalidEmail
	}

	// Validate code format (6 digits)
	if !isValidCode(code) {
		return nil, ErrInvalidCode
	}

	// Find and validate code
	verificationCode, err := s.codeRepo.FindVerificationCode(ctx, email, code)
	if err != nil {
		if errors.Is(err, repository.ErrVerificationCodeNotFound) {
			return nil, ErrInvalidCode
		}
		if errors.Is(err, repository.ErrVerificationCodeExpired) {
			return nil, ErrCodeExpired
		}
		return nil, fmt.Errorf("failed to find verification code: %w", err)
	}

	// Mark code as used
	if err := s.codeRepo.MarkCodeAsUsed(ctx, verificationCode.ID); err != nil {
		if errors.Is(err, repository.ErrVerificationCodeUsed) {
			return nil, ErrCodeAlreadyUsed
		}
		return nil, fmt.Errorf("failed to mark code as used: %w", err)
	}

	// Find or create user
	user, err := s.findOrCreateEmailUser(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("failed to find or create user: %w", err)
	}

	// Generate tokens
	accessToken, err := s.jwtService.GenerateAccessToken(user.ID.String(), getEmailString(user.Email))
	if err != nil {
		return nil, fmt.Errorf("failed to generate access token: %w", err)
	}

	refreshToken, err := s.jwtService.GenerateRefreshToken()
	if err != nil {
		return nil, fmt.Errorf("failed to generate refresh token: %w", err)
	}

	// Save refresh token
	expiresAt := time.Now().Add(s.jwtService.GetRefreshTokenLifetime())
	if err := s.userRepo.SaveRefreshToken(ctx, user.ID, refreshToken, expiresAt); err != nil {
		return nil, fmt.Errorf("failed to save refresh token: %w", err)
	}

	// Get auth providers
	providers, err := s.userRepo.GetUserAuthProviders(ctx, user.ID)
	if err != nil {
		return nil, fmt.Errorf("failed to get auth providers: %w", err)
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int(s.jwtService.GetAccessTokenLifetime().Seconds()),
		User:         mapUserToResponse(user, providers),
	}, nil
}

// GetRetryAfter returns seconds until next resend is allowed
func (s *EmailAuthService) GetRetryAfter(email string) int {
	rateLimitKey := fmt.Sprintf("resend:%s", email)
	return s.rateLimiter.GetRetryAfter(rateLimitKey)
}

// Helper functions

// findOrCreateEmailUser finds existing user by email or creates new one
func (s *EmailAuthService) findOrCreateEmailUser(ctx context.Context, email string) (*repository.User, error) {
	// Try to find user by email provider
	user, err := s.userRepo.FindUserByProvider(ctx, "email", email)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			// Create new user with email provider
			user, err = s.userRepo.CreateUserWithProvider(
				ctx,
				email,
				"",           // No display name initially
				true,         // Email verified after successful code verification
				"email",      // Provider type
				email,        // Provider user ID is the email itself
			)
			if err != nil {
				return nil, fmt.Errorf("failed to create user: %w", err)
			}
			return user, nil
		}
		return nil, fmt.Errorf("failed to find user: %w", err)
	}

	return user, nil
}

// isValidEmail validates email format using basic regex
func isValidEmail(email string) bool {
	if email == "" {
		return false
	}
	if len(email) > 255 {
		return false
	}
	return emailRegex.MatchString(email)
}

// isValidCode validates verification code format (6 digits)
func isValidCode(code string) bool {
	if len(code) != 6 {
		return false
	}
	for _, c := range code {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
