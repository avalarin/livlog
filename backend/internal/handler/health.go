package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/avalarin/livlog/backend/internal/repository"
)

const Version = "1.0.0"

type HealthHandler struct {
	db        *repository.DB
	startTime time.Time
}

func NewHealthHandler(db *repository.DB) *HealthHandler {
	return &HealthHandler{
		db:        db,
		startTime: time.Now(),
	}
}

type DatabaseStatus struct {
	Status string `json:"status"`
	PingMs int64  `json:"ping_ms"`
}

type HealthResponse struct {
	Status    string         `json:"status"`
	Timestamp string         `json:"timestamp"`
	Version   string         `json:"version"`
	Uptime    string         `json:"uptime"`
	Database  DatabaseStatus `json:"database"`
}

func (h *HealthHandler) Health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()

	response := HealthResponse{
		Status:    "ok",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Version:   Version,
		Uptime:    time.Since(h.startTime).Round(time.Second).String(),
		Database: DatabaseStatus{
			Status: "connected",
			PingMs: 0,
		},
	}

	pingDuration, err := h.db.Ping(ctx)
	if err != nil {
		response.Status = "degraded"
		response.Database.Status = "disconnected"
	} else {
		response.Database.PingMs = pingDuration.Milliseconds()
	}

	w.Header().Set("Content-Type", "application/json")

	statusCode := http.StatusOK
	if response.Status != "ok" {
		statusCode = http.StatusServiceUnavailable
	}
	w.WriteHeader(statusCode)

	if err := json.NewEncoder(w).Encode(response); err != nil {
		http.Error(w, "failed to encode response", http.StatusInternalServerError)
	}
}
