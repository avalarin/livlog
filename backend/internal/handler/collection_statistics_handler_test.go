package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/avalarin/livlog/backend/internal/middleware"
)

// ---- HTTP helpers ----

// withAuth wraps an http.Handler, injecting userID into the request context.
func withAuth(userID string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := context.WithValue(r.Context(), middleware.UserIDContextKey, userID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// buildStatsRouter creates a chi router with auth middleware and collection handler routes.
func buildStatsRouter(env *testEnv, userID string) chi.Router {
	r := chi.NewRouter()
	r.Use(func(next http.Handler) http.Handler {
		return withAuth(userID, next)
	})
	collHandler := NewCollectionHandler(env.collectionService, env.log)
	collHandler.RegisterRoutes(r)
	return r
}

// doRequest sends an HTTP request to the router and returns the recorder.
func doRequest(r chi.Router, method, path string, body []byte) *httptest.ResponseRecorder {
	var req *http.Request
	if body != nil {
		req = httptest.NewRequest(method, path, bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
	} else {
		req = httptest.NewRequest(method, path, nil)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// ---- Fixture helpers ----

// createTestEntry inserts an entry directly into the database and returns its UUID.
// score=0 means backlog (unrated). additionalFields is a JSON map string (or "" for empty).
func createTestEntry(
	t *testing.T,
	pool *pgxpool.Pool,
	userID, collectionID uuid.UUID,
	title string,
	score int,
	date string, // "YYYY-MM-DD", or "" to use NULL
	additionalFields string, // raw JSON object string e.g. `{"Genre":"Action"}`, or "" for empty
) uuid.UUID {
	t.Helper()

	// Find any entry type to satisfy the FK constraint.
	var typeID uuid.UUID
	err := pool.QueryRow(context.Background(),
		`SELECT id FROM entry_types LIMIT 1`,
	).Scan(&typeID)
	if err != nil {
		t.Fatalf("createTestEntry: could not find entry_type: %v", err)
	}

	af := "{}"
	if additionalFields != "" {
		af = additionalFields
	}

	// description is always set to the same value as title, but using a separate
	// parameter avoids the "inconsistent types deduced for parameter $N" error that
	// pgx raises when the same placeholder appears in positions with different inferred types.
	var entryID uuid.UUID
	if date == "" {
		err = pool.QueryRow(context.Background(), `
			INSERT INTO entries (collection_id, user_id, type_id, title, description, score, additional_fields)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			RETURNING id`,
			collectionID, userID, typeID, title, title, score, af,
		).Scan(&entryID)
	} else {
		err = pool.QueryRow(context.Background(), `
			INSERT INTO entries (collection_id, user_id, type_id, title, description, score, date, additional_fields)
			VALUES ($1, $2, $3, $4, $5, $6, $7::date, $8)
			RETURNING id`,
			collectionID, userID, typeID, title, title, score, date, af,
		).Scan(&entryID)
	}
	if err != nil {
		t.Fatalf("createTestEntry: %v", err)
	}

	return entryID
}

// createReadOnlyShare creates a second user and shares the collection with them as "read".
// Returns the second user's ID.
func createReadOnlyShare(t *testing.T, pool *pgxpool.Pool, ownerID, collectionID uuid.UUID) uuid.UUID {
	t.Helper()

	email := fmt.Sprintf("reader+%s@example.com", uuid.New().String())
	var readerID uuid.UUID
	err := pool.QueryRow(context.Background(),
		`INSERT INTO users (email, email_verified) VALUES ($1, true) RETURNING id`,
		email,
	).Scan(&readerID)
	if err != nil {
		t.Fatalf("createReadOnlyShare: create user: %v", err)
	}

	_, err = pool.Exec(context.Background(), `
		INSERT INTO collection_shares (collection_id, owner_id, shared_with_user_id, permission_level)
		VALUES ($1, $2, $3, 'read')`,
		collectionID, ownerID, readerID,
	)
	if err != nil {
		t.Fatalf("createReadOnlyShare: insert share: %v", err)
	}

	return readerID
}

// invalidateStatCache deletes all cached stat values so the next GET re-computes them.
func invalidateStatCache(t *testing.T, pool *pgxpool.Pool, collectionID uuid.UUID) {
	t.Helper()
	_, err := pool.Exec(context.Background(),
		`DELETE FROM collection_statistic_values WHERE collection_id = $1`, collectionID)
	if err != nil {
		t.Fatalf("invalidateStatCache: %v", err)
	}
}

// parseStatResponse unmarshals the GET /statistics JSON body into a map keyed by Title.
func parseStatResponse(t *testing.T, body []byte) map[string]string {
	t.Helper()
	var items []struct {
		Title        string `json:"title"`
		DisplayValue string `json:"display_value"`
	}
	if err := json.Unmarshal(body, &items); err != nil {
		t.Fatalf("parseStatResponse: %v\nbody: %s", err, body)
	}
	out := make(map[string]string, len(items))
	for _, item := range items {
		out[item.Title] = item.DisplayValue
	}
	return out
}

// ---- GET /collections/{id}/statistics ----

func TestGetCollectionStatistics_EmptyCollection(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Empty Stats Coll")

	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	stats := parseStatResponse(t, w.Body.Bytes())

	// Default 3 stats must be present.
	if len(stats) != 3 {
		t.Errorf("expected 3 default stats, got %d: %v", len(stats), stats)
	}

	totalVal, ok := stats["Total"]
	if !ok {
		t.Fatalf("expected 'Total' stat to be present")
	}
	if totalVal != "0" {
		t.Errorf("expected total_entries=0, got %q", totalVal)
	}

	backlogVal, ok := stats["Backlog"]
	if !ok {
		t.Fatalf("expected 'Backlog' stat to be present")
	}
	if backlogVal != "0" {
		t.Errorf("expected backlog=0, got %q", backlogVal)
	}

	lastVal, ok := stats["Last Entry"]
	if !ok {
		t.Fatalf("expected 'Last Entry' stat to be present")
	}
	if lastVal != "—" {
		t.Errorf("expected last_entry=—, got %q", lastVal)
	}
}

func TestGetCollectionStatistics_WithEntries(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Stats With Entries")

	// 2 rated, 1 backlog
	createTestEntry(t, pool, userID, collID, "Entry A", 3, "2024-06-15", "")
	createTestEntry(t, pool, userID, collID, "Entry B", 2, "2024-08-20", "")
	createTestEntry(t, pool, userID, collID, "Entry C", 0, "2024-01-01", "") // backlog

	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	stats := parseStatResponse(t, w.Body.Bytes())

	if stats["Total"] != "3" {
		t.Errorf("expected total=3, got %q", stats["Total"])
	}
	if stats["Backlog"] != "1" {
		t.Errorf("expected backlog=1, got %q", stats["Backlog"])
	}
	// Last entry date should reflect the most recent date: Aug 20, 2024
	if stats["Last Entry"] != "Aug 20, 2024" {
		t.Errorf("expected last_entry='Aug 20, 2024', got %q", stats["Last Entry"])
	}
}

func TestGetCollectionStatistics_NotFound(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)

	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodGet, "/collections/"+uuid.New().String()+"/statistics", nil)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestGetCollectionStatistics_NoAuth(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "NoAuth Stats")

	// Build router without auth middleware.
	r := chi.NewRouter()
	collHandler := NewCollectionHandler(env.collectionService, env.log)
	collHandler.RegisterRoutes(r)

	req := httptest.NewRequest(http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d: %s", w.Code, w.Body.String())
	}
}

// ---- GET /collections/{id}/statistics/available ----

func TestGetAvailableStatistics_EmptyCollection(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Avail Stats Empty")

	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics/available", nil)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var items []struct {
		ID        string `json:"id"`
		Title     string `json:"title"`
		IsEnabled bool   `json:"is_enabled"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &items); err != nil {
		t.Fatalf("unmarshal available stats: %v", err)
	}

	// Only builtin stats should be returned for an empty collection (no field_aggregation
	// stats become available until entries with the relevant fields exist).
	builtinIDs := map[string]bool{
		"total_entries": false,
		"backlog":       false,
		"last_entry":    false,
		"avg_score":     false,
		"rated_pct":     false,
	}
	for _, item := range items {
		if _, isBuiltin := builtinIDs[item.ID]; !isBuiltin {
			t.Errorf("unexpected non-builtin stat %q in available list for empty collection", item.ID)
		}
		builtinIDs[item.ID] = true
	}
	for id, seen := range builtinIDs {
		if !seen {
			t.Errorf("expected builtin stat %q to be present in available list", id)
		}
	}
}

func TestGetAvailableStatistics_WithFieldData(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Avail Stats Fields")

	// Add an entry with Genre field — this should unlock top_genre and unique_genres.
	createTestEntry(t, pool, userID, collID, "Action Movie", 3, "2024-01-01", `{"Genre":"Action"}`)

	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics/available", nil)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var items []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &items); err != nil {
		t.Fatalf("unmarshal available stats: %v", err)
	}

	idSet := make(map[string]bool, len(items))
	for _, item := range items {
		idSet[item.ID] = true
	}

	for _, expected := range []string{"top_genre", "unique_genres"} {
		if !idSet[expected] {
			t.Errorf("expected %q to appear in available stats after adding Genre field", expected)
		}
	}
}

// ---- PUT /collections/{id}/statistics/config ----

func TestUpdateStatisticsConfig_Success(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Config Update")

	r := buildStatsRouter(env, userID.String())

	// Update config to include avg_score in addition to (or instead of) the defaults.
	// The service's GetCollectionStatistics always calls EnsureDefaultStatConfigs which
	// re-seeds total_entries/backlog/last_entry via ON CONFLICT DO NOTHING. This means
	// after a PUT that removes defaults, the next GET re-adds them. So a PUT with
	// ["total_entries","backlog","last_entry","avg_score"] gives us a predictable outcome.
	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"total_entries", "backlog", "last_entry", "avg_score"},
	})
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// GET /statistics — should return exactly 4 stats in the configured order.
	w2 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("expected 200 on GET, got %d: %s", w2.Code, w2.Body.String())
	}

	stats := parseStatResponse(t, w2.Body.Bytes())
	if len(stats) != 4 {
		t.Errorf("expected 4 stats after config update, got %d: %v", len(stats), stats)
	}
	if _, ok := stats["Avg Score"]; !ok {
		t.Errorf("expected 'Avg Score' stat to be present, got: %v", stats)
	}

	// Verify the response JSON preserves order — Avg Score must be last.
	var rawItems []struct {
		Title string `json:"title"`
	}
	if err := json.Unmarshal(w2.Body.Bytes(), &rawItems); err != nil {
		t.Fatalf("unmarshal ordered stats: %v", err)
	}
	if len(rawItems) < 4 || rawItems[3].Title != "Avg Score" {
		t.Errorf("expected Avg Score at position 3, got items: %v", rawItems)
	}
}

func TestUpdateStatisticsConfig_InvalidBody(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Config Invalid")

	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config",
		[]byte(`{not valid json`))

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestUpdateStatisticsConfig_ReadOnlyUser(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	ownerID := env.createTestUser(t)
	collID := env.createTestCollection(t, ownerID, "Config ReadOnly")
	readerID := createReadOnlyShare(t, pool, ownerID, collID)

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"total_entries"},
	})
	r := buildStatsRouter(env, readerID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)

	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403, got %d: %s", w.Code, w.Body.String())
	}
}

func TestUpdateStatisticsConfig_NotFound(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"total_entries"},
	})
	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+uuid.New().String()+"/statistics/config", body)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

// ---- Builtin stat computation ----

func TestStatComputation_AvgScore(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "AvgScore Comp")

	// Scores 2 and 2 — average 2.0. (valid range is 0–3)
	createTestEntry(t, pool, userID, collID, "E1", 2, "2024-01-01", "")
	createTestEntry(t, pool, userID, collID, "E2", 2, "2024-01-02", "")
	// Unrated entry — should be excluded from average.
	createTestEntry(t, pool, userID, collID, "E3", 0, "2024-01-03", "")

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"avg_score"},
	})
	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)
	if w.Code != http.StatusOK {
		t.Fatalf("config update: %d %s", w.Code, w.Body.String())
	}

	invalidateStatCache(t, pool, collID)
	w2 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("GET stats: %d %s", w2.Code, w2.Body.String())
	}

	stats := parseStatResponse(t, w2.Body.Bytes())
	if stats["Avg Score"] != "2.0" {
		t.Errorf("expected avg_score=2.0, got %q", stats["Avg Score"])
	}
}

func TestStatComputation_RatedPct(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "RatedPct Comp")

	// 2 rated, 2 unrated → 50%
	createTestEntry(t, pool, userID, collID, "Rated1", 3, "2024-01-01", "")
	createTestEntry(t, pool, userID, collID, "Rated2", 1, "2024-01-02", "")
	createTestEntry(t, pool, userID, collID, "Unrated1", 0, "", "")
	createTestEntry(t, pool, userID, collID, "Unrated2", 0, "", "")

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"rated_pct"},
	})
	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)
	if w.Code != http.StatusOK {
		t.Fatalf("config update: %d %s", w.Code, w.Body.String())
	}

	invalidateStatCache(t, pool, collID)
	w2 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("GET stats: %d %s", w2.Code, w2.Body.String())
	}

	stats := parseStatResponse(t, w2.Body.Bytes())
	if stats["Rated %"] != "50%" {
		t.Errorf("expected rated_pct=50%%, got %q", stats["Rated %"])
	}
}

func TestStatComputation_AllBuiltins(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "AllBuiltins Comp")

	// 3 entries: scores 2, 2, 0 (backlog); dates 2023-05-10, 2024-11-30, 2024-01-01.
	// Valid score range is 0–3.
	createTestEntry(t, pool, userID, collID, "Old Movie", 2, "2023-05-10", "")
	createTestEntry(t, pool, userID, collID, "New Movie", 2, "2024-11-30", "")
	createTestEntry(t, pool, userID, collID, "Backlog Item", 0, "2024-01-01", "")

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"total_entries", "backlog", "last_entry", "avg_score", "rated_pct"},
	})
	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)
	if w.Code != http.StatusOK {
		t.Fatalf("config update: %d %s", w.Code, w.Body.String())
	}

	invalidateStatCache(t, pool, collID)
	w2 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("GET stats: %d %s", w2.Code, w2.Body.String())
	}

	stats := parseStatResponse(t, w2.Body.Bytes())

	if stats["Total"] != "3" {
		t.Errorf("expected total=3, got %q", stats["Total"])
	}
	if stats["Backlog"] != "1" {
		t.Errorf("expected backlog=1, got %q", stats["Backlog"])
	}
	if stats["Last Entry"] != "Nov 30, 2024" {
		t.Errorf("expected last_entry='Nov 30, 2024', got %q", stats["Last Entry"])
	}
	if stats["Avg Score"] != "2.0" {
		t.Errorf("expected avg_score=2.0 (avg of 2 and 2), got %q", stats["Avg Score"])
	}
	// 2 out of 3 rated → 66% (2/3 * 100 = 66.6, truncated to int)
	if stats["Rated %"] != "66%" {
		t.Errorf("expected rated_pct=66%%, got %q", stats["Rated %"])
	}
}

// ---- Field aggregation computation ----

func TestStatComputation_CountTop(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "CountTop Comp")

	// Action appears 3×, Drama 1×.
	createTestEntry(t, pool, userID, collID, "A1", 1, "2024-01-01", `{"Genre":"Action"}`)
	createTestEntry(t, pool, userID, collID, "A2", 1, "2024-01-02", `{"Genre":"Action"}`)
	createTestEntry(t, pool, userID, collID, "A3", 1, "2024-01-03", `{"Genre":"Action"}`)
	createTestEntry(t, pool, userID, collID, "D1", 1, "2024-01-04", `{"Genre":"Drama"}`)

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"top_genre"},
	})
	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)
	if w.Code != http.StatusOK {
		t.Fatalf("config update: %d %s", w.Code, w.Body.String())
	}

	invalidateStatCache(t, pool, collID)
	w2 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("GET stats: %d %s", w2.Code, w2.Body.String())
	}

	stats := parseStatResponse(t, w2.Body.Bytes())
	if stats["Top Genre"] != "Action" {
		t.Errorf("expected top_genre='Action', got %q", stats["Top Genre"])
	}
}

func TestStatComputation_MinMax(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "MinMax Comp")

	createTestEntry(t, pool, userID, collID, "Old", 1, "2024-01-01", `{"Year":"1995"}`)
	createTestEntry(t, pool, userID, collID, "Mid", 1, "2024-01-02", `{"Year":"2010"}`)
	createTestEntry(t, pool, userID, collID, "New", 1, "2024-01-03", `{"Year":"2023"}`)

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"min_year", "max_year"},
	})
	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)
	if w.Code != http.StatusOK {
		t.Fatalf("config update: %d %s", w.Code, w.Body.String())
	}

	invalidateStatCache(t, pool, collID)
	w2 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("GET stats: %d %s", w2.Code, w2.Body.String())
	}

	stats := parseStatResponse(t, w2.Body.Bytes())
	if stats["Earliest Year"] != "1995" {
		t.Errorf("expected min_year=1995, got %q", stats["Earliest Year"])
	}
	if stats["Latest Year"] != "2023" {
		t.Errorf("expected max_year=2023, got %q", stats["Latest Year"])
	}
}

func TestStatComputation_CountDistinct(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "CountDistinct Comp")

	// 3 entries with 2 distinct genres.
	createTestEntry(t, pool, userID, collID, "A1", 1, "2024-01-01", `{"Genre":"Action"}`)
	createTestEntry(t, pool, userID, collID, "A2", 1, "2024-01-02", `{"Genre":"Action"}`)
	createTestEntry(t, pool, userID, collID, "D1", 1, "2024-01-03", `{"Genre":"Drama"}`)

	body, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"unique_genres"},
	})
	r := buildStatsRouter(env, userID.String())
	w := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", body)
	if w.Code != http.StatusOK {
		t.Fatalf("config update: %d %s", w.Code, w.Body.String())
	}

	invalidateStatCache(t, pool, collID)
	w2 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w2.Code != http.StatusOK {
		t.Fatalf("GET stats: %d %s", w2.Code, w2.Body.String())
	}

	stats := parseStatResponse(t, w2.Body.Bytes())
	if stats["Unique Genres"] != "2" {
		t.Errorf("expected unique_genres=2, got %q", stats["Unique Genres"])
	}
}

// ---- Full flow ----

func TestStatisticsFullFlow(t *testing.T) {
	pool := startSharedDB(t)
	env := setupTestEnv(t, pool)

	userID := env.createTestUser(t)
	collID := env.createTestCollection(t, userID, "Full Flow")

	r := buildStatsRouter(env, userID.String())

	// Step 1: Get defaults — should return 3 default stats for empty collection.
	w := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("step1 GET: %d %s", w.Code, w.Body.String())
	}
	stats := parseStatResponse(t, w.Body.Bytes())
	if len(stats) != 3 {
		t.Errorf("step1: expected 3 default stats, got %d", len(stats))
	}
	if stats["Total"] != "0" {
		t.Errorf("step1: expected total=0, got %q", stats["Total"])
	}

	// Step 2: Add two entries.
	createTestEntry(t, pool, userID, collID, "Movie 1", 3, "2024-03-01", `{"Genre":"Sci-Fi"}`)
	createTestEntry(t, pool, userID, collID, "Movie 2", 0, "2024-05-15", `{"Genre":"Action"}`)

	// Step 3: Customize config to include all 3 defaults + avg_score + top_genre.
	// GetCollectionStatistics always calls EnsureDefaultStatConfigs which re-seeds
	// total_entries/backlog/last_entry via ON CONFLICT DO NOTHING. Including them
	// explicitly in the PUT ensures a predictable, fully-controlled config.
	configBody, _ := json.Marshal(map[string]interface{}{
		"statistic_ids": []string{"total_entries", "backlog", "last_entry", "avg_score", "top_genre"},
	})
	w2 := doRequest(r, http.MethodPut, "/collections/"+collID.String()+"/statistics/config", configBody)
	if w2.Code != http.StatusOK {
		t.Fatalf("step3 PUT config: %d %s", w2.Code, w2.Body.String())
	}

	// Step 4: Verify new stats reflect entries.
	invalidateStatCache(t, pool, collID)
	w3 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w3.Code != http.StatusOK {
		t.Fatalf("step4 GET: %d %s", w3.Code, w3.Body.String())
	}
	stats2 := parseStatResponse(t, w3.Body.Bytes())
	if len(stats2) != 5 {
		t.Errorf("step4: expected 5 stats, got %d: %v", len(stats2), stats2)
	}
	if stats2["Total"] != "2" {
		t.Errorf("step4: expected total=2, got %q", stats2["Total"])
	}
	// Only Movie 1 has score>0 (score=3), so avg=3.0
	if stats2["Avg Score"] != "3.0" {
		t.Errorf("step4: expected avg_score=3.0, got %q", stats2["Avg Score"])
	}
	// Both genres appear once, tie broken arbitrarily — just verify it's non-empty and not dash.
	if stats2["Top Genre"] == "—" || stats2["Top Genre"] == "" {
		t.Errorf("step4: expected a top genre, got %q", stats2["Top Genre"])
	}

	// Step 5: Add more entries and re-fetch — cache is invalidated on config update, but here
	// we add entries after the last config update so we manually invalidate.
	createTestEntry(t, pool, userID, collID, "Movie 3", 2, "2024-07-01", `{"Genre":"Action"}`)
	invalidateStatCache(t, pool, collID)

	w4 := doRequest(r, http.MethodGet, "/collections/"+collID.String()+"/statistics", nil)
	if w4.Code != http.StatusOK {
		t.Fatalf("step5 GET: %d %s", w4.Code, w4.Body.String())
	}
	stats3 := parseStatResponse(t, w4.Body.Bytes())
	if stats3["Total"] != "3" {
		t.Errorf("step5: expected total=3, got %q", stats3["Total"])
	}
	// Now Action has 2 entries, Sci-Fi has 1 → top genre is Action.
	if stats3["Top Genre"] != "Action" {
		t.Errorf("step5: expected top_genre=Action, got %q", stats3["Top Genre"])
	}
}
