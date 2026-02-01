package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/google/uuid"
)

var (
	ErrInvalidCollectionName = errors.New("collection name must be between 1 and 50 characters")
	ErrInvalidIcon           = errors.New("icon must be between 1 and 20 characters")
	ErrCollectionHasEntries  = errors.New("cannot delete collection with entries")
)

type CollectionService struct {
	collectionRepo *repository.CollectionRepository
}

func NewCollectionService(collectionRepo *repository.CollectionRepository) *CollectionService {
	return &CollectionService{
		collectionRepo: collectionRepo,
	}
}

// CreateCollection creates a new collection with validation
func (s *CollectionService) CreateCollection(
	ctx context.Context,
	userID uuid.UUID,
	name, icon string,
) (*repository.Collection, error) {
	// Validate name
	name = strings.TrimSpace(name)
	if len(name) < 1 || len(name) > 50 {
		return nil, ErrInvalidCollectionName
	}

	// Validate icon
	icon = strings.TrimSpace(icon)
	if len(icon) < 1 || len(icon) > 20 {
		return nil, ErrInvalidIcon
	}

	return s.collectionRepo.CreateCollection(ctx, userID, name, icon)
}

// GetCollectionsByUserID retrieves all collections for a user
func (s *CollectionService) GetCollectionsByUserID(
	ctx context.Context,
	userID uuid.UUID,
) ([]*repository.Collection, error) {
	return s.collectionRepo.GetCollectionsByUserID(ctx, userID)
}

// GetCollectionByID retrieves a single collection
func (s *CollectionService) GetCollectionByID(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) (*repository.Collection, error) {
	collection, err := s.collectionRepo.GetCollectionByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Check ownership
	if collection.UserID != userID {
		return nil, repository.ErrCollectionNotFound
	}

	return collection, nil
}

// UpdateCollection updates a collection with validation
func (s *CollectionService) UpdateCollection(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
	name, icon string,
) (*repository.Collection, error) {
	// Check ownership first
	existing, err := s.GetCollectionByID(ctx, id, userID)
	if err != nil {
		return nil, err
	}

	// Validate name
	name = strings.TrimSpace(name)
	if len(name) < 1 || len(name) > 50 {
		return nil, ErrInvalidCollectionName
	}

	// Validate icon
	icon = strings.TrimSpace(icon)
	if len(icon) < 1 || len(icon) > 20 {
		return nil, ErrInvalidIcon
	}

	// Ensure we're updating the right user's collection
	_ = existing

	return s.collectionRepo.UpdateCollection(ctx, id, name, icon)
}

// DeleteCollection deletes a collection
func (s *CollectionService) DeleteCollection(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) error {
	// Check ownership
	_, err := s.GetCollectionByID(ctx, id, userID)
	if err != nil {
		return err
	}

	return s.collectionRepo.DeleteCollection(ctx, id)
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
		return nil, errors.New("user already has collections")
	}

	return s.collectionRepo.CreateDefaultCollections(ctx, userID)
}
