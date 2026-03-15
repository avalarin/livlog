package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/avalarin/livlog/backend/internal/repository"
)

var (
	ErrInvalidCollectionName = errors.New("collection name must be between 1 and 50 characters")
	ErrInvalidIcon           = errors.New("icon must start with 'system:' or 'emoji:' and be at most 50 characters")
	ErrInvalidColor          = errors.New("invalid color value")
	ErrCollectionHasEntries  = errors.New("cannot delete collection with entries")
	ErrNotCollectionOwner    = errors.New("you must be the collection owner to perform this action")
	ErrLastOwner             = repository.ErrLastOwner
	ErrAlreadyMember         = repository.ErrAlreadyMember
	ErrAlreadyHasCollections = errors.New("user already has collections")
)

var validSystemIcons = map[string]struct{}{
	"bookmark":        {},
	"music":           {},
	"price-tag":       {},
	"user":            {},
	"male-user":       {},
	"gift":            {},
	"music-library":   {},
	"cymbals":         {},
	"image":           {},
	"music-record":    {},
	"cameras":         {},
	"albums":          {},
	"flash-on":        {},
	"radio-waves":     {},
	"musical-note":    {},
	"briefcase":       {},
	"folder":          {},
	"movie":           {},
	"beach-umbrella":  {},
	"books":           {},
	"cafe":            {},
	"coffee-beans":    {},
	"game-controller": {},
	"layers":          {},
	"place-marker":    {},
	"umbrella":        {},
	"wine-glass":      {},
}

var validColors = map[string]struct{}{
	"dodger-blue":   {},
	"dusty-grape":   {},
	"straw-gold":    {},
	"rosewood":      {},
	"coral-glow":    {},
	"vibrant-coral": {},
	"vintage-grape": {},
	"yellow-green":  {},
	"granite":       {},
	"verdigris":     {},
}

type CollectionService struct {
	collectionRepo *repository.CollectionRepository
	userRepo       *repository.UserRepository
}

func NewCollectionService(
	collectionRepo *repository.CollectionRepository,
	userRepo *repository.UserRepository,
) *CollectionService {
	return &CollectionService{
		collectionRepo: collectionRepo,
		userRepo:       userRepo,
	}
}

// CreateCollection creates a new collection with validation
func (s *CollectionService) CreateCollection(
	ctx context.Context,
	userID uuid.UUID,
	name, icon, color string,
) (*repository.Collection, error) {
	// Validate name
	name = strings.TrimSpace(name)
	if len(name) < 1 || len(name) > 50 {
		return nil, ErrInvalidCollectionName
	}

	// Validate icon
	icon = strings.TrimSpace(icon)
	if err := validateIcon(icon); err != nil {
		return nil, err
	}

	// Validate color
	color = strings.TrimSpace(color)
	if err := validateColor(color); err != nil {
		return nil, err
	}

	return s.collectionRepo.CreateCollection(ctx, userID, name, icon, color)
}

// GetCollectionsByUserID retrieves all collections for a user
func (s *CollectionService) GetCollectionsByUserID(
	ctx context.Context,
	userID uuid.UUID,
) ([]*repository.Collection, error) {
	return s.collectionRepo.GetCollectionsByUserID(ctx, userID)
}

// GetCollectionByID retrieves a single collection, verifying the user has access.
func (s *CollectionService) GetCollectionByID(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) (*repository.Collection, error) {
	return s.collectionRepo.GetCollectionByID(ctx, id, userID)
}

// UpdateCollection updates a collection with validation — only owners may update.
func (s *CollectionService) UpdateCollection(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
	name, icon, color string,
) (*repository.Collection, error) {
	// Verify requester is owner
	role, err := s.collectionRepo.GetUserRole(ctx, id, userID)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			return nil, repository.ErrCollectionNotFound
		}
		return nil, fmt.Errorf("failed to get user role: %w", err)
	}
	if role != "owner" {
		return nil, ErrNotCollectionOwner
	}

	// Validate name
	name = strings.TrimSpace(name)
	if len(name) < 1 || len(name) > 50 {
		return nil, ErrInvalidCollectionName
	}

	// Validate icon
	icon = strings.TrimSpace(icon)
	if err := validateIcon(icon); err != nil {
		return nil, err
	}

	// Validate color
	color = strings.TrimSpace(color)
	if err := validateColor(color); err != nil {
		return nil, err
	}

	if _, err := s.collectionRepo.UpdateCollection(ctx, id, name, icon, color); err != nil {
		return nil, err
	}

	// Re-fetch with role and member count populated
	return s.collectionRepo.GetCollectionByID(ctx, id, userID)
}

// DeleteCollection removes the user from the collection (self-remove from collection_shares).
// The collection row stays even if no members remain.
func (s *CollectionService) DeleteCollection(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) error {
	return s.RemoveShare(ctx, id, userID, userID)
}

// GetMembers returns the members of a collection. The requester must have access.
func (s *CollectionService) GetMembers(
	ctx context.Context,
	collectionID, requesterID uuid.UUID,
) ([]*repository.CollectionMember, error) {
	// Verify requester has access
	_, err := s.collectionRepo.GetCollectionByID(ctx, collectionID, requesterID)
	if err != nil {
		return nil, err
	}

	return s.collectionRepo.GetCollectionMembers(ctx, collectionID)
}

// AddShare invites a user (by email) to a collection. Only owners may invite.
func (s *CollectionService) AddShare(
	ctx context.Context,
	collectionID, requesterID uuid.UUID,
	email, role string,
) error {
	// Verify requester is owner
	requesterRole, err := s.collectionRepo.GetUserRole(ctx, collectionID, requesterID)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			return repository.ErrCollectionNotFound
		}
		return fmt.Errorf("failed to get user role: %w", err)
	}
	if requesterRole != "owner" {
		return ErrNotCollectionOwner
	}

	// Look up invitee by email
	invitee, err := s.userRepo.GetUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			return repository.ErrUserNotFound
		}
		return fmt.Errorf("failed to find user: %w", err)
	}

	return s.collectionRepo.AddCollectionShare(ctx, collectionID, requesterID, invitee.ID, role)
}

// RemoveShare removes a user from a collection.
// Users may remove themselves; only owners may remove others.
// The last-owner guard is enforced atomically in the repository.
func (s *CollectionService) RemoveShare(
	ctx context.Context,
	collectionID, requesterID, targetUserID uuid.UUID,
) error {
	// If removing someone else, requester must be owner.
	if requesterID != targetUserID {
		requesterRole, err := s.collectionRepo.GetUserRole(ctx, collectionID, requesterID)
		if err != nil {
			if errors.Is(err, repository.ErrCollectionNotFound) {
				return repository.ErrCollectionNotFound
			}
			return fmt.Errorf("failed to get user role: %w", err)
		}
		if requesterRole != "owner" {
			return ErrNotCollectionOwner
		}
	}

	// The repo enforces the last-owner guard within a single transaction.
	return s.collectionRepo.RemoveCollectionShare(ctx, collectionID, targetUserID)
}

// UpdateShare changes a user's permission level in a collection. Only owners may update.
func (s *CollectionService) UpdateShare(
	ctx context.Context,
	collectionID, requesterID, targetUserID uuid.UUID,
	newRole string,
) error {
	// Verify requester is owner
	requesterRole, err := s.collectionRepo.GetUserRole(ctx, collectionID, requesterID)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			return repository.ErrCollectionNotFound
		}
		return fmt.Errorf("failed to get user role: %w", err)
	}
	if requesterRole != "owner" {
		return ErrNotCollectionOwner
	}

	return s.collectionRepo.UpdateCollectionShare(ctx, collectionID, targetUserID, newRole)
}

// validateIcon checks that the icon string uses a recognized prefix and a valid name/content.
func validateIcon(icon string) error {
	if len(icon) < 1 || len(icon) > 50 {
		return ErrInvalidIcon
	}
	if strings.HasPrefix(icon, "system:") {
		name := strings.TrimPrefix(icon, "system:")
		if _, ok := validSystemIcons[name]; !ok {
			return ErrInvalidIcon
		}
		return nil
	}
	if strings.HasPrefix(icon, "emoji:") {
		content := strings.TrimPrefix(icon, "emoji:")
		runeCount := utf8.RuneCountInString(content)
		if runeCount < 1 || runeCount > 10 {
			return ErrInvalidIcon
		}
		return nil
	}
	return ErrInvalidIcon
}

// validateColor checks that the color is one of the allowed values.
func validateColor(color string) error {
	if _, ok := validColors[color]; !ok {
		return ErrInvalidColor
	}
	return nil
}

// CreateDefaultCollections creates default collections if user has none
func (s *CollectionService) CreateDefaultCollections(
	ctx context.Context,
	userID uuid.UUID,
) ([]*repository.Collection, error) {
	// Check if user already has collections
	hasCollections, err := s.collectionRepo.HasCollections(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to check collections: %w", err)
	}

	if hasCollections {
		return nil, ErrAlreadyHasCollections
	}

	return s.collectionRepo.CreateDefaultCollections(ctx, userID)
}
