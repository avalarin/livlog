package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/google/uuid"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
)

type AuthService struct {
	userRepo      *repository.UserRepository
	appleVerifier *AppleVerifier
	jwtService    *JWTService
}

type PersonNameComponents struct {
	GivenName  *string `json:"given_name,omitempty"`
	FamilyName *string `json:"family_name,omitempty"`
}

type AppleAuthRequest struct {
	IdentityToken     string                `json:"identity_token"`
	AuthorizationCode *string               `json:"authorization_code,omitempty"`
	FullName          *PersonNameComponents `json:"full_name,omitempty"`
	Email             *string               `json:"email,omitempty"`
}

type AuthResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	User         *User  `json:"user"`
}

type User struct {
	ID            string   `json:"id"`
	Email         *string  `json:"email,omitempty"`
	EmailVerified bool     `json:"email_verified"`
	DisplayName   *string  `json:"display_name,omitempty"`
	AuthProviders []string `json:"auth_providers"`
	CreatedAt     string   `json:"created_at"`
	UpdatedAt     *string  `json:"updated_at,omitempty"`
}

func NewAuthService(
	userRepo *repository.UserRepository,
	appleVerifier *AppleVerifier,
	jwtService *JWTService,
) *AuthService {
	return &AuthService{
		userRepo:      userRepo,
		appleVerifier: appleVerifier,
		jwtService:    jwtService,
	}
}

func (s *AuthService) AuthenticateWithApple(ctx context.Context, req *AppleAuthRequest) (*AuthResponse, error) {
	// Verify Apple identity token
	claims, err := s.appleVerifier.VerifyIdentityToken(req.IdentityToken)
	if err != nil {
		return nil, fmt.Errorf("failed to verify Apple token: %w", err)
	}

	appleUserID := claims.Sub
	email := claims.Email
	emailVerified := claims.EmailVerified

	// Try to find existing user
	user, err := s.userRepo.FindUserByProvider(ctx, "apple", appleUserID)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			// Register new user
			user, err = s.registerNewAppleUser(ctx, req, appleUserID, email, emailVerified)
			if err != nil {
				return nil, fmt.Errorf("failed to register user: %w", err)
			}
		} else {
			return nil, fmt.Errorf("failed to find user: %w", err)
		}
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

func (s *AuthService) RefreshToken(ctx context.Context, refreshToken string) (*AuthResponse, error) {
	// Find refresh token
	token, err := s.userRepo.FindRefreshToken(ctx, refreshToken)
	if err != nil {
		if errors.Is(err, repository.ErrRefreshTokenNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, fmt.Errorf("failed to find refresh token: %w", err)
	}

	// Get user
	user, err := s.userRepo.GetUserByID(ctx, token.UserID)
	if err != nil {
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	// Generate new tokens
	accessToken, err := s.jwtService.GenerateAccessToken(user.ID.String(), getEmailString(user.Email))
	if err != nil {
		return nil, fmt.Errorf("failed to generate access token: %w", err)
	}

	newRefreshToken, err := s.jwtService.GenerateRefreshToken()
	if err != nil {
		return nil, fmt.Errorf("failed to generate refresh token: %w", err)
	}

	// Revoke old refresh token
	if err := s.userRepo.RevokeRefreshToken(ctx, refreshToken); err != nil {
		return nil, fmt.Errorf("failed to revoke old token: %w", err)
	}

	// Save new refresh token
	expiresAt := time.Now().Add(s.jwtService.GetRefreshTokenLifetime())
	if err := s.userRepo.SaveRefreshToken(ctx, user.ID, newRefreshToken, expiresAt); err != nil {
		return nil, fmt.Errorf("failed to save new refresh token: %w", err)
	}

	// Get auth providers
	providers, err := s.userRepo.GetUserAuthProviders(ctx, user.ID)
	if err != nil {
		return nil, fmt.Errorf("failed to get auth providers: %w", err)
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: newRefreshToken,
		ExpiresIn:    int(s.jwtService.GetAccessTokenLifetime().Seconds()),
		User:         mapUserToResponse(user, providers),
	}, nil
}

func (s *AuthService) Logout(ctx context.Context, refreshToken string) error {
	if err := s.userRepo.RevokeRefreshToken(ctx, refreshToken); err != nil {
		if errors.Is(err, repository.ErrRefreshTokenNotFound) {
			// Token already revoked or doesn't exist - not an error for logout
			return nil
		}
		return fmt.Errorf("failed to revoke token: %w", err)
	}
	return nil
}

func (s *AuthService) GetUserByID(ctx context.Context, userID string) (*User, error) {
	id, err := uuid.Parse(userID)
	if err != nil {
		return nil, fmt.Errorf("invalid user ID: %w", err)
	}

	user, err := s.userRepo.GetUserByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("failed to get user: %w", err)
	}

	providers, err := s.userRepo.GetUserAuthProviders(ctx, user.ID)
	if err != nil {
		return nil, fmt.Errorf("failed to get auth providers: %w", err)
	}

	return mapUserToResponse(user, providers), nil
}

func (s *AuthService) DeleteAccount(ctx context.Context, userID string) error {
	id, err := uuid.Parse(userID)
	if err != nil {
		return fmt.Errorf("invalid user ID: %w", err)
	}

	// Revoke all tokens
	if err := s.userRepo.RevokeAllUserTokens(ctx, id); err != nil {
		return fmt.Errorf("failed to revoke tokens: %w", err)
	}

	// Soft delete user (cascades to auth providers via DB)
	if err := s.userRepo.DeleteUser(ctx, id); err != nil {
		return fmt.Errorf("failed to delete user: %w", err)
	}

	return nil
}

// Helper functions

func (s *AuthService) registerNewAppleUser(
	ctx context.Context,
	req *AppleAuthRequest,
	appleUserID, email string,
	emailVerified bool,
) (*repository.User, error) {
	// Build display name from Apple's full name if available
	displayName := buildDisplayName(req.FullName)

	// Use provided email if available, otherwise use email from token
	userEmail := email
	if req.Email != nil && *req.Email != "" {
		userEmail = *req.Email
	}

	// Create user with auth provider in a transaction
	user, err := s.userRepo.CreateUserWithProvider(
		ctx,
		userEmail,
		displayName,
		emailVerified,
		"apple",
		appleUserID,
	)
	if err != nil {
		return nil, err
	}

	return user, nil
}

func buildDisplayName(fullName *PersonNameComponents) string {
	if fullName == nil {
		return ""
	}

	var name string
	if fullName.GivenName != nil && *fullName.GivenName != "" {
		name = *fullName.GivenName
	}
	if fullName.FamilyName != nil && *fullName.FamilyName != "" {
		if name != "" {
			name += " "
		}
		name += *fullName.FamilyName
	}
	return name
}

func mapUserToResponse(user *repository.User, providers []string) *User {
	updatedAt := user.UpdatedAt.Format(time.RFC3339)
	return &User{
		ID:            user.ID.String(),
		Email:         user.Email,
		EmailVerified: user.EmailVerified,
		DisplayName:   user.DisplayName,
		AuthProviders: providers,
		CreatedAt:     user.CreatedAt.Format(time.RFC3339),
		UpdatedAt:     &updatedAt,
	}
}

func getEmailString(email *string) string {
	if email == nil {
		return ""
	}
	return *email
}
