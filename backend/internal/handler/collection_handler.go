package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/service"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type CollectionHandler struct {
	collectionService *service.CollectionService
}

func NewCollectionHandler(collectionService *service.CollectionService) *CollectionHandler {
	return &CollectionHandler{
		collectionService: collectionService,
	}
}

func (h *CollectionHandler) RegisterRoutes(r chi.Router) {
	r.Get("/collections", h.GetCollections)
	r.Post("/collections", h.CreateCollection)
	r.Post("/collections/default", h.CreateDefaultCollections)
	r.Get("/collections/{id}", h.GetCollection)
	r.Put("/collections/{id}", h.UpdateCollection)
	r.Delete("/collections/{id}", h.DeleteCollection)
}

type createCollectionRequest struct {
	Name string `json:"name"`
	Icon string `json:"icon"`
}

type collectionResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Icon      string `json:"icon"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

func (h *CollectionHandler) GetCollections(w http.ResponseWriter, r *http.Request) {
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

	collections, err := h.collectionService.GetCollectionsByUserID(r.Context(), uid)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to get collections", err)
		return
	}

	response := make([]collectionResponse, len(collections))
	for i, c := range collections {
		response[i] = mapCollectionToResponse(c)
	}

	respondWithJSON(w, http.StatusOK, response)
}

func (h *CollectionHandler) CreateCollection(w http.ResponseWriter, r *http.Request) {
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

	var req createCollectionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	collection, err := h.collectionService.CreateCollection(r.Context(), uid, req.Name, req.Icon)
	if err != nil {
		if errors.Is(err, service.ErrInvalidCollectionName) || errors.Is(err, service.ErrInvalidIcon) {
			respondWithError(w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to create collection", err)
		return
	}

	respondWithJSON(w, http.StatusCreated, mapCollectionToResponse(collection))
}

func (h *CollectionHandler) CreateDefaultCollections(w http.ResponseWriter, r *http.Request) {
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

	collections, err := h.collectionService.CreateDefaultCollections(r.Context(), uid)
	if err != nil {
		if err.Error() == "user already has collections" {
			respondWithError(w, http.StatusBadRequest, "User already has collections", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to create default collections", err)
		return
	}

	response := make([]collectionResponse, len(collections))
	for i, c := range collections {
		response[i] = mapCollectionToResponse(c)
	}

	respondWithJSON(w, http.StatusCreated, response)
}

func (h *CollectionHandler) GetCollection(w http.ResponseWriter, r *http.Request) {
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

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	collection, err := h.collectionService.GetCollectionByID(r.Context(), cid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(w, http.StatusNotFound, "Collection not found", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to get collection", err)
		return
	}

	respondWithJSON(w, http.StatusOK, mapCollectionToResponse(collection))
}

func (h *CollectionHandler) UpdateCollection(w http.ResponseWriter, r *http.Request) {
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

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	var req createCollectionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	collection, err := h.collectionService.UpdateCollection(r.Context(), cid, uid, req.Name, req.Icon)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(w, http.StatusNotFound, "Collection not found", err)
			return
		}
		if errors.Is(err, service.ErrInvalidCollectionName) || errors.Is(err, service.ErrInvalidIcon) {
			respondWithError(w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to update collection", err)
		return
	}

	respondWithJSON(w, http.StatusOK, mapCollectionToResponse(collection))
}

func (h *CollectionHandler) DeleteCollection(w http.ResponseWriter, r *http.Request) {
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

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	err = h.collectionService.DeleteCollection(r.Context(), cid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(w, http.StatusNotFound, "Collection not found", err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to delete collection", err)
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]string{"message": "Collection deleted successfully"})
}

func mapCollectionToResponse(c *repository.Collection) collectionResponse {
	return collectionResponse{
		ID:        c.ID.String(),
		Name:      c.Name,
		Icon:      c.Icon,
		CreatedAt: c.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: c.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}
