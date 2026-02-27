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

type TypeHandler struct {
	typeService *service.TypeService
}

func NewTypeHandler(typeService *service.TypeService) *TypeHandler {
	return &TypeHandler{typeService: typeService}
}

func (h *TypeHandler) RegisterRoutes(r chi.Router) {
	r.Get("/types", h.GetTypes)
	r.Post("/types", h.CreateType)
}

type createTypeRequest struct {
	Name string `json:"name"`
	Icon string `json:"icon"`
}

type typeResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Icon      string `json:"icon"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

func (h *TypeHandler) GetTypes(w http.ResponseWriter, r *http.Request) {
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

	types, err := h.typeService.GetAllTypes(r.Context(), uid)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, "Failed to get types", err)
		return
	}

	response := make([]typeResponse, len(types))
	for i, t := range types {
		response[i] = mapTypeToResponse(t)
	}

	respondWithJSON(w, http.StatusOK, response)
}

func (h *TypeHandler) CreateType(w http.ResponseWriter, r *http.Request) {
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

	var req createTypeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	t, err := h.typeService.CreateType(r.Context(), uid, req.Name, req.Icon)
	if err != nil {
		if errors.Is(err, service.ErrInvalidTypeName) || errors.Is(err, service.ErrInvalidTypeIcon) {
			respondWithError(w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(w, http.StatusInternalServerError, "Failed to create type", err)
		return
	}

	respondWithJSON(w, http.StatusCreated, mapTypeToResponse(t))
}

func mapTypeToResponse(t *repository.EntryType) typeResponse {
	return typeResponse{
		ID:        t.ID.String(),
		Name:      t.Name,
		Icon:      t.Icon,
		CreatedAt: t.CreatedAt.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: t.UpdatedAt.Format("2006-01-02T15:04:05Z07:00"),
	}
}
