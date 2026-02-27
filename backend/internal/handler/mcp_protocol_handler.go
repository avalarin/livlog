package handler

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/service"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/mark3labs/mcp-go/mcp"
	mcpserver "github.com/mark3labs/mcp-go/server"
	"go.uber.org/zap"
)

const maxAddEntriesBatch = 100

type MCPProtocolHandler struct {
	mcpService        *service.MCPService
	collectionService *service.CollectionService
	entryService      *service.EntryService
	log               *zap.Logger
}

func NewMCPProtocolHandler(
	mcpService *service.MCPService,
	collectionService *service.CollectionService,
	entryService *service.EntryService,
	log *zap.Logger,
) *MCPProtocolHandler {
	return &MCPProtocolHandler{
		mcpService:        mcpService,
		collectionService: collectionService,
		entryService:      entryService,
		log:               log,
	}
}

func (h *MCPProtocolHandler) RegisterRoutes(r chi.Router) {
	// Single endpoint — StreamableHTTPServer handles GET (SSE) and POST (tool calls).
	r.HandleFunc("/api/mcp/{unique_code}", h.handleMCP)
}

func (h *MCPProtocolHandler) handleMCP(w http.ResponseWriter, r *http.Request) {
	uniqueCode := chi.URLParam(r, "unique_code")
	if uniqueCode == "" {
		http.Error(w, "missing unique_code", http.StatusBadRequest)
		return
	}

	userID, err := h.mcpService.GetUserIDByCode(r.Context(), uniqueCode)
	if err != nil {
		if errors.Is(err, repository.ErrMCPNotFound) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		h.log.Error("failed to get user by mcp code", zap.Error(err))
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	mcpSrv := mcpserver.NewMCPServer("livlog", "1.0.0")

	// Register get-collections tool
	getCollectionsTool := mcp.NewTool("get-collections",
		mcp.WithDescription("Get all collections for the authenticated user"),
	)
	mcpSrv.AddTool(getCollectionsTool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		collections, err := h.collectionService.GetCollectionsByUserID(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to get collections: %w", err)
		}

		type collectionResult struct {
			ID         string `json:"id"`
			Name       string `json:"name"`
			Icon       string `json:"icon"`
			EntryCount int    `json:"entry_count"`
		}

		results := make([]collectionResult, len(collections))
		for i, c := range collections {
			results[i] = collectionResult{
				ID:         c.ID.String(),
				Name:       c.Name,
				Icon:       c.Icon,
				EntryCount: c.EntryCount,
			}
		}

		jsonBytes, err := json.Marshal(results)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal collections: %w", err)
		}

		return mcp.NewToolResultText(string(jsonBytes)), nil
	})

	// Register add-entries tool
	addEntriesTool := mcp.NewTool("add-entries",
		mcp.WithDescription("Add one or more entries to a collection (max 100 per call)"),
		mcp.WithString("collection_id",
			mcp.Required(),
			mcp.Description("UUID of the collection to add entries to"),
		),
		mcp.WithArray("entries",
			mcp.Required(),
			mcp.Description(`Array of entries to add. Each entry: {"title": string (required), "description": string (optional), "score": 0-3 (optional, default 0), "date": "YYYY-MM-DD" (optional, default today)}`),
		),
	)
	mcpSrv.AddTool(addEntriesTool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, ok := req.Params.Arguments.(map[string]interface{})
		if !ok {
			return nil, fmt.Errorf("invalid arguments format")
		}

		collectionIDRaw, ok := args["collection_id"]
		if !ok {
			return nil, fmt.Errorf("collection_id is required")
		}
		collectionIDStr, ok := collectionIDRaw.(string)
		if !ok {
			return nil, fmt.Errorf("collection_id must be a string")
		}

		collectionUUID, err := uuid.Parse(collectionIDStr)
		if err != nil {
			return nil, fmt.Errorf("invalid collection_id: %w", err)
		}

		entriesRaw, ok := args["entries"]
		if !ok {
			return nil, fmt.Errorf("entries is required")
		}

		entriesJSON, err := json.Marshal(entriesRaw)
		if err != nil {
			return nil, fmt.Errorf("failed to process entries: %w", err)
		}

		type entryInput struct {
			Title       string `json:"title"`
			Description string `json:"description"`
			Score       int    `json:"score"`
			Date        string `json:"date"`
		}

		var entries []entryInput
		if err := json.Unmarshal(entriesJSON, &entries); err != nil {
			return nil, fmt.Errorf("invalid entries format: %w", err)
		}

		if len(entries) == 0 {
			return nil, fmt.Errorf("entries must not be empty")
		}
		if len(entries) > maxAddEntriesBatch {
			return nil, fmt.Errorf("too many entries: maximum %d per call", maxAddEntriesBatch)
		}

		today := time.Now().Format("2006-01-02")
		createdIDs := make([]string, 0, len(entries))

		for _, e := range entries {
			if e.Title == "" {
				return nil, fmt.Errorf("each entry must have a title")
			}

			description := e.Description
			if description == "" {
				description = e.Title
			}

			score := e.Score
			if score < 0 || score > 3 {
				score = 0
			}

			dateStr := e.Date
			if dateStr == "" {
				dateStr = today
			}

			date, err := time.Parse("2006-01-02", dateStr)
			if err != nil {
				return nil, fmt.Errorf("invalid date format for entry %q, use YYYY-MM-DD", e.Title)
			}

			entry, err := h.entryService.CreateEntry(
				ctx,
				userID,
				&collectionUUID,
				nil,
				e.Title,
				description,
				score,
				date,
				nil,
				nil,
				nil,
			)
			if err != nil {
				return nil, fmt.Errorf("failed to create entry %q: %w", e.Title, err)
			}

			createdIDs = append(createdIDs, entry.ID.String())
		}

		type addEntriesResult struct {
			CreatedIDs []string `json:"created_ids"`
		}

		jsonBytes, err := json.Marshal(addEntriesResult{CreatedIDs: createdIDs})
		if err != nil {
			return nil, fmt.Errorf("failed to marshal result: %w", err)
		}

		return mcp.NewToolResultText(string(jsonBytes)), nil
	})

	// Use StreamableHTTPServer in stateless mode: each POST is self-contained,
	// no session state is stored between requests — safe for per-request server creation.
	transport := mcpserver.NewStreamableHTTPServer(mcpSrv,
		mcpserver.WithStateLess(true),
	)
	transport.ServeHTTP(w, r)
}
