package handler

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

// testImageBytes is a small arbitrary byte sequence used as image data in tests.
// The backend stores raw bytes without format validation.
var testImageBytes = []byte("FAKE_IMAGE_DATA_FOR_TESTING_PURPOSES")

// ---- get-collections ----

func TestMCP_GetCollections_ReturnsList(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	env.createTestCollection(t, userID, "Movies")
	env.createTestCollection(t, userID, "Books")
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "get-collections", nil)

	type collResult struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		EntryCount int    `json:"entry_count"`
	}
	var cols []collResult
	if err := json.Unmarshal([]byte(text), &cols); err != nil {
		t.Fatalf("unmarshal collections: %v", err)
	}

	if len(cols) != 2 {
		t.Fatalf("expected 2 collections, got %d", len(cols))
	}

	names := map[string]bool{}
	for _, c := range cols {
		names[c.Name] = true
		if _, err := uuid.Parse(c.ID); err != nil {
			t.Errorf("collection ID %q is not a valid UUID", c.ID)
		}
	}
	if !names["Movies"] || !names["Books"] {
		t.Errorf("expected both Movies and Books collections, got %v", names)
	}
}

func TestMCP_GetCollections_EmptyList(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "get-collections", nil)

	var cols []interface{}
	if err := json.Unmarshal([]byte(text), &cols); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(cols) != 0 {
		t.Errorf("expected 0 collections, got %d", len(cols))
	}
}

// ---- get-entry-types ----

func TestMCP_GetEntryTypes_ReturnsSystemTypes(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "get-entry-types", nil)

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
	var types []typeResult
	if err := json.Unmarshal([]byte(text), &types); err != nil {
		t.Fatalf("unmarshal entry types: %v", err)
	}

	expectedNames := map[string]bool{
		"Movie": false,
		"Book":  false,
		"Game":  false,
		"Show":  false,
		"Album": false,
		"Other": false,
	}
	for _, tp := range types {
		if _, ok := expectedNames[tp.Name]; ok {
			expectedNames[tp.Name] = true
		}
		if _, err := uuid.Parse(tp.ID); err != nil {
			t.Errorf("type ID %q is not a valid UUID", tp.ID)
		}
		if tp.Fields == nil {
			t.Errorf("type %q has nil fields array", tp.Name)
		}
	}
	for name, found := range expectedNames {
		if !found {
			t.Errorf("expected system type %q but it was not returned", name)
		}
	}
}

// ---- add-entries ----

func TestMCP_AddEntries_SingleEntry(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "My Movies")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{
				"title":       "The Matrix",
				"description": "A sci-fi classic",
				"type_id":     movieTypeID.String(),
				"score":       2,
				"date":        "2024-01-15",
			},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var result addResult
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		t.Fatalf("unmarshal add-entries result: %v", err)
	}
	if len(result.CreatedIDs) != 1 {
		t.Fatalf("expected 1 created ID, got %d", len(result.CreatedIDs))
	}

	entryID, err := uuid.Parse(result.CreatedIDs[0])
	if err != nil {
		t.Fatalf("invalid entry UUID %q: %v", result.CreatedIDs[0], err)
	}

	// Verify entry exists in DB
	var title string
	var score int
	err = pool.QueryRow(context.Background(),
		`SELECT title, score FROM entries WHERE id = $1`, entryID,
	).Scan(&title, &score)
	if err != nil {
		t.Fatalf("entry not found in DB: %v", err)
	}
	if title != "The Matrix" {
		t.Errorf("expected title 'The Matrix', got %q", title)
	}
	if score != 2 {
		t.Errorf("expected score 2, got %d", score)
	}
}

func TestMCP_AddEntries_BatchEntries(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Batch Collection")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "Movie 1", "type_id": movieTypeID.String()},
			map[string]interface{}{"title": "Movie 2", "type_id": movieTypeID.String()},
			map[string]interface{}{"title": "Movie 3", "type_id": movieTypeID.String()},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var result addResult
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(result.CreatedIDs) != 3 {
		t.Errorf("expected 3 created IDs, got %d", len(result.CreatedIDs))
	}
}

func TestMCP_AddEntries_DefaultValues(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Defaults")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{
				"title":   "Minimal Entry",
				"type_id": movieTypeID.String(),
			},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var result addResult
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(result.CreatedIDs) != 1 {
		t.Fatalf("expected 1 created ID, got %d", len(result.CreatedIDs))
	}

	entryID, _ := uuid.Parse(result.CreatedIDs[0])

	var title, description string
	var score int
	err := pool.QueryRow(context.Background(),
		`SELECT title, description, score FROM entries WHERE id = $1`, entryID,
	).Scan(&title, &description, &score)
	if err != nil {
		t.Fatalf("entry not found: %v", err)
	}

	// description defaults to title
	if description != title {
		t.Errorf("expected description to default to title %q, got %q", title, description)
	}
	// score defaults to 0
	if score != 0 {
		t.Errorf("expected default score 0, got %d", score)
	}
}

func TestMCP_AddEntries_ValidationErrors(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Validation")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	cases := []struct {
		name  string
		entry map[string]interface{}
	}{
		{
			name:  "missing title",
			entry: map[string]interface{}{"type_id": movieTypeID.String()},
		},
		{
			name:  "missing type_id",
			entry: map[string]interface{}{"title": "No Type"},
		},
		{
			name:  "score out of range",
			entry: map[string]interface{}{"title": "Bad Score", "type_id": movieTypeID.String(), "score": 5},
		},
		{
			name:  "invalid date format",
			entry: map[string]interface{}{"title": "Bad Date", "type_id": movieTypeID.String(), "date": "not-a-date"},
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			body := map[string]interface{}{
				"jsonrpc": "2.0",
				"id":      1,
				"method":  "tools/call",
				"params": map[string]interface{}{
					"name": "add-entries",
					"arguments": map[string]interface{}{
						"collection_id": collID.String(),
						"entries":       []interface{}{tc.entry},
					},
				},
			}

			resp := callMCPRaw(t, env, uniqueCode, body)
			if !containsError(resp) {
				t.Errorf("expected error for case %q, got: %s", tc.name, resp)
			}
		})
	}
}

// callMCPRaw sends a raw JSON-RPC request and returns the raw response body.
func callMCPRaw(t *testing.T, env *testEnv, uniqueCode string, body map[string]interface{}) string {
	t.Helper()

	bodyBytes, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("callMCPRaw marshal: %v", err)
	}

	r := chi.NewRouter()
	env.handler.RegisterRoutes(r)

	req := httptest.NewRequest(http.MethodPost, "/api/mcp/"+uniqueCode, bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	return w.Body.String()
}

// containsError checks whether a response body contains any indication of an error.
func containsError(body string) bool {
	return strings.Contains(body, `"error"`) ||
		strings.Contains(body, `"isError":true`) ||
		strings.Contains(body, `"is_error":true`)
}

func TestMCP_AddEntries_WithBase64Image(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Image Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	b64 := base64.StdEncoding.EncodeToString(testImageBytes)

	text := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{
				"title":   "Entry With Image",
				"type_id": movieTypeID.String(),
				"images":  []interface{}{map[string]interface{}{"data": b64}},
			},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var result addResult
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(result.CreatedIDs) != 1 {
		t.Fatalf("expected 1 created ID, got %d", len(result.CreatedIDs))
	}

	entryID, _ := uuid.Parse(result.CreatedIDs[0])

	var imageCount int
	err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM entry_images WHERE entry_id = $1 AND is_cover = true`, entryID,
	).Scan(&imageCount)
	if err != nil {
		t.Fatalf("query entry_images: %v", err)
	}
	if imageCount != 1 {
		t.Errorf("expected 1 cover image, got %d", imageCount)
	}
}

func TestMCP_AddEntries_WithURLImage(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	// Start a local httptest server that serves image bytes.
	imgServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		_, _ = w.Write(testImageBytes)
	}))
	defer imgServer.Close()

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "URL Image Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{
				"title":   "Entry With URL Image",
				"type_id": movieTypeID.String(),
				"images":  []interface{}{map[string]interface{}{"url": imgServer.URL + "/image.jpg"}},
			},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var result addResult
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(result.CreatedIDs) != 1 {
		t.Fatalf("expected 1 created ID, got %d", len(result.CreatedIDs))
	}

	entryID, _ := uuid.Parse(result.CreatedIDs[0])

	var imageCount int
	err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM entry_images WHERE entry_id = $1`, entryID,
	).Scan(&imageCount)
	if err != nil {
		t.Fatalf("query entry_images: %v", err)
	}
	if imageCount != 1 {
		t.Errorf("expected 1 image from URL, got %d", imageCount)
	}
}

func TestMCP_AddEntries_AutoTagsMCP(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Tag Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	text := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "Tagged Movie", "type_id": movieTypeID.String()},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var result addResult
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(result.CreatedIDs) != 1 {
		t.Fatalf("expected 1 created ID, got %d", len(result.CreatedIDs))
	}

	entryID, _ := uuid.Parse(result.CreatedIDs[0])

	var tagCount int
	err := pool.QueryRow(context.Background(), `
		SELECT COUNT(*) FROM entry_tags et
		JOIN tags t ON t.id = et.tag_id
		WHERE et.entry_id = $1 AND t.name = 'mcp' AND t.user_id IS NULL
	`, entryID).Scan(&tagCount)
	if err != nil {
		t.Fatalf("query entry_tags: %v", err)
	}
	if tagCount != 1 {
		t.Errorf("expected 1 mcp tag on entry, got %d", tagCount)
	}
}

func TestMCP_AddEntries_ImageLimitExceeded(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Image Limit")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	b64 := base64.StdEncoding.EncodeToString(testImageBytes)
	images := make([]interface{}, 4)
	for i := range images {
		images[i] = map[string]interface{}{"data": b64}
	}

	body := map[string]interface{}{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]interface{}{
			"name": "add-entries",
			"arguments": map[string]interface{}{
				"collection_id": collID.String(),
				"entries": []interface{}{
					map[string]interface{}{
						"title":   "Too Many Images",
						"type_id": movieTypeID.String(),
						"images":  images,
					},
				},
			},
		},
	}

	resp := callMCPRaw(t, env, uniqueCode, body)
	if !containsError(resp) {
		t.Errorf("expected error for exceeding image limit, got: %s", resp)
	}
}

// ---- find-entries ----

func TestMCP_FindEntries_ByID(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Find Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	// Create an entry
	addText := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "Find Me", "type_id": movieTypeID.String(), "score": 3},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var ar addResult
	if err := json.Unmarshal([]byte(addText), &ar); err != nil {
		t.Fatalf("unmarshal add: %v", err)
	}
	entryID := ar.CreatedIDs[0]

	// Find by ID
	findText := env.callMCPTool(t, uniqueCode, "find-entries", map[string]interface{}{
		"id": entryID,
	})

	type entryResult struct {
		ID    string `json:"id"`
		Title string `json:"title"`
		Score int    `json:"score"`
	}
	var entry entryResult
	if err := json.Unmarshal([]byte(findText), &entry); err != nil {
		t.Fatalf("unmarshal find: %v", err)
	}
	if entry.ID != entryID {
		t.Errorf("expected ID %q, got %q", entryID, entry.ID)
	}
	if entry.Title != "Find Me" {
		t.Errorf("expected title 'Find Me', got %q", entry.Title)
	}
	if entry.Score != 3 {
		t.Errorf("expected score 3, got %d", entry.Score)
	}
}

func TestMCP_FindEntries_ByCollection(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collA := env.createTestCollection(t, userID, "Collection A")
	collB := env.createTestCollection(t, userID, "Collection B")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	// Add 2 entries to collection A
	env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collA.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "A1", "type_id": movieTypeID.String()},
			map[string]interface{}{"title": "A2", "type_id": movieTypeID.String()},
		},
	})

	// Add 1 entry to collection B
	env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collB.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "B1", "type_id": movieTypeID.String()},
		},
	})

	// Find by collection_id=A
	findText := env.callMCPTool(t, uniqueCode, "find-entries", map[string]interface{}{
		"collection_id": collA.String(),
	})

	var entries []map[string]interface{}
	if err := json.Unmarshal([]byte(findText), &entries); err != nil {
		t.Fatalf("unmarshal find: %v", err)
	}
	if len(entries) != 2 {
		t.Errorf("expected 2 entries in collection A, got %d", len(entries))
	}
}

func TestMCP_FindEntries_ByName(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Search Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "The Matrix", "type_id": movieTypeID.String()},
			map[string]interface{}{"title": "Matrix Reloaded", "type_id": movieTypeID.String()},
			map[string]interface{}{"title": "Inception", "type_id": movieTypeID.String()},
		},
	})

	findText := env.callMCPTool(t, uniqueCode, "find-entries", map[string]interface{}{
		"name": "matrix",
	})

	var entries []map[string]interface{}
	if err := json.Unmarshal([]byte(findText), &entries); err != nil {
		t.Fatalf("unmarshal find: %v", err)
	}
	if len(entries) != 2 {
		t.Errorf("expected 2 matrix entries, got %d", len(entries))
	}
}

func TestMCP_FindEntries_NotFound(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	uniqueCode := env.enableMCP(t, userID)

	randomID := uuid.New().String()

	body := map[string]interface{}{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]interface{}{
			"name":      "find-entries",
			"arguments": map[string]interface{}{"id": randomID},
		},
	}

	resp := callMCPRaw(t, env, uniqueCode, body)
	if !containsError(resp) {
		t.Errorf("expected error for non-existent entry, got: %s", resp)
	}
}

// ---- edit-entry ----

func TestMCP_EditEntry_PatchTitle(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Edit Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	addText := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "Old Title", "type_id": movieTypeID.String(), "score": 1},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var ar addResult
	if err := json.Unmarshal([]byte(addText), &ar); err != nil {
		t.Fatalf("unmarshal add: %v", err)
	}
	entryID := ar.CreatedIDs[0]

	editText := env.callMCPTool(t, uniqueCode, "edit-entry", map[string]interface{}{
		"id":    entryID,
		"title": "New Title",
	})

	type entryResult struct {
		ID    string `json:"id"`
		Title string `json:"title"`
		Score int    `json:"score"`
	}
	var entry entryResult
	if err := json.Unmarshal([]byte(editText), &entry); err != nil {
		t.Fatalf("unmarshal edit: %v", err)
	}
	if entry.Title != "New Title" {
		t.Errorf("expected title 'New Title', got %q", entry.Title)
	}
	// Score should be preserved at 1
	if entry.Score != 1 {
		t.Errorf("expected score 1 to be preserved, got %d", entry.Score)
	}
}

func TestMCP_EditEntry_MergeAdditionalFields(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Merge Fields Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	addText := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{
				"title":             "With Fields",
				"type_id":           movieTypeID.String(),
				"additional_fields": map[string]interface{}{"Year": "2020", "Director": "Nolan"},
			},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var ar addResult
	if err := json.Unmarshal([]byte(addText), &ar); err != nil {
		t.Fatalf("unmarshal add: %v", err)
	}
	entryID := ar.CreatedIDs[0]

	editText := env.callMCPTool(t, uniqueCode, "edit-entry", map[string]interface{}{
		"id":                entryID,
		"additional_fields": map[string]interface{}{"Year": "2021"},
	})

	type entryResult struct {
		AdditionalFields map[string]string `json:"additional_fields"`
	}
	var entry entryResult
	if err := json.Unmarshal([]byte(editText), &entry); err != nil {
		t.Fatalf("unmarshal edit: %v", err)
	}
	if entry.AdditionalFields["Year"] != "2021" {
		t.Errorf("expected Year=2021, got %q", entry.AdditionalFields["Year"])
	}
	if entry.AdditionalFields["Director"] != "Nolan" {
		t.Errorf("expected Director=Nolan to be preserved, got %q", entry.AdditionalFields["Director"])
	}
}

func TestMCP_EditEntry_DeleteAdditionalFields(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Delete Fields Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	addText := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{
				"title":             "Fields To Delete",
				"type_id":           movieTypeID.String(),
				"additional_fields": map[string]interface{}{"A": "1", "B": "2"},
			},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var ar addResult
	if err := json.Unmarshal([]byte(addText), &ar); err != nil {
		t.Fatalf("unmarshal add: %v", err)
	}
	entryID := ar.CreatedIDs[0]

	editText := env.callMCPTool(t, uniqueCode, "edit-entry", map[string]interface{}{
		"id":                       entryID,
		"additional_fields_delete": []interface{}{"A"},
	})

	type entryResult struct {
		AdditionalFields map[string]string `json:"additional_fields"`
	}
	var entry entryResult
	if err := json.Unmarshal([]byte(editText), &entry); err != nil {
		t.Fatalf("unmarshal edit: %v", err)
	}
	if _, hasA := entry.AdditionalFields["A"]; hasA {
		t.Errorf("expected field A to be deleted, but it is still present")
	}
	if entry.AdditionalFields["B"] != "2" {
		t.Errorf("expected field B=2 to be preserved, got %q", entry.AdditionalFields["B"])
	}
}

func TestMCP_EditEntry_UpdateScore(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Score Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	addText := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "Score Movie", "type_id": movieTypeID.String(), "score": 0},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var ar addResult
	if err := json.Unmarshal([]byte(addText), &ar); err != nil {
		t.Fatalf("unmarshal add: %v", err)
	}
	entryID := ar.CreatedIDs[0]

	editText := env.callMCPTool(t, uniqueCode, "edit-entry", map[string]interface{}{
		"id":    entryID,
		"score": 3,
	})

	type entryResult struct {
		Score int `json:"score"`
	}
	var entry entryResult
	if err := json.Unmarshal([]byte(editText), &entry); err != nil {
		t.Fatalf("unmarshal edit: %v", err)
	}
	if entry.Score != 3 {
		t.Errorf("expected score 3, got %d", entry.Score)
	}
}

func TestMCP_EditEntry_WithImages(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Edit Images Test")
	movieTypeID := env.getMovieTypeID(t)
	uniqueCode := env.enableMCP(t, userID)

	// Create entry without images
	addText := env.callMCPTool(t, uniqueCode, "add-entries", map[string]interface{}{
		"collection_id": collID.String(),
		"entries": []interface{}{
			map[string]interface{}{"title": "No Image Entry", "type_id": movieTypeID.String()},
		},
	})

	type addResult struct {
		CreatedIDs []string `json:"created_ids"`
	}
	var ar addResult
	if err := json.Unmarshal([]byte(addText), &ar); err != nil {
		t.Fatalf("unmarshal add: %v", err)
	}
	entryID := ar.CreatedIDs[0]
	entryUUID, _ := uuid.Parse(entryID)

	// Verify no images initially
	var initialCount int
	_ = pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM entry_images WHERE entry_id = $1`, entryUUID,
	).Scan(&initialCount)
	if initialCount != 0 {
		t.Fatalf("expected 0 initial images, got %d", initialCount)
	}

	b64 := base64.StdEncoding.EncodeToString(testImageBytes)

	env.callMCPTool(t, uniqueCode, "edit-entry", map[string]interface{}{
		"id":     entryID,
		"images": []interface{}{map[string]interface{}{"data": b64}},
	})

	var imageCount int
	err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM entry_images WHERE entry_id = $1`, entryUUID,
	).Scan(&imageCount)
	if err != nil {
		t.Fatalf("query entry_images: %v", err)
	}
	if imageCount != 1 {
		t.Errorf("expected 1 image after edit, got %d", imageCount)
	}
}
