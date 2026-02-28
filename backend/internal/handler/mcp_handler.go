package handler

import (
	"errors"
	"net/http"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/service"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"go.uber.org/zap"
)

type MCPHandler struct {
	mcpService *service.MCPService
	log        *zap.Logger
}

func NewMCPHandler(mcpService *service.MCPService, log *zap.Logger) *MCPHandler {
	return &MCPHandler{
		mcpService: mcpService,
		log:        log,
	}
}

func (h *MCPHandler) RegisterRoutes(r chi.Router) {
	r.Get("/mcp", h.GetStatus)
	r.Post("/mcp", h.Enable)
	r.Delete("/mcp", h.Disable)
}

type mcpStatusResponse struct {
	Enabled bool    `json:"enabled"`
	URL     *string `json:"url"` // null when not enabled
}

func (h *MCPHandler) GetStatus(w http.ResponseWriter, r *http.Request) {
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

	status, err := h.mcpService.GetStatus(r.Context(), uid)
	if err != nil {
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to get MCP status", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusOK, mapMCPStatusToResponse(status))
}

func (h *MCPHandler) Enable(w http.ResponseWriter, r *http.Request) {
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

	status, err := h.mcpService.Enable(r.Context(), uid)
	if err != nil {
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to enable MCP", err)
		return
	}

	respondWithJSON(h.log, w, http.StatusCreated, mapMCPStatusToResponse(status))
}

func (h *MCPHandler) Disable(w http.ResponseWriter, r *http.Request) {
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

	err = h.mcpService.Disable(r.Context(), uid)
	if err != nil {
		if errors.Is(err, repository.ErrMCPNotFound) {
			respondWithError(h.log, w, http.StatusNotFound, "MCP integration not found", err)
			return
		}
		respondWithError(h.log, w, http.StatusInternalServerError, "Failed to disable MCP", err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func mapMCPStatusToResponse(s *service.MCPStatus) mcpStatusResponse {
	if !s.Enabled {
		return mcpStatusResponse{Enabled: false, URL: nil}
	}
	url := s.URL
	return mcpStatusResponse{Enabled: true, URL: &url}
}
