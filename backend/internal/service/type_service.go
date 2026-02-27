package service

import (
	"context"
	"errors"
	"strings"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/google/uuid"
)

var (
	ErrInvalidTypeName = errors.New("type name must be between 1 and 50 characters")
	ErrInvalidTypeIcon = errors.New("icon must be between 1 and 20 characters")
)

type TypeService struct {
	typeRepo *repository.TypeRepository
}

func NewTypeService(typeRepo *repository.TypeRepository) *TypeService {
	return &TypeService{typeRepo: typeRepo}
}

// GetAllTypes returns system types plus the user's own types.
func (s *TypeService) GetAllTypes(
	ctx context.Context,
	userID uuid.UUID,
) ([]*repository.EntryType, error) {
	return s.typeRepo.GetAllTypes(ctx, userID)
}

// GetTypeByID returns a type if it is a system type or owned by the given user.
func (s *TypeService) GetTypeByID(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) (*repository.EntryType, error) {
	t, err := s.typeRepo.GetTypeByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// System types (user_id == nil) are visible to everyone
	if t.UserID != nil && *t.UserID != userID {
		return nil, repository.ErrTypeNotFound
	}

	return t, nil
}

// CreateType creates a new user-owned entry type with validation.
func (s *TypeService) CreateType(
	ctx context.Context,
	userID uuid.UUID,
	name, icon string,
) (*repository.EntryType, error) {
	name = strings.TrimSpace(name)
	if len(name) < 1 || len(name) > 50 {
		return nil, ErrInvalidTypeName
	}

	icon = strings.TrimSpace(icon)
	if len(icon) < 1 || len(icon) > 20 {
		return nil, ErrInvalidTypeIcon
	}

	return s.typeRepo.CreateType(ctx, &userID, name, icon)
}
