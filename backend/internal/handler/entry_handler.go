package handler

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/service"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type EntryHandler struct {
	entryService *service.EntryService
}

func NewEntryHandler(entryService *service.EntryService) *EntryHandler {
	return &EntryHandler{
		entryService: entryService,
	}
}

func (h *EntryHandler) RegisterRoutes(r chi.Router) {
	r.Get("/entries", h.GetEntries)
	r.Post("/entries", h.CreateEntry)
	r.Get("/entries/search", h.SearchEntries)
	r.Get("/entries/{id}", h.GetEntry)
	r.Put("/entries/{id}", h.UpdateEntry)
	r.Delete("/entries/{id}", h.DeleteEntry)
	r.Get("/entries/{id}/images", h.GetEntryImages)
}

type imageData struct {
	Data     string `json:"data"`      // base64 encoded
	IsCover  bool   `json:"is_cover"`
	Position int    `json:"position"`
}

type createEntryRequest struct {
	CollectionID     *string            `json:"collection_id,omitempty"`
	Title            string             `json:"title"`
	Description      string             `json:"description"`
	Score            int                `json:"score"`
	Date             string             `json:"date"` // YYYY-MM-DD
	AdditionalFields map[string]string  `json:"additional_fields,omitempty"`
	Images           []imageData        `json:"images,omitempty"`
}

type entryResponse struct {
	ID               string            `json:"id"`
	CollectionID     *string           `json:"collection_id,omitempty"`
	Title            string            `json:"title"`
	Description      string            `json:"description"`
	Score            int               `json:"score"`
	Date             string            `json:"date"`
	AdditionalFields map[string]string `json:"additional_fields"`
	CreatedAt        string            `json:"created_at"`
	UpdatedAt        string            `json:"updated_at"`
}

type imageResponse struct {
	ID       string `json:"id"`
	Data     string `json:"data"` // base64 encoded
	IsCover  bool   `json:"is_cover"`
	Position int    `json:"position"`
}

func (h *EntryHandler) GetEntries(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	// Parse query parameters
	var collectionID *uuid.UUID
	if collectionParam := r.URL.Query().Get("collection_id"); collectionParam != "" {
		cid, err := uuid.Parse(collectionParam)
		if err != nil {
			respondWithError(w, http.StatusBadRequest, "Invalid collection ID", err)
			return
		}
		collectionID = &cid
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit == 0 {
		limit = 50
	}

	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	entries, err := h.entryService.GetEntriesByUserID(r.Context(), uid, collectionID, limit, offset)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to get entries", err)
		return
	}

	response := make([]entryResponse, len(entries))
	for i, e := range entries {
		response[i] = mapEntryToResponse(e)
	}

	respondWithJSON(w, http.StatusOK, response)
}

func (h *EntryHandler) CreateEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	var req createEntryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	// Parse collection ID
	var collectionID *uuid.UUID
	if req.CollectionID != nil {
		cid, err := uuid.Parse(*req.CollectionID)
		if err != nil {
			respondWithError(w, http.StatusBadRequest, "Invalid collection ID", err)
			return
		}
		collectionID = &cid
	}

	// Parse date
	date, err := time.Parse("2006-01-02", req.Date)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid date format (use YYYY-MM-DD)", err)
		return
	}

	// Parse images
	var images []repository.EntryImage
	for _, img := range req.Images {
		imageBytes, err := base64.StdEncoding.DecodeString(img.Data)
		if err != nil {
			respondWithError(w, http.StatusBadRequest, "Invalid image data", err)
			return
		}
		images = append(images, repository.EntryImage{
			ImageData: imageBytes,
			IsCover:   img.IsCover,
			Position:  img.Position,
		})
	}

	entry, err := h.entryService.CreateEntry(
		r.Context(),
		uid,
		collectionID,
		req.Title,
		req.Description,
		req.Score,
		date,
		req.AdditionalFields,
		images,
	)
	if err != nil {
		if errors.Is(err, service.ErrInvalidTitle) ||
			errors.Is(err, service.ErrInvalidDescription) ||
			errors.Is(err, service.ErrInvalidScore) {
			respondWithError(w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to create entry", err)
		return
	}

	respondWithJSON(w, http.StatusCreated, mapEntryToResponse(entry))
}

func (h *EntryHandler) GetEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	entryID := chi.URLParam(r, "id")
	eid, err := uuid.Parse(entryID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid entry ID", err)
		return
	}

	entry, err := h.entryService.GetEntryByID(r.Context(), eid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrEntryNotFound) {
			respondWithError(w, http.StatusNotFound, "Entry not found", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to get entry", err)
		return
	}

	respondWithJSON(w, http.StatusOK, mapEntryToResponse(entry))
}

func (h *EntryHandler) UpdateEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	entryID := chi.URLParam(r, "id")
	eid, err := uuid.Parse(entryID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid entry ID", err)
		return
	}

	var req createEntryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	// Parse collection ID
	var collectionID *uuid.UUID
	if req.CollectionID != nil {
		cid, err := uuid.Parse(*req.CollectionID)
		if err != nil {
			respondWithError(w, http.StatusBadRequest, "Invalid collection ID", err)
			return
		}
		collectionID = &cid
	}

	// Parse date
	date, err := time.Parse("2006-01-02", req.Date)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid date format (use YYYY-MM-DD)", err)
		return
	}

	// Parse images (nil if not provided, means don't update images)
	var images []repository.EntryImage
	if req.Images != nil {
		for _, img := range req.Images {
			imageBytes, err := base64.StdEncoding.DecodeString(img.Data)
			if err != nil {
				respondWithError(w, http.StatusBadRequest, "Invalid image data", err)
				return
			}
			images = append(images, repository.EntryImage{
				ImageData: imageBytes,
				IsCover:   img.IsCover,
				Position:  img.Position,
			})
		}
	}

	entry, err := h.entryService.UpdateEntry(
		r.Context(),
		eid,
		uid,
		collectionID,
		req.Title,
		req.Description,
		req.Score,
		date,
		req.AdditionalFields,
		images,
	)
	if err != nil {
		if errors.Is(err, repository.ErrEntryNotFound) {
			respondWithError(w, http.StatusNotFound, "Entry not found", err)
			return
		}
		if errors.Is(err, service.ErrInvalidTitle) ||
			errors.Is(err, service.ErrInvalidDescription) ||
			errors.Is(err, service.ErrInvalidScore) {
			respondWithError(w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to update entry", err)
		return
	}

	respondWithJSON(w, http.StatusOK, mapEntryToResponse(entry))
}

func (h *EntryHandler) DeleteEntry(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	entryID := chi.URLParam(r, "id")
	eid, err := uuid.Parse(entryID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid entry ID", err)
		return
	}

	err = h.entryService.DeleteEntry(r.Context(), eid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrEntryNotFound) {
			respondWithError(w, http.StatusNotFound, "Entry not found", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to delete entry", err)
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]string{"message": "Entry deleted successfully"})
}

func (h *EntryHandler) GetEntryImages(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	entryID := chi.URLParam(r, "id")
	eid, err := uuid.Parse(entryID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid entry ID", err)
		return
	}

	images, err := h.entryService.GetEntryImages(r.Context(), eid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrEntryNotFound) {
			respondWithError(w, http.StatusNotFound, "Entry not found", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to get images", err)
		return
	}

	response := make([]imageResponse, len(images))
	for i, img := range images {
		response[i] = imageResponse{
			ID:       img.ID.String(),
			Data:     base64.StdEncoding.EncodeToString(img.ImageData),
			IsCover:  img.IsCover,
			Position: img.Position,
		}
	}

	respondWithJSON(w, http.StatusOK, response)
}

func (h *EntryHandler) SearchEntries(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	query := r.URL.Query().Get("q")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit == 0 {
		limit = 50
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	entries, err := h.entryService.SearchEntries(r.Context(), uid, query, limit, offset)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to search entries", err)
		return
	}

	response := make([]entryResponse, len(entries))
	for i, e := range entries {
		response[i] = mapEntryToResponse(e)
	}

	respondWithJSON(w, http.StatusOK, response)
}

func mapEntryToResponse(e *repository.Entry) entryResponse {
	var collectionID *string
	if e.CollectionID != nil {
		cid := e.CollectionID.String()
		collectionID = &cid
	}

	return entryResponse{
		ID:               e.ID.String(),
		CollectionID:     collectionID,
		Title:            e.Title,
		Description:      e.Description,
		Score:            e.Score,
		Date:             e.Date.Format("2006-01-02"),
		AdditionalFields: e.AdditionalFields,
		CreatedAt:        e.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:        e.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}
