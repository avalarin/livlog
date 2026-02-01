package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/avalarin/livlog/backend/internal/service"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type AISearchHandler struct {
	aiSearchService *service.AISearchService
}

func NewAISearchHandler(aiSearchService *service.AISearchService) *AISearchHandler {
	return &AISearchHandler{
		aiSearchService: aiSearchService,
	}
}

func (h *AISearchHandler) RegisterRoutes(r chi.Router) {
	r.Post("/search", h.Search)
}

type searchRequest struct {
	Query string `json:"query"`
}

type searchResponse struct {
	Options []service.SearchOption `json:"options"`
}

func (h *AISearchHandler) Search(w http.ResponseWriter, r *http.Request) {
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

	var req searchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid request body", err)
		return
	}

	if req.Query == "" {
		respondWithError(w, http.StatusBadRequest, "Query is required", nil)
		return
	}

	options, err := h.aiSearchService.SearchOptions(r.Context(), uid, req.Query)
	if err != nil {
		if errors.Is(err, service.ErrAISearchRateLimitExceeded) {
			// Return 429 rate limit error according to API spec
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)

			errorResp := map[string]interface{}{
				"error": map[string]interface{}{
					"code":    "RATE_LIMIT_EXCEEDED",
					"message": "Too many AI search requests. Please try again later.",
					"details": map[string]interface{}{
						"retryAfter": 86400, // 24 hours in seconds
					},
				},
			}

			json.NewEncoder(w).Encode(errorResp)
			return
		}

		respondWithError(w, http.StatusInternalServerError, "Failed to perform search", err)
		return
	}

	respondWithJSON(w, http.StatusOK, searchResponse{Options: options})
}
