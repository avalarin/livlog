package service

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"

	"github.com/avalarin/livlog/backend/internal/repository"
)

var (
	ErrInvalidDisplayName         = errors.New("display name must be between 1 and 50 characters")
	ErrTemplateNotFound           = errors.New("collection template not found")
	ErrOnboardingAlreadyCompleted = errors.New("onboarding already completed")
)

type OnboardingService struct {
	userRepo       *repository.UserRepository
	collectionRepo *repository.CollectionRepository
	entryRepo      *repository.EntryRepository
}

func NewOnboardingService(
	userRepo *repository.UserRepository,
	collectionRepo *repository.CollectionRepository,
	entryRepo *repository.EntryRepository,
) *OnboardingService {
	return &OnboardingService{
		userRepo:       userRepo,
		collectionRepo: collectionRepo,
		entryRepo:      entryRepo,
	}
}

// GetTemplates returns all collection templates.
func (s *OnboardingService) GetTemplates(
	ctx context.Context,
) ([]*repository.Collection, error) {
	return s.collectionRepo.GetTemplateCollections(ctx)
}

// UpdateDisplayName validates and updates the user's display name.
func (s *OnboardingService) UpdateDisplayName(
	ctx context.Context,
	userID uuid.UUID,
	displayName string,
) error {
	displayName = strings.TrimSpace(displayName)
	if len(displayName) < 1 || len(displayName) > 50 {
		return ErrInvalidDisplayName
	}

	if err := s.userRepo.UpdateDisplayName(ctx, userID, displayName); err != nil {
		return fmt.Errorf("failed to update display name: %w", err)
	}

	return nil
}

// CreateCollectionFromTemplate creates a new collection from a template,
// optionally copying the template's entries.
func (s *OnboardingService) CreateCollectionFromTemplate(
	ctx context.Context,
	userID uuid.UUID,
	templateSlug string,
	includeEntries bool,
) (*repository.Collection, error) {
	template, err := s.collectionRepo.GetTemplateBySlug(ctx, templateSlug)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			return nil, ErrTemplateNotFound
		}
		return nil, fmt.Errorf("failed to get template: %w", err)
	}

	newCollection, err := s.collectionRepo.CreateCollection(
		ctx, userID, template.Name, template.Icon, template.Color, template.AllowedEntryTypes,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create collection from template: %w", err)
	}

	if includeEntries {
		_, err = s.entryRepo.CopyTemplateEntries(ctx, template.ID, newCollection.ID, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to copy template entries: %w", err)
		}
	}

	return newCollection, nil
}

// CompleteOnboarding marks onboarding as completed for the user.
func (s *OnboardingService) CompleteOnboarding(
	ctx context.Context,
	userID uuid.UUID,
) error {
	user, err := s.userRepo.GetUserByID(ctx, userID)
	if err != nil {
		return fmt.Errorf("failed to get user: %w", err)
	}
	if user.OnboardingCompleted {
		return ErrOnboardingAlreadyCompleted
	}

	if err := s.userRepo.CompleteOnboarding(ctx, userID); err != nil {
		return fmt.Errorf("failed to complete onboarding: %w", err)
	}

	return nil
}
