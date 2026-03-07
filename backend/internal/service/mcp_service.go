package service

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"

	"github.com/avalarin/livlog/backend/internal/repository"
)

type MCPStatus struct {
	Enabled bool
	URL     string // empty if not enabled
}

type MCPService struct {
	mcpRepo       *repository.MCPRepository
	publicBaseURL string // full base URL, e.g. "https://prod.example.com"
}

func NewMCPService(mcpRepo *repository.MCPRepository, publicBaseURL string) *MCPService {
	return &MCPService{
		mcpRepo:       mcpRepo,
		publicBaseURL: strings.TrimRight(publicBaseURL, "/"),
	}
}

// BuildMCPURL constructs the full MCP endpoint URL for a given unique code.
func (s *MCPService) BuildMCPURL(uniqueCode string) string {
	return fmt.Sprintf("%s/api/mcp/%s", s.publicBaseURL, uniqueCode)
}

// generateUniqueCode generates a cryptographically random 64-character hex string.
func generateUniqueCode() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("failed to generate unique code: %w", err)
	}
	return hex.EncodeToString(bytes), nil
}

// GetStatus returns the current MCP integration status for a user.
func (s *MCPService) GetStatus(ctx context.Context, userID uuid.UUID) (*MCPStatus, error) {
	integration, err := s.mcpRepo.GetByUserID(ctx, userID)
	if err != nil {
		if errors.Is(err, repository.ErrMCPNotFound) {
			return &MCPStatus{Enabled: false}, nil
		}
		return nil, fmt.Errorf("failed to get mcp status: %w", err)
	}

	return &MCPStatus{
		Enabled: true,
		URL:     s.BuildMCPURL(integration.UniqueCode),
	}, nil
}

// Enable creates or replaces the MCP integration for a user atomically.
// Each call generates a new unique_code, invalidating any previously issued URL.
func (s *MCPService) Enable(ctx context.Context, userID uuid.UUID) (*MCPStatus, error) {
	uniqueCode, err := generateUniqueCode()
	if err != nil {
		return nil, err
	}

	integration, err := s.mcpRepo.Upsert(ctx, userID, uniqueCode)
	if err != nil {
		return nil, fmt.Errorf("failed to enable mcp integration: %w", err)
	}

	return &MCPStatus{
		Enabled: true,
		URL:     s.BuildMCPURL(integration.UniqueCode),
	}, nil
}

// Disable removes the MCP integration for a user.
func (s *MCPService) Disable(ctx context.Context, userID uuid.UUID) error {
	return s.mcpRepo.DeleteByUserID(ctx, userID)
}

// GetUserIDByCode looks up a user by their MCP unique_code.
func (s *MCPService) GetUserIDByCode(ctx context.Context, uniqueCode string) (uuid.UUID, error) {
	integration, err := s.mcpRepo.GetByUniqueCode(ctx, uniqueCode)
	if err != nil {
		return uuid.UUID{}, err
	}
	return integration.UserID, nil
}
