package service

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/avalarin/livlog/backend/internal/repository"
)

var (
	ErrInvalidTitle       = errors.New("title must be between 1 and 200 characters")
	ErrInvalidDescription = errors.New("description must be between 1 and 2000 characters")
	ErrInvalidScore       = errors.New("score must be between 0 and 3")
	ErrInvalidFieldValue  = errors.New("additional field has invalid value for its type")
)

type EntryService struct {
	entryRepo      *repository.EntryRepository
	collectionRepo *repository.CollectionRepository
	typeRepo       *repository.TypeRepository
}

func NewEntryService(
	entryRepo *repository.EntryRepository,
	collectionRepo *repository.CollectionRepository,
	typeRepo *repository.TypeRepository,
) *EntryService {
	return &EntryService{
		entryRepo:      entryRepo,
		collectionRepo: collectionRepo,
		typeRepo:       typeRepo,
	}
}

// validateAdditionalFields checks that number-typed fields contain parseable numeric values.
// Unknown field keys are silently ignored for forward compatibility.
func (s *EntryService) validateAdditionalFields(
	ctx context.Context,
	typeID *uuid.UUID,
	additionalFields map[string]string,
) error {
	if typeID == nil || len(additionalFields) == 0 {
		return nil
	}

	entryType, err := s.typeRepo.GetTypeByID(ctx, *typeID)
	if err != nil {
		return fmt.Errorf("failed to fetch type for field validation: %w", err)
	}

	fieldsByKey := make(map[string]repository.FieldDefinition, len(entryType.Fields))
	for _, f := range entryType.Fields {
		fieldsByKey[f.Key] = f
	}

	for key, value := range additionalFields {
		fieldDef, known := fieldsByKey[key]
		if !known || value == "" {
			continue
		}
		if fieldDef.Type == "number" {
			if _, err := strconv.ParseFloat(value, 64); err != nil {
				return fmt.Errorf("%w: field %q expects a number", ErrInvalidFieldValue, key)
			}
		}
	}

	return nil
}

// CreateEntry creates a new entry with validation
func (s *EntryService) CreateEntry(
	ctx context.Context,
	userID uuid.UUID,
	collectionID *uuid.UUID,
	typeID *uuid.UUID,
	title, description string,
	score int,
	date time.Time,
	additionalFields map[string]string,
	images []repository.EntryImage,
	seedImageIDs []uuid.UUID,
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

	// Validate additional field values against the type's field schema
	if err := s.validateAdditionalFields(ctx, typeID, additionalFields); err != nil {
		return nil, err
	}

	// Validate collection access and write permission if provided
	if collectionID != nil {
		role, err := s.collectionRepo.GetUserRole(ctx, *collectionID, userID)
		if err != nil {
			return nil, fmt.Errorf("invalid collection: %w", err)
		}
		if role == "read" {
			return nil, ErrNotCollectionOwner
		}
	}

	// Create entry
	entry, err := s.entryRepo.CreateEntry(
		ctx,
		userID,
		collectionID,
		typeID,
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
	} else if len(seedImageIDs) > 0 {
		if err := s.entryRepo.CopySeedImagesToEntry(ctx, entry.ID, seedImageIDs); err != nil {
			return nil, fmt.Errorf("failed to copy seed images: %w", err)
		}
	}

	// Refresh collection statistics cache (best-effort).
	if collectionID != nil {
		_ = s.collectionRepo.RefreshCollectionStatistics(ctx, *collectionID)
	}

	return entry, nil
}

// GetSeedImageByID returns a seed image by its fixed UUID without user ownership check.
func (s *EntryService) GetSeedImageByID(ctx context.Context, imageID uuid.UUID) (*repository.EntryImage, error) {
	return s.entryRepo.GetSeedImageByID(ctx, imageID)
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

// GetEntryByID retrieves a single entry.
// Access is granted to the entry's creator or to any member of the entry's collection.
func (s *EntryService) GetEntryByID(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) (*repository.Entry, error) {
	entry, err := s.entryRepo.GetEntryByID(ctx, id)
	if err != nil {
		return nil, err
	}

	if entry.UserID == userID {
		return entry, nil
	}

	// Allow access if the user is a member of the entry's collection.
	if entry.CollectionID != nil {
		if _, err := s.collectionRepo.GetUserRole(ctx, *entry.CollectionID, userID); err == nil {
			return entry, nil
		}
	}

	return nil, repository.ErrEntryNotFound
}

// UpdateEntry updates an entry with validation
func (s *EntryService) UpdateEntry(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
	collectionID *uuid.UUID,
	typeID *uuid.UUID,
	title, description string,
	score int,
	date time.Time,
	additionalFields map[string]string,
	images []repository.EntryImage,
) (*repository.Entry, error) {
	// Fetch at repo level to check access against the entry's current collection.
	existing, err := s.entryRepo.GetEntryByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Verify the caller may write to the entry's current collection.
	if existing.CollectionID != nil {
		role, err := s.collectionRepo.GetUserRole(ctx, *existing.CollectionID, userID)
		if err != nil {
			return nil, repository.ErrEntryNotFound
		}
		if role == "read" {
			return nil, ErrNotCollectionOwner
		}
	} else if existing.UserID != userID {
		return nil, repository.ErrEntryNotFound
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

	// Validate additional field values against the type's field schema
	if err := s.validateAdditionalFields(ctx, typeID, additionalFields); err != nil {
		return nil, err
	}

	// If moving the entry to a different collection, verify write access there too.
	if collectionID != nil {
		role, err := s.collectionRepo.GetUserRole(ctx, *collectionID, userID)
		if err != nil {
			return nil, fmt.Errorf("invalid collection: %w", err)
		}
		if role == "read" {
			return nil, ErrNotCollectionOwner
		}
	}

	// Update entry
	entry, err := s.entryRepo.UpdateEntry(
		ctx,
		id,
		collectionID,
		typeID,
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

	// Refresh collection statistics cache for affected collections (best-effort).
	if existing.CollectionID != nil {
		_ = s.collectionRepo.RefreshCollectionStatistics(ctx, *existing.CollectionID)
	}
	if collectionID != nil && (existing.CollectionID == nil || *collectionID != *existing.CollectionID) {
		_ = s.collectionRepo.RefreshCollectionStatistics(ctx, *collectionID)
	}

	return entry, nil
}

// DeleteEntry deletes an entry.
// Users with owner/write access to the entry's collection may delete any entry in it.
// Entries without a collection may only be deleted by their creator.
func (s *EntryService) DeleteEntry(
	ctx context.Context,
	id uuid.UUID,
	userID uuid.UUID,
) error {
	entry, err := s.entryRepo.GetEntryByID(ctx, id)
	if err != nil {
		return err
	}

	if entry.CollectionID != nil {
		role, err := s.collectionRepo.GetUserRole(ctx, *entry.CollectionID, userID)
		if err != nil {
			return fmt.Errorf("invalid collection: %w", err)
		}
		if role == "read" {
			return ErrNotCollectionOwner
		}
	} else if entry.UserID != userID {
		return repository.ErrEntryNotFound
	}

	if err := s.entryRepo.DeleteEntry(ctx, id); err != nil {
		return err
	}

	// Refresh collection statistics cache (best-effort).
	if entry.CollectionID != nil {
		_ = s.collectionRepo.RefreshCollectionStatistics(ctx, *entry.CollectionID)
	}

	return nil
}

// DeleteEntries bulk-deletes entries owned by userID. Returns the count of deleted rows.
// Callers are responsible for validating that ids is non-empty and within size limits.
func (s *EntryService) DeleteEntries(ctx context.Context, ids []uuid.UUID, userID uuid.UUID) (int64, error) {
	return s.entryRepo.DeleteEntriesByIDs(ctx, ids, userID)
}

// GetImageByID retrieves a single image by ID without ownership check.
// Images are served on a public endpoint — access control is by UUID obscurity.
func (s *EntryService) GetImageByID(
	ctx context.Context,
	imageID uuid.UUID,
) (*repository.EntryImage, error) {
	return s.entryRepo.GetImageByID(ctx, imageID)
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
