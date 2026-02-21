package service

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/google/uuid"
)

var (
	ErrInvalidTitle       = errors.New("title must be between 1 and 200 characters")
	ErrInvalidDescription = errors.New("description must be between 1 and 2000 characters")
	ErrInvalidScore       = errors.New("score must be between 0 and 3")
)

type EntryService struct {
	entryRepo      *repository.EntryRepository
	collectionRepo *repository.CollectionRepository
}

func NewEntryService(
	entryRepo *repository.EntryRepository,
	collectionRepo *repository.CollectionRepository,
) *EntryService {
	return &EntryService{
		entryRepo:      entryRepo,
		collectionRepo: collectionRepo,
	}
}

// CreateEntry creates a new entry with validation
func (s *EntryService) CreateEntry(
	ctx context.Context,
	userID uuid.UUID,
	collectionID *uuid.UUID,
	title, description string,
	score int,
	date time.Time,
	additionalFields map[string]string,
	images []repository.EntryImage,
) (*repository.Entry, error) {
	// Validate title
	title = strings.TrimSpace(title)
	if len(title) < 1 || len(title) > 200 {
		return nil, ErrInvalidTitle
	}

	// Validate description
	description = strings.TrimSpace(description)
	if len(description) < 1 || len(description) > 2000 {
		return nil, ErrInvalidDescription
	}

	// Validate score
	if score < 0 || score > 3 {
		return nil, ErrInvalidScore
	}

	// Validate collection ownership if provided
	if collectionID != nil {
		collection, err := s.collectionRepo.GetCollectionByID(ctx, *collectionID)
		if err != nil {
			return nil, fmt.Errorf("invalid collection: %w", err)
		}
		if collection.UserID != userID {
			return nil, repository.ErrCollectionNotFound
		}
	}

	// Create entry
	entry, err := s.entryRepo.CreateEntry(
		ctx,
		userID,
		collectionID,
		title,
		description,
		score,
		date,
		additionalFields,
	)
	if err != nil {
		return nil, err
	}

	// Save images if provided
	if len(images) > 0 {
		// Set entry_id for all images
		for i := range images {
			images[i].EntryID = entry.ID
		}
		if err := s.entryRepo.SaveEntryImages(ctx, entry.ID, images); err != nil {
			return nil, fmt.Errorf("failed to save images: %w", err)
		}
	}

	return entry, nil
}

// GetEntriesByUserID retrieves entries with pagination
func (s *EntryService) GetEntriesByUserID(
	ctx context.Context,
	userID uuid.UUID,
	collectionID *uuid.UUID,
	limit, offset int,
) ([]*repository.Entry, error) {
	// Default pagination
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}

	return s.entryRepo.GetEntriesByUserID(ctx, userID, collectionID, limit, offset)
}

// GetEntryByID retrieves a single entry
func (s *EntryService) GetEntryByID(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) (*repository.Entry, error) {
	entry, err := s.entryRepo.GetEntryByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Check ownership
	if entry.UserID != userID {
		return nil, repository.ErrEntryNotFound
	}

	return entry, nil
}

// UpdateEntry updates an entry with validation
func (s *EntryService) UpdateEntry(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
	collectionID *uuid.UUID,
	title, description string,
	score int,
	date time.Time,
	additionalFields map[string]string,
	images []repository.EntryImage,
) (*repository.Entry, error) {
	// Check ownership
	_, err := s.GetEntryByID(ctx, id, userID)
	if err != nil {
		return nil, err
	}

	// Validate title
	title = strings.TrimSpace(title)
	if len(title) < 1 || len(title) > 200 {
		return nil, ErrInvalidTitle
	}

	// Validate description
	description = strings.TrimSpace(description)
	if len(description) < 1 || len(description) > 2000 {
		return nil, ErrInvalidDescription
	}

	// Validate score
	if score < 0 || score > 3 {
		return nil, ErrInvalidScore
	}

	// Validate collection ownership if provided
	if collectionID != nil {
		collection, err := s.collectionRepo.GetCollectionByID(ctx, *collectionID)
		if err != nil {
			return nil, fmt.Errorf("invalid collection: %w", err)
		}
		if collection.UserID != userID {
			return nil, repository.ErrCollectionNotFound
		}
	}

	// Update entry
	entry, err := s.entryRepo.UpdateEntry(
		ctx,
		id,
		collectionID,
		title,
		description,
		score,
		date,
		additionalFields,
	)
	if err != nil {
		return nil, err
	}

	// Update images if provided
	if images != nil {
		// Set entry_id for all images
		for i := range images {
			images[i].EntryID = entry.ID
		}
		if err := s.entryRepo.SaveEntryImages(ctx, entry.ID, images); err != nil {
			return nil, fmt.Errorf("failed to update images: %w", err)
		}
	}

	return entry, nil
}

// DeleteEntry deletes an entry
func (s *EntryService) DeleteEntry(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) error {
	// Check ownership
	_, err := s.GetEntryByID(ctx, id, userID)
	if err != nil {
		return err
	}

	return s.entryRepo.DeleteEntry(ctx, id)
}

// GetImageByID retrieves a single image by ID, validating user ownership
func (s *EntryService) GetImageByID(
	ctx context.Context,
	imageID uuid.UUID,
	userID uuid.UUID,
) (*repository.EntryImage, error) {
	img, err := s.entryRepo.GetImageByID(ctx, imageID)
	if err != nil {
		return nil, err
	}

	// Check ownership via parent entry
	_, err = s.GetEntryByID(ctx, img.EntryID, userID)
	if err != nil {
		return nil, err
	}

	return img, nil
}

// GetEntryImageMetas returns image metadata for a single entry
func (s *EntryService) GetEntryImageMetas(
	ctx context.Context,
	entryID uuid.UUID,
) ([]repository.ImageMeta, error) {
	return s.entryRepo.GetEntryImageMetas(ctx, entryID)
}

// GetImageMetasByEntryIDs returns a map of entry ID -> image metadata for multiple entries
func (s *EntryService) GetImageMetasByEntryIDs(
	ctx context.Context,
	entryIDs []uuid.UUID,
) (map[uuid.UUID][]repository.ImageMeta, error) {
	return s.entryRepo.GetImageMetasByEntryIDs(ctx, entryIDs)
}

// SearchEntries searches entries by query
func (s *EntryService) SearchEntries(
	ctx context.Context,
	userID uuid.UUID,
	query string,
	limit, offset int,
) ([]*repository.Entry, error) {
	// Default pagination
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}

	query = strings.TrimSpace(query)
	if query == "" {
		return s.GetEntriesByUserID(ctx, userID, nil, limit, offset)
	}

	return s.entryRepo.SearchEntries(ctx, userID, query, limit, offset)
}
