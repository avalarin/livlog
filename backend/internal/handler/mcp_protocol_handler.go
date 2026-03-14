package handler

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/mark3labs/mcp-go/mcp"
	mcpserver "github.com/mark3labs/mcp-go/server"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/service"
)

const (
	maxAddEntriesBatch = 100
	maxImageBytes      = 5 << 20 // 5 MB
	maxImagesPerEntry  = 3
)

type MCPProtocolHandler struct {
	mcpService        *service.MCPService
	collectionService *service.CollectionService
	entryService      *service.EntryService
	typeService       *service.TypeService
	tagRepo           *repository.TagRepository
	log               *zap.Logger
}

func NewMCPProtocolHandler(
	mcpService *service.MCPService,
	collectionService *service.CollectionService,
	entryService *service.EntryService,
	typeService *service.TypeService,
	tagRepo *repository.TagRepository,
	log *zap.Logger,
) *MCPProtocolHandler {
	return &MCPProtocolHandler{
		mcpService:        mcpService,
		collectionService: collectionService,
		entryService:      entryService,
		typeService:       typeService,
		tagRepo:           tagRepo,
		log:               log,
	}
}

func (h *MCPProtocolHandler) RegisterRoutes(r chi.Router) {
	// Single endpoint — StreamableHTTPServer handles GET (SSE) and POST (tool calls).
	r.HandleFunc("/api/mcp/{unique_code}", h.handleMCP)
}

// mcpEntryResult is the shared entry shape returned by find-entries and edit-entry.
type mcpEntryResult struct {
	ID               string            `json:"id"`
	CollectionID     string            `json:"collection_id,omitempty"`
	TypeID           string            `json:"type_id,omitempty"`
	Title            string            `json:"title"`
	Description      string            `json:"description"`
	Score            int               `json:"score"`
	Date             string            `json:"date"`
	AdditionalFields map[string]string `json:"additional_fields"`
}

func entryToResult(e *repository.Entry) mcpEntryResult {
	r := mcpEntryResult{
		ID:               e.ID.String(),
		Title:            e.Title,
		Description:      e.Description,
		Score:            e.Score,
		Date:             e.Date.Format("2006-01-02"),
		AdditionalFields: e.AdditionalFields,
	}
	if e.CollectionID != nil {
		r.CollectionID = e.CollectionID.String()
	}
	if e.TypeID != nil {
		r.TypeID = e.TypeID.String()
	}
	if r.AdditionalFields == nil {
		r.AdditionalFields = map[string]string{}
	}
	return r
}

// downloadImage fetches the image at rawURL and returns its bytes.
// Only http/https schemes are allowed. The body is limited to maxBytes.
func downloadImage(ctx context.Context, rawURL string, maxBytes int64) ([]byte, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, fmt.Errorf("unsupported URL scheme %q: only http and https are allowed", parsed.Scheme)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to download image: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("image URL returned HTTP %d", resp.StatusCode)
	}

	// LimitReader: read up to maxBytes+1 so we can detect an oversize body.
	limited := io.LimitReader(resp.Body, maxBytes+1)
	data, err := io.ReadAll(limited)
	if err != nil {
		return nil, fmt.Errorf("failed to read image body: %w", err)
	}
	if int64(len(data)) > maxBytes {
		return nil, fmt.Errorf("image exceeds maximum size of %d bytes", maxBytes)
	}

	return data, nil
}

// imageInput is the per-image payload accepted by add-entries and edit-entry.
type imageInput struct {
	URL  string `json:"url"`
	Data string `json:"data"`
}

// parseImages converts a raw JSON-marshallable value (from MCP args) into
// []repository.EntryImage. At most maxImagesPerEntry images are accepted.
func parseImages(ctx context.Context, raw interface{}) ([]repository.EntryImage, error) {
	if raw == nil {
		return nil, nil
	}

	rawJSON, err := json.Marshal(raw)
	if err != nil {
		return nil, fmt.Errorf("failed to process images: %w", err)
	}

	var inputs []imageInput
	if err := json.Unmarshal(rawJSON, &inputs); err != nil {
		return nil, fmt.Errorf("images must be an array of objects with url or data fields")
	}

	if len(inputs) > maxImagesPerEntry {
		return nil, fmt.Errorf("too many images: maximum %d per entry", maxImagesPerEntry)
	}

	images := make([]repository.EntryImage, 0, len(inputs))
	for i, inp := range inputs {
		var data []byte

		switch {
		case inp.URL != "":
			downloaded, err := downloadImage(ctx, inp.URL, maxImageBytes)
			if err != nil {
				return nil, fmt.Errorf("failed to fetch image %d from URL: %w", i, err)
			}
			data = downloaded

		case inp.Data != "":
			decoded, err := base64.StdEncoding.DecodeString(inp.Data)
			if err != nil {
				return nil, fmt.Errorf("image %d: invalid base64 data: %w", i, err)
			}
			if int64(len(decoded)) > maxImageBytes {
				return nil, fmt.Errorf("image %d exceeds maximum size of %d bytes", i, maxImageBytes)
			}
			data = decoded

		default:
			return nil, fmt.Errorf("image %d must have either url or data field", i)
		}

		images = append(images, repository.EntryImage{
			ImageData: data,
			IsCover:   i == 0,
			Position:  i,
		})
	}

	return images, nil
}

// mcpToolDefs holds the MCP tool definitions (name, description, input schema).
// These are shared between handleMCP (which pairs each tool with a real handler)
// and the eval test (which reads the schemas to build OpenAI tool definitions).
var mcpToolDefs = struct {
	GetCollections mcp.Tool
	GetEntryTypes  mcp.Tool
	AddEntries     mcp.Tool
	FindEntries    mcp.Tool
	EditEntry      mcp.Tool
}{
	GetCollections: mcp.NewTool("get-collections",
		mcp.WithDescription("Get all collections for the authenticated user"),
	),
	GetEntryTypes: mcp.NewTool("get-entry-types",
		mcp.WithDescription("Get all available entry types (system-wide and user-defined) with their fields. Call this only when you don't already know the type_id — if the type_id is provided in context, skip this step and use it directly."),
	),
	AddEntries: mcp.NewTool("add-entries",
		mcp.WithDescription("Add one or more entries to a collection (max 100 per call). If you already know the type_id from context, use it directly — no need to call get-entry-types first."),
		mcp.WithString("collection_id",
			mcp.Required(),
			mcp.Description("UUID of the collection to add entries to"),
		),
		mcp.WithArray("entries",
			mcp.Required(),
			mcp.Description("Array of entry objects to add"),
			mcp.Items(map[string]any{
				"type": "object",
				"properties": map[string]any{
					"title":       map[string]any{"type": "string", "description": "Entry title (required)"},
					"description": map[string]any{"type": "string", "description": "Short user note (optional, defaults to title). Do NOT put metadata here — use additional_fields for director, author, year, etc."},
					"type_id":     map[string]any{"type": "string", "description": "Entry type UUID (required)"},
					"score":       map[string]any{"type": "number", "description": "0 = new/haven't watched/read/played yet, 1 = bad, 2 = okay, 3 = great"},
					"date":        map[string]any{"type": "string", "description": "Watch/read/play date in YYYY-MM-DD format (defaults to today)"},
					"additional_fields": map[string]any{
						"type":        "object",
						"description": "REQUIRED for metadata. Put attributes like director, author, year here — NEVER in the description field.",
						"properties": map[string]any{
							"Director":  map[string]any{"type": "string"},
							"Author":    map[string]any{"type": "string"},
							"Year":      map[string]any{"type": "string"},
							"Developer": map[string]any{"type": "string"},
							"Genre":     map[string]any{"type": "string"},
						},
						"additionalProperties": map[string]any{"type": "string"},
					},
					"images": map[string]any{
						"type":        "array",
						"description": "Images: [{\"url\": \"https://...\"} or {\"data\": \"<base64>\"}] (max 3, max 5MB each, first = cover)",
						"items":       map[string]any{"type": "object"},
					},
				},
				"required": []string{"title", "type_id"},
			}),
		),
	),
	FindEntries: mcp.NewTool("find-entries",
		mcp.WithDescription("Search for entries when you don't have their IDs. Provide at least one of: id, name, or collection_id. Not required before edit-entry — if you already have the entry ID, call edit-entry directly."),
		mcp.WithString("id",
			mcp.Description("Entry UUID — return exactly this entry. If provided, all other parameters are ignored."),
		),
		mcp.WithString("collection_id",
			mcp.Description("Narrow results to a specific collection. Not required — omit to search across all collections."),
		),
		mcp.WithString("name",
			mcp.Description("Case-insensitive substring to match against entry titles."),
		),
		mcp.WithNumber("limit",
			mcp.Description("Maximum number of results to return (1-100, default 20)."),
		),
	),
	EditEntry: mcp.NewTool("edit-entry",
		mcp.WithDescription(`Update an existing entry by ID. Call this directly when you have the entry ID — no need to look it up with find-entries first.

Patch semantics: omit a field to keep its current value, provide it to replace. additional_fields are MERGED (existing keys preserved); use additional_fields_delete to remove keys.`),
		mcp.WithString("id",
			mcp.Required(),
			mcp.Description("UUID of the entry to edit"),
		),
		mcp.WithString("title",
			mcp.Description("New title (1-200 chars)"),
		),
		mcp.WithString("description",
			mcp.Description("New description (1-2000 chars)"),
		),
		mcp.WithString("type_id",
			mcp.Description("New type UUID — use get-entry-types to find valid values"),
		),
		mcp.WithString("collection_id",
			mcp.Description("New collection UUID to move the entry to. To remove the entry from all collections use collection_id_clear instead."),
		),
		mcp.WithBoolean("collection_id_clear",
			mcp.Description("Set to true to remove the entry from its current collection. Takes precedence over collection_id."),
		),
		mcp.WithNumber("score",
			mcp.Description("New score: 0 = new/haven't watched/read/played yet, 1 = bad, 2 = okay, 3 = great"),
		),
		mcp.WithString("date",
			mcp.Description("New watch/read/play date in YYYY-MM-DD format"),
		),
		mcp.WithObject("additional_fields",
			mcp.Description("Key-value pairs to merge into the existing additional_fields map. Existing keys not listed here are preserved."),
		),
		mcp.WithArray("additional_fields_delete",
			mcp.Description("List of additional_fields keys to remove. Applied after the merge of additional_fields."),
			mcp.WithStringItems(),
		),
		mcp.WithArray("images",
			mcp.Description(`Replacement images for the entry (max 3, max 5MB each). Each element: {"url": "https://..."} or {"data": "<base64>"}. First image becomes the cover. Replaces all existing images when provided.`),
			mcp.Items(map[string]any{"type": "object"}),
		),
	),
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

	// Look up the "mcp" system tag once per request; log a warning if missing.
	mcpTag, mcpTagErr := h.tagRepo.GetSystemTagByName(r.Context(), "mcp")
	if mcpTagErr != nil {
		h.log.Warn("mcp system tag not found — entries will not be auto-tagged", zap.Error(mcpTagErr))
	}

	mcpSrv := mcpserver.NewMCPServer("livlog", "1.0.0")

	// Register get-collections tool
	mcpSrv.AddTool(mcpToolDefs.GetCollections, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
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

	// Register get-entry-types tool
	mcpSrv.AddTool(mcpToolDefs.GetEntryTypes, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		types, err := h.typeService.GetAllTypes(ctx, userID)
		if err != nil {
			return nil, fmt.Errorf("failed to get entry types: %w", err)
		}

		type fieldResult struct {
			Key   string `json:"key"`
			Label string `json:"label"`
			Type  string `json:"type"`
		}
		type typeResult struct {
			ID     string        `json:"id"`
			Name   string        `json:"name"`
			Icon   string        `json:"icon"`
			Fields []fieldResult `json:"fields"`
		}

		results := make([]typeResult, len(types))
		for i, t := range types {
			fields := make([]fieldResult, len(t.Fields))
			for j, f := range t.Fields {
				fields[j] = fieldResult{Key: f.Key, Label: f.Label, Type: f.Type}
			}
			results[i] = typeResult{
				ID:     t.ID.String(),
				Name:   t.Name,
				Icon:   t.Icon,
				Fields: fields,
			}
		}

		jsonBytes, err := json.Marshal(results)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal entry types: %w", err)
		}

		return mcp.NewToolResultText(string(jsonBytes)), nil
	})

	// Register add-entries tool
	mcpSrv.AddTool(mcpToolDefs.AddEntries, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
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
			Title            string            `json:"title"`
			Description      string            `json:"description"`
			TypeID           string            `json:"type_id"`
			Score            int               `json:"score"`
			Date             string            `json:"date"`
			AdditionalFields map[string]string `json:"additional_fields"`
			Images           interface{}       `json:"images"`
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

			if e.TypeID == "" {
				return nil, fmt.Errorf("each entry must have a type_id — call get-entry-types to find valid values")
			}
			typeUUID, err := uuid.Parse(e.TypeID)
			if err != nil {
				return nil, fmt.Errorf("invalid type_id %q: %w", e.TypeID, err)
			}

			description := e.Description
			if description == "" {
				description = e.Title
			}

			score := e.Score
			if score < 0 || score > 3 {
				return nil, fmt.Errorf("invalid score %d for entry %q: must be 0-3", score, e.Title)
			}

			dateStr := e.Date
			if dateStr == "" {
				dateStr = today
			}

			date, err := time.Parse("2006-01-02", dateStr)
			if err != nil {
				return nil, fmt.Errorf("invalid date format for entry %q, use YYYY-MM-DD", e.Title)
			}

			additionalFields := e.AdditionalFields
			if additionalFields == nil {
				additionalFields = map[string]string{}
			}

			images, err := parseImages(ctx, e.Images)
			if err != nil {
				return nil, fmt.Errorf("invalid images for entry %q: %w", e.Title, err)
			}

			entry, err := h.entryService.CreateEntry(
				ctx,
				userID,
				&collectionUUID,
				&typeUUID,
				e.Title,
				description,
				score,
				date,
				additionalFields,
				images,
				nil,
			)
			if err != nil {
				return nil, fmt.Errorf("failed to create entry %q: %w", e.Title, err)
			}

			// Auto-tag entry with the "mcp" system tag.
			if mcpTag != nil {
				if tagErr := h.tagRepo.AddTagToEntry(ctx, entry.ID, mcpTag.ID); tagErr != nil {
					h.log.Warn("failed to auto-tag entry with mcp tag",
						zap.String("entry_id", entry.ID.String()),
						zap.Error(tagErr),
					)
				}
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

	// Register find-entries tool
	mcpSrv.AddTool(mcpToolDefs.FindEntries, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, ok := req.Params.Arguments.(map[string]interface{})
		if !ok {
			return nil, fmt.Errorf("invalid arguments format")
		}

		// Lookup by ID takes priority
		if idRaw, hasID := args["id"]; hasID {
			idStr, ok := idRaw.(string)
			if !ok {
				return nil, fmt.Errorf("id must be a string")
			}
			entryUUID, err := uuid.Parse(idStr)
			if err != nil {
				return nil, fmt.Errorf("invalid id: %w", err)
			}
			entry, err := h.entryService.GetEntryByID(ctx, entryUUID, userID)
			if err != nil {
				if errors.Is(err, repository.ErrEntryNotFound) {
					return nil, fmt.Errorf("entry not found")
				}
				return nil, fmt.Errorf("failed to get entry: %w", err)
			}
			result := entryToResult(entry)
			jsonBytes, err := json.Marshal(result)
			if err != nil {
				return nil, fmt.Errorf("failed to marshal entry: %w", err)
			}
			return mcp.NewToolResultText(string(jsonBytes)), nil
		}

		// List / search mode
		var collectionUUID *uuid.UUID
		if colRaw, hasCol := args["collection_id"]; hasCol {
			colStr, ok := colRaw.(string)
			if !ok {
				return nil, fmt.Errorf("collection_id must be a string")
			}
			parsed, err := uuid.Parse(colStr)
			if err != nil {
				return nil, fmt.Errorf("invalid collection_id: %w", err)
			}
			collectionUUID = &parsed
		}

		limit := 20
		if limitRaw, hasLimit := args["limit"]; hasLimit {
			if limitFloat, ok := limitRaw.(float64); ok {
				limit = int(limitFloat)
			}
		}
		if limit < 1 {
			limit = 1
		}
		if limit > 100 {
			limit = 100
		}

		nameFilter := ""
		if nameRaw, hasName := args["name"]; hasName {
			if nameStr, ok := nameRaw.(string); ok {
				nameFilter = nameStr
			}
		}

		var entries []*repository.Entry
		var fetchErr error

		if nameFilter != "" {
			// SearchEntries applies the ILIKE filter in the DB, so the limit is
			// respected correctly even when the collection has many entries.
			entries, fetchErr = h.entryService.SearchEntries(ctx, userID, nameFilter, limit, 0)
			if fetchErr != nil {
				return nil, fmt.Errorf("failed to search entries: %w", fetchErr)
			}
			// If a collection filter was also requested, apply it client-side.
			// SearchEntries already returned at most `limit` name-matched rows,
			// so this secondary filter may yield fewer results than limit.
			if collectionUUID != nil {
				filtered := entries[:0]
				for _, e := range entries {
					if e.CollectionID != nil && *e.CollectionID == *collectionUUID {
						filtered = append(filtered, e)
					}
				}
				entries = filtered
			}
		} else {
			// No name filter — DB handles the collection filter and limit directly.
			entries, fetchErr = h.entryService.GetEntriesByUserID(ctx, userID, collectionUUID, limit, 0)
			if fetchErr != nil {
				return nil, fmt.Errorf("failed to get entries: %w", fetchErr)
			}
		}

		results := make([]mcpEntryResult, 0, len(entries))
		for _, e := range entries {
			results = append(results, entryToResult(e))
		}

		jsonBytes, err := json.Marshal(results)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal entries: %w", err)
		}

		return mcp.NewToolResultText(string(jsonBytes)), nil
	})

	// Register edit-entry tool
	mcpSrv.AddTool(mcpToolDefs.EditEntry, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		args, ok := req.Params.Arguments.(map[string]interface{})
		if !ok {
			return nil, fmt.Errorf("invalid arguments format")
		}

		idRaw, ok := args["id"]
		if !ok {
			return nil, fmt.Errorf("id is required")
		}
		idStr, ok := idRaw.(string)
		if !ok {
			return nil, fmt.Errorf("id must be a string")
		}
		entryUUID, err := uuid.Parse(idStr)
		if err != nil {
			return nil, fmt.Errorf("invalid id: %w", err)
		}

		// Fetch current state to build the patch.
		// Note: UpdateEntry re-fetches the entry internally for its ownership check,
		// resulting in two DB reads per edit. This is safe but acknowledged as a known
		// inefficiency — eliminating it would require a lower-level service method.
		current, err := h.entryService.GetEntryByID(ctx, entryUUID, userID)
		if err != nil {
			if errors.Is(err, repository.ErrEntryNotFound) {
				return nil, fmt.Errorf("entry not found")
			}
			return nil, fmt.Errorf("failed to get entry: %w", err)
		}

		// Apply patches — only fields present in args are updated
		title := current.Title
		if v, ok := args["title"].(string); ok && v != "" {
			title = v
		}

		description := current.Description
		if v, ok := args["description"].(string); ok && v != "" {
			description = v
		}

		typeID := current.TypeID
		if v, ok := args["type_id"].(string); ok && v != "" {
			parsed, err := uuid.Parse(v)
			if err != nil {
				return nil, fmt.Errorf("invalid type_id: %w", err)
			}
			typeID = &parsed
		}

		// Preserve current value (including nil = "no collection") unless explicitly overridden.
		// collection_id_clear takes precedence: it sets collectionID to nil, which the repo
		// stores as NULL — effectively removing the entry from any collection.
		collectionID := current.CollectionID
		if clear, _ := args["collection_id_clear"].(bool); clear {
			collectionID = nil
		} else if v, ok := args["collection_id"].(string); ok && v != "" {
			parsed, err := uuid.Parse(v)
			if err != nil {
				return nil, fmt.Errorf("invalid collection_id: %w", err)
			}
			collectionID = &parsed
		}

		score := current.Score
		if v, ok := args["score"].(float64); ok {
			score = int(v)
			if score < 0 || score > 3 {
				return nil, fmt.Errorf("invalid score %d: must be 0-3", score)
			}
		}

		date := current.Date
		if v, ok := args["date"].(string); ok && v != "" {
			parsed, err := time.Parse("2006-01-02", v)
			if err != nil {
				return nil, fmt.Errorf("invalid date format, use YYYY-MM-DD")
			}
			date = parsed
		}

		// Start from a copy of the current map so we don't mutate cached state.
		additionalFields := make(map[string]string, len(current.AdditionalFields))
		for k, v := range current.AdditionalFields {
			additionalFields[k] = v
		}

		// Merge new keys into the copy — existing keys not mentioned are preserved.
		if v, ok := args["additional_fields"]; ok {
			afJSON, err := json.Marshal(v)
			if err != nil {
				return nil, fmt.Errorf("failed to process additional_fields: %w", err)
			}
			var af map[string]string
			if err := json.Unmarshal(afJSON, &af); err != nil {
				return nil, fmt.Errorf("additional_fields must be a flat string-to-string map")
			}
			for k, val := range af {
				additionalFields[k] = val
			}
		}

		// Delete keys listed in additional_fields_delete (applied after merge).
		if v, ok := args["additional_fields_delete"]; ok {
			deleteJSON, err := json.Marshal(v)
			if err != nil {
				return nil, fmt.Errorf("failed to process additional_fields_delete: %w", err)
			}
			var deleteKeys []string
			if err := json.Unmarshal(deleteJSON, &deleteKeys); err != nil {
				return nil, fmt.Errorf("additional_fields_delete must be an array of strings")
			}
			for _, k := range deleteKeys {
				delete(additionalFields, k)
			}
		}

		// Parse images if provided; nil means "don't touch existing images".
		var images []repository.EntryImage
		if imagesRaw, hasImages := args["images"]; hasImages {
			parsed, err := parseImages(ctx, imagesRaw)
			if err != nil {
				return nil, fmt.Errorf("invalid images: %w", err)
			}
			images = parsed
		}

		updated, err := h.entryService.UpdateEntry(
			ctx,
			entryUUID,
			userID,
			collectionID,
			typeID,
			title,
			description,
			score,
			date,
			additionalFields,
			images,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to update entry: %w", err)
		}

		result := entryToResult(updated)
		jsonBytes, err := json.Marshal(result)
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
