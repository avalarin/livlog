package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/service"
)

type CollectionHandler struct {
	collectionService *service.CollectionService
	log               *zap.Logger
}

func NewCollectionHandler(collectionService *service.CollectionService, log *zap.Logger) *CollectionHandler {
	return &CollectionHandler{
		collectionService: collectionService,
		log:               log,
	}
}

func (h *CollectionHandler) RegisterRoutes(r chi.Router) {
	r.Get("/collections", h.GetCollections)
	r.Post("/collections", h.CreateCollection)
	r.Post("/collections/default", h.CreateDefaultCollections)
	r.Get("/collections/{id}", h.GetCollection)
	r.Put("/collections/{id}", h.UpdateCollection)
	r.Delete("/collections/{id}", h.DeleteCollection)
	r.Get("/collections/{id}/members", h.GetMembers)
	r.Post("/collections/{id}/shares", h.AddShare)
	r.Patch("/collections/{id}/shares/{userID}", h.UpdateShare)
	r.Delete("/collections/{id}/shares/{userID}", h.RemoveShare)
}

type createCollectionRequest struct {
	Name string `json:"name"`
	Icon string `json:"icon"`
}

type collectionResponse struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Icon        string  `json:"icon"`
	EntryCount  int     `json:"entry_count"`
	MemberCount int     `json:"member_count"`
	MyRole      string  `json:"my_role"`
	SharedBy    *string `json:"shared_by,omitempty"`
	CreatedAt   string  `json:"created_at"`
	UpdatedAt   string  `json:"updated_at"`
}

type memberResponse struct {
	UserID      string  `json:"user_id"`
	Email       *string `json:"email"`
	DisplayName *string `json:"display_name"`
	Role        string  `json:"role"`
}

type addShareRequest struct {
	Email string `json:"email"`
	Role  string `json:"role"`
}

type updateShareRequest struct {
	Role string `json:"role"`
}

func (h *CollectionHandler) GetCollections(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collections, err := h.collectionService.GetCollectionsByUserID(r.Context(), uid)
	if err != nil {
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to get collections", err)
		return
	}

	response := make([]collectionResponse, len(collections))
	for i, c := range collections {
		response[i] = mapCollectionToResponse(c)
	}

	respondWithJSON(h.log, w, http.StatusOK, response)
}

func (h *CollectionHandler) CreateCollection(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	var req createCollectionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	collection, err := h.collectionService.CreateCollection(r.Context(), uid, req.Name, req.Icon)
	if err != nil {
		if errors.Is(err, service.ErrInvalidCollectionName) || errors.Is(err, service.ErrInvalidIcon) {
			respondWithError(h.log, w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to create collection", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusCreated, mapCollectionToResponse(collection))
}

func (h *CollectionHandler) CreateDefaultCollections(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collections, err := h.collectionService.CreateDefaultCollections(r.Context(), uid)
	if err != nil {
		if errors.Is(err, service.ErrAlreadyHasCollections) {
			respondWithError(h.log, w, http.StatusBadRequest, "User already has collections", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to create default collections", err)
		return
	}

	response := make([]collectionResponse, len(collections))
	for i, c := range collections {
		response[i] = mapCollectionToResponse(c)
	}

	respondWithJSON(h.log, w, http.StatusCreated, response)
}

func (h *CollectionHandler) GetCollection(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	collection, err := h.collectionService.GetCollectionByID(r.Context(), cid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "Collection not found", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to get collection", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, mapCollectionToResponse(collection))
}

func (h *CollectionHandler) UpdateCollection(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	var req createCollectionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	collection, err := h.collectionService.UpdateCollection(r.Context(), cid, uid, req.Name, req.Icon)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "Collection not found", err)
			return
		}
		if errors.Is(err, service.ErrNotCollectionOwner) {
			respondWithError(h.log, w, http.StatusForbidden, err.Error(), err)
			return
		}
		if errors.Is(err, service.ErrInvalidCollectionName) || errors.Is(err, service.ErrInvalidIcon) {
			respondWithError(h.log, w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to update collection", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, mapCollectionToResponse(collection))
}

func (h *CollectionHandler) DeleteCollection(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	err = h.collectionService.DeleteCollection(r.Context(), cid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "Collection not found", err)
			return
		}
		if errors.Is(err, service.ErrLastOwner) {
			respondWithError(h.log, w, http.StatusConflict, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to leave collection", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, map[string]string{"message": "Collection deleted successfully"})
}

func (h *CollectionHandler) GetMembers(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	members, err := h.collectionService.GetMembers(r.Context(), cid, uid)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "Collection not found", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to get members", err)
		return
	}

	response := make([]memberResponse, len(members))
	for i, m := range members {
		response[i] = memberResponse{
			UserID:      m.UserID.String(),
			Email:       m.Email,
			DisplayName: m.DisplayName,
			Role:        m.Role,
		}
	}

	respondWithJSON(h.log, w, http.StatusOK, response)
}

func (h *CollectionHandler) AddShare(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	var req addShareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	// Validate role
	if req.Role != "owner" && req.Role != "write" && req.Role != "read" {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid role: must be 'owner', 'write', or 'read'", nil)
		return
	}

	err = h.collectionService.AddShare(r.Context(), cid, uid, req.Email, req.Role)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "Collection not found", err)
			return
		}
		if errors.Is(err, service.ErrNotCollectionOwner) {
			respondWithError(h.log, w, http.StatusForbidden, err.Error(), err)
			return
		}
		if errors.Is(err, repository.ErrAlreadyMember) {
			respondWithError(h.log, w, http.StatusConflict, "User is already a member of this collection", err)
			return
		}
		if errors.Is(err, repository.ErrUserNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "User not found", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to add share", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusCreated, map[string]string{"message": "User added to collection"})
}

func (h *CollectionHandler) UpdateShare(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	targetUserIDStr := chi.URLParam(r, "userID")
	targetUID, err := uuid.Parse(targetUserIDStr)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid target user ID", err)
		return
	}

	var req updateShareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Role != "owner" && req.Role != "write" && req.Role != "read" {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid role: must be 'owner', 'write', or 'read'", nil)
		return
	}

	err = h.collectionService.UpdateShare(r.Context(), cid, uid, targetUID, req.Role)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "Collection or membership not found", err)
			return
		}
		if errors.Is(err, service.ErrNotCollectionOwner) {
			respondWithError(h.log, w, http.StatusForbidden, err.Error(), err)
			return
		}
		if errors.Is(err, service.ErrLastOwner) {
			respondWithError(h.log, w, http.StatusConflict, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to update share", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, map[string]string{"message": "Permission updated"})
}

func (h *CollectionHandler) RemoveShare(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	uid, err := uuid.Parse(userID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid user ID", err)
		return
	}

	collectionID := chi.URLParam(r, "id")
	cid, err := uuid.Parse(collectionID)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid collection ID", err)
		return
	}

	targetUserIDStr := chi.URLParam(r, "userID")
	targetUID, err := uuid.Parse(targetUserIDStr)
	if err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid target user ID", err)
		return
	}

	err = h.collectionService.RemoveShare(r.Context(), cid, uid, targetUID)
	if err != nil {
		if errors.Is(err, repository.ErrCollectionNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "Collection or membership not found", err)
			return
		}
		if errors.Is(err, service.ErrNotCollectionOwner) {
			respondWithError(h.log, w, http.StatusForbidden, err.Error(), err)
			return
		}
		if errors.Is(err, service.ErrLastOwner) {
			respondWithError(h.log, w, http.StatusConflict, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to remove share", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, map[string]string{"message": "User removed from collection"})
}

func mapCollectionToResponse(c *repository.Collection) collectionResponse {
	return collectionResponse{
		ID:          c.ID.String(),
		Name:        c.Name,
		Icon:        c.Icon,
		EntryCount:  c.EntryCount,
		MemberCount: c.MemberCount,
		MyRole:      c.MyRole,
		SharedBy:    c.SharedBy,
		CreatedAt:   c.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt:   c.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}
