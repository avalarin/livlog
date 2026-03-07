package service

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/avalarin/livlog/backend/internal/repository"
)

// --- Mock implementations ---

type mockUserRepo struct {
	findUserByProviderFn     func(ctx context.Context, provider, providerUserID string) (*repository.User, error)
	createUserWithProviderFn func(ctx context.Context, email, displayName string, emailVerified bool, provider, providerUserID string) (*repository.User, error)
	saveRefreshTokenFn       func(ctx context.Context, userID uuid.UUID, token string, expiresAt time.Time) error
	getUserAuthProvidersFn   func(ctx context.Context, userID uuid.UUID) ([]string, error)
}

func (m *mockUserRepo) FindUserByProvider(ctx context.Context, provider, providerUserID string) (*repository.User, error) {
	return m.findUserByProviderFn(ctx, provider, providerUserID)
}

func (m *mockUserRepo) CreateUserWithProvider(ctx context.Context, email, displayName string, emailVerified bool, provider, providerUserID string) (*repository.User, error) {
	return m.createUserWithProviderFn(ctx, email, displayName, emailVerified, provider, providerUserID)
}

func (m *mockUserRepo) SaveRefreshToken(ctx context.Context, userID uuid.UUID, token string, expiresAt time.Time) error {
	return m.saveRefreshTokenFn(ctx, userID, token, expiresAt)
}

func (m *mockUserRepo) GetUserAuthProviders(ctx context.Context, userID uuid.UUID) ([]string, error) {
	return m.getUserAuthProvidersFn(ctx, userID)
}

type mockCodeRepo struct {
	createVerificationCodeFn func(ctx context.Context, email, code string, expiresAt time.Time) (*repository.VerificationCode, error)
	findVerificationCodeFn   func(ctx context.Context, email, code string) (*repository.VerificationCode, error)
	markCodeAsUsedFn         func(ctx context.Context, id uuid.UUID) error

	// Capture args for assertions
	lastCreateEmail string
	lastCreateCode  string
}

func (m *mockCodeRepo) CreateVerificationCode(ctx context.Context, email, code string, expiresAt time.Time) (*repository.VerificationCode, error) {
	m.lastCreateEmail = email
	m.lastCreateCode = code
	return m.createVerificationCodeFn(ctx, email, code, expiresAt)
}

func (m *mockCodeRepo) FindVerificationCode(ctx context.Context, email, code string) (*repository.VerificationCode, error) {
	return m.findVerificationCodeFn(ctx, email, code)
}

func (m *mockCodeRepo) MarkCodeAsUsed(ctx context.Context, id uuid.UUID) error {
	return m.markCodeAsUsedFn(ctx, id)
}

type mockAttemptRepo struct {
	recordAttemptFn       func(ctx context.Context, email, deviceID, ipAddress string) error
	hasRecentAttemptFn    func(ctx context.Context, email, deviceID, ipAddress string, cooldown time.Duration) (bool, error)
	countRecentAttemptsFn func(ctx context.Context, email string, window time.Duration) (int, error)

	// Capture args for assertions
	lastRecordIP    string
	lastHasRecentIP string
}

func (m *mockAttemptRepo) RecordAttempt(ctx context.Context, email, deviceID, ipAddress string) error {
	m.lastRecordIP = ipAddress
	return m.recordAttemptFn(ctx, email, deviceID, ipAddress)
}

func (m *mockAttemptRepo) HasRecentAttempt(ctx context.Context, email, deviceID, ipAddress string, cooldown time.Duration) (bool, error) {
	m.lastHasRecentIP = ipAddress
	return m.hasRecentAttemptFn(ctx, email, deviceID, ipAddress, cooldown)
}

func (m *mockAttemptRepo) CountRecentAttempts(ctx context.Context, email string, window time.Duration) (int, error) {
	return m.countRecentAttemptsFn(ctx, email, window)
}

type mockJWTProvider struct {
	generateAccessTokenFn  func(userID, email string) (string, error)
	generateRefreshTokenFn func() (string, error)
	accessTokenLifetime    time.Duration
	refreshTokenLifetime   time.Duration
}

func (m *mockJWTProvider) GenerateAccessToken(userID, email string) (string, error) {
	return m.generateAccessTokenFn(userID, email)
}

func (m *mockJWTProvider) GenerateRefreshToken() (string, error) {
	return m.generateRefreshTokenFn()
}

func (m *mockJWTProvider) GetAccessTokenLifetime() time.Duration {
	return m.accessTokenLifetime
}

func (m *mockJWTProvider) GetRefreshTokenLifetime() time.Duration {
	return m.refreshTokenLifetime
}

type mockEmailProvider struct {
	sendVerificationCodeFn func(ctx context.Context, email string, code string) error
	enabled                bool
}

func (m *mockEmailProvider) SendVerificationCode(ctx context.Context, email string, code string) error {
	return m.sendVerificationCodeFn(ctx, email, code)
}

func (m *mockEmailProvider) IsEnabled() bool {
	return m.enabled
}

// --- Test helpers ---

const (
	testEmail    = "test@example.com"
	testDeviceID = "device-123"
	testIPAddr   = "192.168.1.1"
)

func newTestUser() *repository.User {
	email := testEmail
	displayName := "Test User"
	return &repository.User{
		ID:            uuid.New(),
		Email:         &email,
		EmailVerified: true,
		DisplayName:   &displayName,
		CreatedAt:     time.Now(),
		UpdatedAt:     time.Now(),
	}
}

func newTestVerificationCode(id uuid.UUID) *repository.VerificationCode {
	return &repository.VerificationCode{
		ID:        id,
		Email:     testEmail,
		CodeHash:  "somehash",
		CreatedAt: time.Now(),
		ExpiresAt: time.Now().Add(5 * time.Minute),
	}
}

// defaultMocks returns mocks pre-configured for the common success scenario.
func defaultMocks() (*mockUserRepo, *mockCodeRepo, *mockAttemptRepo, *mockJWTProvider, *mockEmailProvider) {
	user := newTestUser()
	codeID := uuid.New()

	userRepo := &mockUserRepo{
		findUserByProviderFn: func(ctx context.Context, provider, providerUserID string) (*repository.User, error) {
			return user, nil
		},
		createUserWithProviderFn: func(ctx context.Context, email, displayName string, emailVerified bool, provider, providerUserID string) (*repository.User, error) {
			return user, nil
		},
		saveRefreshTokenFn: func(ctx context.Context, userID uuid.UUID, token string, expiresAt time.Time) error {
			return nil
		},
		getUserAuthProvidersFn: func(ctx context.Context, userID uuid.UUID) ([]string, error) {
			return []string{"email"}, nil
		},
	}

	codeRepo := &mockCodeRepo{
		createVerificationCodeFn: func(ctx context.Context, email, code string, expiresAt time.Time) (*repository.VerificationCode, error) {
			return newTestVerificationCode(codeID), nil
		},
		findVerificationCodeFn: func(ctx context.Context, email, code string) (*repository.VerificationCode, error) {
			return newTestVerificationCode(codeID), nil
		},
		markCodeAsUsedFn: func(ctx context.Context, id uuid.UUID) error {
			return nil
		},
	}

	attemptRepo := &mockAttemptRepo{
		recordAttemptFn: func(ctx context.Context, email, deviceID, ipAddress string) error {
			return nil
		},
		hasRecentAttemptFn: func(ctx context.Context, email, deviceID, ipAddress string, cooldown time.Duration) (bool, error) {
			return false, nil
		},
		countRecentAttemptsFn: func(ctx context.Context, email string, window time.Duration) (int, error) {
			return 0, nil
		},
	}

	jwtProvider := &mockJWTProvider{
		generateAccessTokenFn: func(userID, email string) (string, error) {
			return "access-token", nil
		},
		generateRefreshTokenFn: func() (string, error) {
			return "refresh-token", nil
		},
		accessTokenLifetime:  15 * time.Minute,
		refreshTokenLifetime: 7 * 24 * time.Hour,
	}

	emailProvider := &mockEmailProvider{
		enabled: false,
		sendVerificationCodeFn: func(ctx context.Context, email string, code string) error {
			return nil
		},
	}

	return userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider
}

func newService(
	userRepo UserRepository,
	codeRepo VerificationCodeRepository,
	attemptRepo VerificationAttemptRepository,
	jwtProvider JWTProvider,
	emailProvider EmailProvider,
) *EmailAuthService {
	return NewEmailAuthService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider,
		3*time.Minute, // resendCooldown
		5,             // maxCodesPerHour
		true,          // ipRateLimitEnabled
	)
}

// --- SendVerificationCode tests ---

func TestSendVerificationCode_Success(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	err := svc.SendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
}

func TestSendVerificationCode_InvalidEmail(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	err := svc.SendVerificationCode(context.Background(), "not-an-email", testDeviceID, testIPAddr)
	if !errors.Is(err, ErrInvalidEmail) {
		t.Fatalf("expected ErrInvalidEmail, got: %v", err)
	}
}

func TestSendVerificationCode_RateLimited_RecentAttempt(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	attemptRepo.hasRecentAttemptFn = func(ctx context.Context, email, deviceID, ipAddress string, cooldown time.Duration) (bool, error) {
		return true, nil
	}
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	err := svc.SendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if !errors.Is(err, ErrRateLimitExceeded) {
		t.Fatalf("expected ErrRateLimitExceeded, got: %v", err)
	}
}

func TestSendVerificationCode_RateLimited_HourlyMax(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	const maxCodesPerHour = 5
	attemptRepo.countRecentAttemptsFn = func(ctx context.Context, email string, window time.Duration) (int, error) {
		return maxCodesPerHour, nil
	}
	svc := NewEmailAuthService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider,
		3*time.Minute, maxCodesPerHour, true)

	err := svc.SendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if !errors.Is(err, ErrRateLimitExceeded) {
		t.Fatalf("expected ErrRateLimitExceeded, got: %v", err)
	}
}

func TestSendVerificationCode_EmailDisabled_UsesHardcodedCode(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	emailProvider.enabled = false

	sendCalled := false
	emailProvider.sendVerificationCodeFn = func(ctx context.Context, email string, code string) error {
		sendCalled = true
		return nil
	}

	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	err := svc.SendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	if codeRepo.lastCreateCode != HardcodedVerificationCode {
		t.Errorf("expected code %q, got %q", HardcodedVerificationCode, codeRepo.lastCreateCode)
	}
	if !sendCalled {
		t.Error("expected SendVerificationCode to be called even when disabled (sender handles the no-op)")
	}
}

func TestSendVerificationCode_EmailEnabled_GeneratesRandomCode(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	emailProvider.enabled = true

	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	err := svc.SendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	code := codeRepo.lastCreateCode
	if len(code) != 6 {
		t.Errorf("expected 6-digit code, got %q (len=%d)", code, len(code))
	}
	for _, c := range code {
		if c < '0' || c > '9' {
			t.Errorf("code %q contains non-digit character %q", code, c)
		}
	}
}

func TestSendVerificationCode_EmailSendFailure(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	emailProvider.enabled = true
	emailProvider.sendVerificationCodeFn = func(ctx context.Context, email string, code string) error {
		return fmt.Errorf("smtp error")
	}

	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	err := svc.SendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if err == nil {
		t.Fatal("expected error from email send failure, got nil")
	}
}

func TestSendVerificationCode_IPRateLimitDisabled(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()

	// Record what IP is passed into these calls
	var hasRecentIP, recordIP string
	attemptRepo.hasRecentAttemptFn = func(ctx context.Context, email, deviceID, ipAddress string, cooldown time.Duration) (bool, error) {
		hasRecentIP = ipAddress
		return false, nil
	}
	attemptRepo.recordAttemptFn = func(ctx context.Context, email, deviceID, ipAddress string) error {
		recordIP = ipAddress
		return nil
	}

	svc := NewEmailAuthService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider,
		3*time.Minute, 5, false) // ipRateLimitEnabled = false

	err := svc.SendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	if hasRecentIP != "" {
		t.Errorf("expected empty ipAddress for HasRecentAttempt when IP rate limiting disabled, got %q", hasRecentIP)
	}
	if recordIP != "" {
		t.Errorf("expected empty ipAddress for RecordAttempt when IP rate limiting disabled, got %q", recordIP)
	}
}

// --- VerifyCode tests ---

func TestVerifyCode_Success(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	resp, err := svc.VerifyCode(context.Background(), testEmail, "123456")
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if resp == nil {
		t.Fatal("expected non-nil AuthResponse")
	}
	if resp.AccessToken != "access-token" {
		t.Errorf("unexpected access token: %q", resp.AccessToken)
	}
	if resp.RefreshToken != "refresh-token" {
		t.Errorf("unexpected refresh token: %q", resp.RefreshToken)
	}
	if resp.User == nil {
		t.Error("expected non-nil User in response")
	}
}

func TestVerifyCode_InvalidEmail(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	_, err := svc.VerifyCode(context.Background(), "not-an-email", "123456")
	if !errors.Is(err, ErrInvalidEmail) {
		t.Fatalf("expected ErrInvalidEmail, got: %v", err)
	}
}

func TestVerifyCode_InvalidCodeFormat(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	testCases := []string{"abc", "12345", "1234567", "abcdef", ""}
	for _, code := range testCases {
		_, err := svc.VerifyCode(context.Background(), testEmail, code)
		if !errors.Is(err, ErrInvalidCode) {
			t.Errorf("code %q: expected ErrInvalidCode, got: %v", code, err)
		}
	}
}

func TestVerifyCode_CodeNotFound(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	codeRepo.findVerificationCodeFn = func(ctx context.Context, email, code string) (*repository.VerificationCode, error) {
		return nil, repository.ErrVerificationCodeNotFound
	}
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	_, err := svc.VerifyCode(context.Background(), testEmail, "123456")
	if !errors.Is(err, ErrInvalidCode) {
		t.Fatalf("expected ErrInvalidCode, got: %v", err)
	}
}

func TestVerifyCode_CodeExpired(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	codeRepo.findVerificationCodeFn = func(ctx context.Context, email, code string) (*repository.VerificationCode, error) {
		return nil, repository.ErrVerificationCodeExpired
	}
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	_, err := svc.VerifyCode(context.Background(), testEmail, "123456")
	if !errors.Is(err, ErrCodeExpired) {
		t.Fatalf("expected ErrCodeExpired, got: %v", err)
	}
}

func TestVerifyCode_CodeAlreadyUsed(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	codeRepo.markCodeAsUsedFn = func(ctx context.Context, id uuid.UUID) error {
		return repository.ErrVerificationCodeUsed
	}
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	_, err := svc.VerifyCode(context.Background(), testEmail, "123456")
	if !errors.Is(err, ErrCodeAlreadyUsed) {
		t.Fatalf("expected ErrCodeAlreadyUsed, got: %v", err)
	}
}

func TestVerifyCode_NewUserCreated(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()

	newUser := newTestUser()
	createCalled := false

	userRepo.findUserByProviderFn = func(ctx context.Context, provider, providerUserID string) (*repository.User, error) {
		return nil, repository.ErrUserNotFound
	}
	userRepo.createUserWithProviderFn = func(ctx context.Context, email, displayName string, emailVerified bool, provider, providerUserID string) (*repository.User, error) {
		createCalled = true
		if email != testEmail {
			return nil, fmt.Errorf("unexpected email: %q", email)
		}
		return newUser, nil
	}

	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	resp, err := svc.VerifyCode(context.Background(), testEmail, "123456")
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if !createCalled {
		t.Error("expected CreateUserWithProvider to be called for new user")
	}
	if resp == nil {
		t.Fatal("expected non-nil AuthResponse")
	}
}

// --- Other tests ---

func TestGetResendCooldown(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	cooldown := 3 * time.Minute
	svc := NewEmailAuthService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider,
		cooldown, 5, true)

	got := svc.GetResendCooldown()
	expected := int(cooldown.Seconds())
	if got != expected {
		t.Errorf("expected %d, got %d", expected, got)
	}
}

func TestResendVerificationCode_DelegatesToSend(t *testing.T) {
	userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider := defaultMocks()
	svc := newService(userRepo, codeRepo, attemptRepo, jwtProvider, emailProvider)

	// ResendVerificationCode should succeed just like SendVerificationCode
	err := svc.ResendVerificationCode(context.Background(), testEmail, testDeviceID, testIPAddr)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}

	// Verify code was created (same path as SendVerificationCode)
	if codeRepo.lastCreateEmail != testEmail {
		t.Errorf("expected code created for %q, got %q", testEmail, codeRepo.lastCreateEmail)
	}
}
