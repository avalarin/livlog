package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/service"
)

type OnboardingHandler struct {
	onboardingService *service.OnboardingService
	log               *zap.Logger
}

func NewOnboardingHandler(onboardingService *service.OnboardingService, log *zap.Logger) *OnboardingHandler {
	return &OnboardingHandler{
		onboardingService: onboardingService,
		log:               log,
	}
}

func (h *OnboardingHandler) RegisterRoutes(r chi.Router) {
	r.Get("/onboarding/templates", h.GetTemplates)
	r.Post("/onboarding/complete", h.CompleteOnboarding)
	r.Put("/users/me/display-name", h.UpdateDisplayName)
	r.Post("/collections/from-template/{slug}", h.CreateFromTemplate)
}

type templateResponse struct {
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	Description string `json:"description"`
	Icon        string `json:"icon"`
	Color       string `json:"color"`
}

func (h *OnboardingHandler) GetTemplates(w http.ResponseWriter, r *http.Request) {
	userID := getUserIDFromContext(r.Context())
	if userID == "" {
		respondWithError(h.log, w, http.StatusUnauthorized, "User not authenticated", nil)
		return
	}

	templates, err := h.onboardingService.GetTemplates(r.Context())
	if err != nil {
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to get templates", err)
		return
	}

	response := make([]templateResponse, len(templates))
	for i, t := range templates {
		slug := ""
		if t.Slug != nil {
			slug = *t.Slug
		}
		response[i] = templateResponse{
			Slug:        slug,
			Name:        t.Name,
			Description: t.Description,
			Icon:        t.Icon,
			Color:       t.Color,
		}
	}

	respondWithJSON(h.log, w, http.StatusOK, response)
}

func (h *OnboardingHandler) CompleteOnboarding(w http.ResponseWriter, r *http.Request) {
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

	err = h.onboardingService.CompleteOnboarding(r.Context(), uid)
	if err != nil {
		if errors.Is(err, service.ErrOnboardingAlreadyCompleted) {
			respondWithError(h.log, w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to complete onboarding", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, map[string]string{"message": "Onboarding completed"})
}

type updateDisplayNameRequest struct {
	DisplayName string `json:"display_name"`
}

func (h *OnboardingHandler) UpdateDisplayName(w http.ResponseWriter, r *http.Request) {
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

	var req updateDisplayNameRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(h.log, w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	err = h.onboardingService.UpdateDisplayName(r.Context(), uid, req.DisplayName)
	if err != nil {
		if errors.Is(err, service.ErrInvalidDisplayName) {
			respondWithError(h.log, w, http.StatusBadRequest, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to update display name", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, map[string]string{"message": "Display name updated"})
}

type createFromTemplateRequest struct {
	IncludeEntries *bool `json:"include_entries"`
}

func (h *OnboardingHandler) CreateFromTemplate(w http.ResponseWriter, r *http.Request) {
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

	slug := chi.URLParam(r, "slug")
	if slug == "" {
		respondWithError(h.log, w, http.StatusBadRequest, "Template slug is required", nil)
		return
	}

	includeEntries := true
	var req createFromTemplateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err == nil && req.IncludeEntries != nil {
		includeEntries = *req.IncludeEntries
	}

	collection, err := h.onboardingService.CreateCollectionFromTemplate(r.Context(), uid, slug, includeEntries)
	if err != nil {
		if errors.Is(err, service.ErrTemplateNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, err.Error(), err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to create collection from template", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusCreated, map[string]string{
		"message":       "Collection created from template",
		"collection_id": collection.ID.String(),
	})
}
