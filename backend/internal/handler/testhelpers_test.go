package handler

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	tcpostgres "github.com/testcontainers/testcontainers-go/modules/postgres"
	"go.uber.org/zap"

	"github.com/avalarin/livlog/backend/internal/repository"
	"github.com/avalarin/livlog/backend/internal/service"
)

// migrationsDir returns the absolute path to the migrations directory.
// go test sets the working directory to the package source directory, so
// we can navigate up two levels from backend/internal/handler/ to backend/
// and then into migrations/.
func migrationsDir() string {
	// When go test runs, cwd is the package directory (backend/internal/handler).
	// backend/internal/handler -> backend/internal (1) -> backend (2) -> backend/migrations
	cwd, err := os.Getwd()
	if err != nil {
		panic("migrationsDir: " + err.Error())
	}
	abs, err := filepath.Abs(filepath.Join(cwd, "..", "..", "migrations"))
	if err != nil {
		panic("migrationsDir abs: " + err.Error())
	}
	return abs
}

// ---- Shared Postgres container (one per test binary) ----

var (
	sharedPool     *pgxpool.Pool
	sharedPoolOnce sync.Once
	sharedPoolErr  error
)

// startSharedDB starts a Postgres 16 container and runs all migrations.
// It is safe to call multiple times — only the first call does real work.
func startSharedDB(tb testing.TB) *pgxpool.Pool {
	sharedPoolOnce.Do(func() {
		ctx := context.Background()

		pgContainer, err := tcpostgres.Run(ctx,
			"postgres:16-alpine",
			tcpostgres.WithDatabase("testdb"),
			tcpostgres.WithUsername("testuser"),
			tcpostgres.WithPassword("testpass"),
			tcpostgres.BasicWaitStrategies(),
		)
		if err != nil {
			sharedPoolErr = fmt.Errorf("failed to start postgres container: %w", err)
			return
		}

		connStr, err := pgContainer.ConnectionString(ctx, "sslmode=disable")
		if err != nil {
			sharedPoolErr = fmt.Errorf("failed to get connection string: %w", err)
			return
		}

		// Run migrations
		m, err := migrate.New("file://"+migrationsDir(), connStr)
		if err != nil {
			sharedPoolErr = fmt.Errorf("failed to create migrate instance: %w", err)
			return
		}
		if err := m.Up(); err != nil {
			sharedPoolErr = fmt.Errorf("failed to run migrations: %w", err)
			return
		}
		_, _ = m.Close()

		pool, err := pgxpool.New(ctx, connStr)
		if err != nil {
			sharedPoolErr = fmt.Errorf("failed to create pool: %w", err)
			return
		}

		sharedPool = pool

		// Container cleanup is deferred to process exit intentionally:
		// testcontainers uses Ryuk for reaping, and the pool is closed below.
		// We register a finalizer-style cleanup through testing.M in TestMain.
	})

	if sharedPoolErr != nil {
		tb.Fatalf("shared DB setup failed: %v", sharedPoolErr)
	}

	return sharedPool
}

// TestMain starts the shared DB once and runs all tests.
func TestMain(m *testing.M) {
	m.Run()
	if sharedPool != nil {
		sharedPool.Close()
	}
}

// ---- testEnv wires all dependencies ----

type testEnv struct {
	pool              *pgxpool.Pool
	mcpService        *service.MCPService
	collectionService *service.CollectionService
	entryService      *service.EntryService
	typeService       *service.TypeService
	tagRepo           *repository.TagRepository
	entryRepo         *repository.EntryRepository
	collectionRepo    *repository.CollectionRepository
	mcpRepo           *repository.MCPRepository
	handler           *MCPProtocolHandler
	log               *zap.Logger
}

func setupTestEnv(t *testing.T, pool *pgxpool.Pool) *testEnv {
	t.Helper()

	log := zap.NewNop()

	collectionRepo := repository.NewCollectionRepository(pool)
	entryRepo := repository.NewEntryRepository(pool)
	typeRepo := repository.NewTypeRepository(pool)
	mcpRepo := repository.NewMCPRepository(pool)
	tagRepo := repository.NewTagRepository(pool)
	userRepo := repository.NewUserRepository(pool)

	collectionService := service.NewCollectionService(collectionRepo, userRepo)
	entryService := service.NewEntryService(entryRepo, collectionRepo, typeRepo)
	typeService := service.NewTypeService(typeRepo)
	mcpService := service.NewMCPService(mcpRepo, "http://localhost:8080")

	h := NewMCPProtocolHandler(mcpService, collectionService, entryService, typeService, tagRepo, log)

	return &testEnv{
		pool:              pool,
		mcpService:        mcpService,
		collectionService: collectionService,
		entryService:      entryService,
		typeService:       typeService,
		tagRepo:           tagRepo,
		entryRepo:         entryRepo,
		collectionRepo:    collectionRepo,
		mcpRepo:           mcpRepo,
		handler:           h,
		log:               log,
	}
}

// createTestUser inserts a minimal user row and returns its UUID.
func (env *testEnv) createTestUser(t *testing.T) uuid.UUID {
	t.Helper()

	email := fmt.Sprintf("test+%s@example.com", uuid.New().String())
	var userID uuid.UUID
	err := env.pool.QueryRow(
		context.Background(),
		`INSERT INTO users (email, email_verified) VALUES ($1, true) RETURNING id`,
		email,
	).Scan(&userID)
	if err != nil {
		t.Fatalf("createTestUser: %v", err)
	}

	return userID
}

// createTestCollection inserts a collection and its owner share row.
func (env *testEnv) createTestCollection(t *testing.T, userID uuid.UUID, name string) uuid.UUID {
	t.Helper()

	var collID uuid.UUID
	err := env.pool.QueryRow(
		context.Background(),
		`INSERT INTO collections (user_id, name, icon, color) VALUES ($1, $2, 'system:folder', 'dodger-blue') RETURNING id`,
		userID, name,
	).Scan(&collID)
	if err != nil {
		t.Fatalf("createTestCollection insert: %v", err)
	}

	_, err = env.pool.Exec(
		context.Background(),
		`INSERT INTO collection_shares (collection_id, owner_id, shared_with_user_id, permission_level)
		 VALUES ($1, $2, $2, 'owner')`,
		collID, userID,
	)
	if err != nil {
		t.Fatalf("createTestCollection share: %v", err)
	}

	return collID
}

// enableMCP calls mcpService.Enable and returns the unique_code.
func (env *testEnv) enableMCP(t *testing.T, userID uuid.UUID) string {
	t.Helper()

	status, err := env.mcpService.Enable(context.Background(), userID)
	if err != nil {
		t.Fatalf("enableMCP: %v", err)
	}

	// Extract unique_code from URL: http://localhost:8080/api/mcp/<code>
	parts := strings.Split(status.URL, "/api/mcp/")
	if len(parts) != 2 {
		t.Fatalf("enableMCP: unexpected URL %q", status.URL)
	}

	return parts[1]
}

// getMovieTypeID finds the Movie system type.
func (env *testEnv) getMovieTypeID(t *testing.T) uuid.UUID {
	t.Helper()

	var id uuid.UUID
	err := env.pool.QueryRow(
		context.Background(),
		`SELECT id FROM entry_types WHERE name = 'Movie' AND user_id IS NULL LIMIT 1`,
	).Scan(&id)
	if err != nil {
		t.Fatalf("getMovieTypeID: %v", err)
	}

	return id
}

// callMCPTool sends a tools/call JSON-RPC request to the MCP handler and returns
// the text content of the first result item.
func (env *testEnv) callMCPTool(t *testing.T, uniqueCode string, toolName string, args map[string]interface{}) string {
	t.Helper()

	body := map[string]interface{}{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "tools/call",
		"params": map[string]interface{}{
			"name":      toolName,
			"arguments": args,
		},
	}
	bodyBytes, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("callMCPTool marshal: %v", err)
	}

	r := chi.NewRouter()
	env.handler.RegisterRoutes(r)

	req := httptest.NewRequest(http.MethodPost, "/api/mcp/"+uniqueCode, bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("callMCPTool %q: HTTP %d: %s", toolName, w.Code, w.Body.String())
	}

	return extractMCPText(t, w.Body.Bytes())
}

// extractMCPText parses a JSON-RPC response (or SSE stream) and returns the first
// text content item from the result.
func extractMCPText(t *testing.T, rawBody []byte) string {
	t.Helper()

	type contentItem struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	type rpcResult struct {
		Content []contentItem `json:"content"`
	}
	type rpcError struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	}
	type rpcResponse struct {
		JSONRPC string      `json:"jsonrpc"`
		ID      interface{} `json:"id"`
		Result  *rpcResult  `json:"result"`
		Error   *rpcError   `json:"error"`
	}

	body := strings.TrimSpace(string(rawBody))

	// StreamableHTTPServer may return SSE-formatted events.
	if strings.Contains(body, "data:") {
		scanner := bufio.NewScanner(strings.NewReader(body))
		for scanner.Scan() {
			line := scanner.Text()
			if !strings.HasPrefix(line, "data:") {
				continue
			}
			jsonLine := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
			var resp rpcResponse
			if err := json.Unmarshal([]byte(jsonLine), &resp); err != nil {
				continue
			}
			if resp.Error != nil {
				t.Fatalf("MCP tool returned error: code=%d message=%s", resp.Error.Code, resp.Error.Message)
			}
			if resp.Result != nil && len(resp.Result.Content) > 0 {
				return resp.Result.Content[0].Text
			}
		}
		t.Fatalf("extractMCPText: no result found in SSE body: %s", body)
	}

	// Plain JSON response
	var resp rpcResponse
	if err := json.Unmarshal(rawBody, &resp); err != nil {
		t.Fatalf("extractMCPText: failed to unmarshal response: %v\nbody: %s", err, body)
	}
	if resp.Error != nil {
		t.Fatalf("MCP tool returned error: code=%d message=%s", resp.Error.Code, resp.Error.Message)
	}
	if resp.Result == nil || len(resp.Result.Content) == 0 {
		t.Fatalf("extractMCPText: empty result content in body: %s", body)
	}

	return resp.Result.Content[0].Text
}
