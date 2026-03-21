package service

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"time"

	"github.com/avalarin/livlog/backend/internal/repository"
)

const (
	// HardcodedVerificationCode is the verification code used when email sending is disabled
	HardcodedVerificationCode = "000000"

	// VerificationCodeExpiry is the time window for code verification
	VerificationCodeExpiry = 5 * time.Minute
)

var (
	ErrInvalidEmail      = errors.New("invalid email format")
	ErrInvalidCode       = errors.New("invalid verification code")
	ErrCodeExpired       = errors.New("verification code expired")
	ErrCodeAlreadyUsed   = errors.New("verification code already used")
	ErrRateLimitExceeded = errors.New("too many requests, please wait")

	// Simple email regex for basic validation
	emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`)
)

// RateLimitError carries rate limit details so the handler can return structured 429 responses.
type RateLimitError struct {
	RetryAfter int    // remaining seconds until the client may retry
	LimitType  string // "email_cooldown" or "device_limit" or "hourly_limit"
}

func (e *RateLimitError) Error() string { return "rate limit exceeded" }

type EmailAuthService struct {
	userRepo           UserRepository
	codeRepo           VerificationCodeRepository
	attemptRepo        VerificationAttemptRepository
	jwtService         JWTProvider
	emailSender        EmailProvider
	resendCooldown     time.Duration
	perEmailCooldown   time.Duration
	deviceMaxEmails    int
	deviceWindow       time.Duration
	maxCodesPerHour    int
	ipRateLimitEnabled bool
}

func NewEmailAuthService(
	userRepo UserRepository,
	codeRepo VerificationCodeRepository,
	attemptRepo VerificationAttemptRepository,
	jwtService JWTProvider,
	emailSender EmailProvider,
	resendCooldown time.Duration,
	maxCodesPerHour int,
	ipRateLimitEnabled bool,
	perEmailCooldown time.Duration,
	deviceMaxEmails int,
	deviceWindow time.Duration,
) *EmailAuthService {
	return &EmailAuthService{
		userRepo:           userRepo,
		codeRepo:           codeRepo,
		attemptRepo:        attemptRepo,
		jwtService:         jwtService,
		emailSender:        emailSender,
		resendCooldown:     resendCooldown,
		perEmailCooldown:   perEmailCooldown,
		deviceMaxEmails:    deviceMaxEmails,
		deviceWindow:       deviceWindow,
		maxCodesPerHour:    maxCodesPerHour,
		ipRateLimitEnabled: ipRateLimitEnabled,
	}
}

// SendVerificationCode generates and stores a verification code for the email, then sends it
func (s *EmailAuthService) SendVerificationCode(ctx context.Context, email, deviceID, ipAddress string) error {
	// Validate email format
	if !isValidEmail(email) {
		return ErrInvalidEmail
	}

	// Check rate limit
	if err := s.checkRateLimit(ctx, email, deviceID, ipAddress); err != nil {
		return err
	}

	// Generate code: random if email is enabled, hardcoded otherwise
	var code string
	if s.emailSender.IsEnabled() {
		var err error
		code, err = generateVerificationCode()
		if err != nil {
			return err
		}
	} else {
		code = HardcodedVerificationCode
	}

	// Calculate expiry time
	expiresAt := time.Now().Add(VerificationCodeExpiry)

	// Record attempt in DB first (consumes rate-limit window regardless of outcome)
	recordIP := ipAddress
	if !s.ipRateLimitEnabled {
		recordIP = ""
	}
	if err := s.attemptRepo.RecordAttempt(ctx, email, deviceID, recordIP); err != nil {
		return fmt.Errorf("failed to record verification attempt: %w", err)
	}

	// Create verification code (automatically invalidates previous codes)
	_, err := s.codeRepo.CreateVerificationCode(ctx, email, code, expiresAt)
	if err != nil {
		return fmt.Errorf("failed to create verification code: %w", err)
	}

	// Send email
	if err := s.emailSender.SendVerificationCode(ctx, email, code); err != nil {
		return fmt.Errorf("failed to send verification email: %w", err)
	}

	return nil
}

// ResendVerificationCode resends verification code with rate limiting
func (s *EmailAuthService) ResendVerificationCode(ctx context.Context, email, deviceID, ipAddress string) error {
	return s.SendVerificationCode(ctx, email, deviceID, ipAddress)
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

// GetResendCooldown returns the per-email cooldown in seconds (shown to users as the resend timer)
func (s *EmailAuthService) GetResendCooldown() int {
	return int(s.perEmailCooldown.Seconds())
}

// checkRateLimit enforces three independent limits:
//  1. Per-email cooldown: minimum time between sends for the same email address.
//  2. Per-device distinct-email cap: prevents a single device from spamming many addresses.
//  3. Hourly per-email safety net: hard cap on total sends for one email per hour.
func (s *EmailAuthService) checkRateLimit(ctx context.Context, email, deviceID, _ string) error {
	// 1. Per-email cooldown
	lastAttempt, err := s.attemptRepo.GetLastAttemptTime(ctx, email, s.perEmailCooldown)
	if err != nil {
		return fmt.Errorf("failed to check rate limit: %w", err)
	}
	if lastAttempt != nil {
		elapsed := time.Since(*lastAttempt)
		remaining := s.perEmailCooldown - elapsed
		if remaining > 0 {
			return &RateLimitError{
				RetryAfter: int(remaining.Seconds()) + 1, // round up
				LimitType:  "email_cooldown",
			}
		}
	}

	// 2. Per-device distinct-email limit
	if deviceID != "" {
		distinctCount, err := s.attemptRepo.CountDistinctEmailsByDevice(ctx, deviceID, s.deviceWindow)
		if err != nil {
			return fmt.Errorf("failed to check device rate limit: %w", err)
		}
		if distinctCount >= s.deviceMaxEmails {
			retryAfter := int(s.deviceWindow.Seconds())
			oldest, err := s.attemptRepo.GetOldestAttemptTimeByDevice(ctx, deviceID, s.deviceWindow)
			if err == nil && oldest != nil {
				remaining := s.deviceWindow - time.Since(*oldest)
				if remaining > 0 {
					retryAfter = int(remaining.Seconds()) + 1
				}
			}
			return &RateLimitError{
				RetryAfter: retryAfter,
				LimitType:  "device_limit",
			}
		}
	}

	// 3. Hourly per-email safety net
	count, err := s.attemptRepo.CountRecentAttempts(ctx, email, time.Hour)
	if err != nil {
		return fmt.Errorf("failed to count attempts: %w", err)
	}
	if count >= s.maxCodesPerHour {
		return &RateLimitError{
			RetryAfter: int(time.Hour.Seconds()),
			LimitType:  "hourly_limit",
		}
	}

	return nil
}

// generateVerificationCode generates a cryptographically random 6-digit code
func generateVerificationCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", fmt.Errorf("failed to generate random code: %w", err)
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// Helper functions

// findOrCreateEmailUser finds existing user by email or creates new one.
// If the user exists (e.g. registered via Apple Sign In) but has no email provider,
// links the email provider to the existing account.
func (s *EmailAuthService) findOrCreateEmailUser(ctx context.Context, email string) (*repository.User, error) {
	// Try to find user by email provider
	user, err := s.userRepo.FindUserByProvider(ctx, "email", email)
	if err == nil {
		return user, nil
	}
	if !errors.Is(err, repository.ErrUserNotFound) {
		return nil, fmt.Errorf("failed to find user: %w", err)
	}

	// No email provider — check if user exists with this email (e.g. via Apple)
	user, err = s.userRepo.GetUserByEmail(ctx, email)
	if err != nil && !errors.Is(err, repository.ErrUserNotFound) {
		return nil, fmt.Errorf("failed to find user by email: %w", err)
	}
	if user != nil {
		// Link email provider to existing account
		if err := s.userRepo.CreateAuthProvider(ctx, user.ID, "email", email); err != nil {
			return nil, fmt.Errorf("failed to link email provider: %w", err)
		}
		return user, nil
	}

	// Completely new user — create with email provider
	user, err = s.userRepo.CreateUserWithProvider(
		ctx,
		email,
		"",      // No display name initially
		true,    // Email verified after successful code verification
		"email", // Provider type
		email,   // Provider user ID is the email itself
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create user: %w", err)
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
