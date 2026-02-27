# Backend Architecture Notes

## Stack
- Go + chi router
- PostgreSQL with pgx/v5 (pgxpool)
- golang-migrate for migrations (file-based, auto-runs at startup)
- JWT (RS256) for auth
- prometheus metrics

## Directory Structure
```
backend/
  cmd/server/main.go          — wires everything, starts HTTP server
  internal/
    handler/                  — thin HTTP handlers
    service/                  — business logic, validation, ownership checks
    repository/               — raw SQL, DB structs
    middleware/               — auth (JWT), logging, metrics
    config/                   — config loading
    seed/                     — embedded seed images with fixed UUIDs
  migrations/                 — NNN_description.up.sql / .down.sql
```

## Database Tables

### users
```
id UUID PK, email VARCHAR(255), email_verified BOOL, display_name VARCHAR(255),
ai_usage_policy ENUM('basic','pro','unlimited') DEFAULT 'basic',
created_at, updated_at, deleted_at (soft delete)
```

### user_auth_providers
```
id UUID PK, user_id FK users, provider VARCHAR(50), provider_user_id VARCHAR(255),
UNIQUE(provider, provider_user_id)
```

### user_tokens
```
id UUID PK, user_id FK, refresh_token_hash VARCHAR(64),
device_info JSONB, expires_at, created_at, revoked_at
```

### verification_codes
```
id UUID PK, email VARCHAR(255), code_hash VARCHAR(64),
created_at, expires_at, used_at
UNIQUE on (email) WHERE used_at IS NULL (one active code per email)
```

### collections
```
id UUID PK, user_id FK users (CASCADE), name VARCHAR(50), icon VARCHAR(20),
created_at, updated_at
```

### collection_shares  (placeholder, not used in app yet)
```
id, collection_id FK, owner_id FK users, shared_with_user_id FK users,
permission_level VARCHAR(20) DEFAULT 'read'
UNIQUE(collection_id, shared_with_user_id)
```

### entries
```
id UUID PK, collection_id UUID FK collections (ON DELETE CASCADE — nullable),
type_id UUID FK entry_types (ON DELETE SET NULL — nullable),
user_id FK users (CASCADE), title VARCHAR(200), description TEXT (<=2000),
score SMALLINT (0-3), date DATE, additional_fields JSONB DEFAULT '{}',
created_at, updated_at
```
NOTE: type_id was added in migration 008. entry category is now stored explicitly
via entry_types (system types: Movie, Book, Game, Show, Music, Other). Collection FK
was also changed from SET NULL to CASCADE in 008.

### entry_types
```
id UUID PK, user_id UUID FK users (nullable — NULL means system/global type),
name VARCHAR(50), icon VARCHAR(20), created_at, updated_at
```
System types (user_id IS NULL): Movie, Book, Game, Show, Music, Other.
Users can create custom types (user_id = their ID).
No per-type field schema — all types share the same additional_fields JSONB structure.

### entry_images
```
id UUID PK, entry_id FK entries (CASCADE), image_data BYTEA,
is_cover BOOL, position INT, created_at
```

### ai_search_usage
```
id UUID PK, user_id FK (UNIQUE — one row per user), search_count INT,
period_start, period_end, created_at, updated_at
```

### seed_images
```
id UUID PK (fixed known UUIDs), image_data BYTEA, created_at
```

## Migration System
- Library: `github.com/golang-migrate/migrate/v4`
- Source: `file://migrations` directory
- Files named: `NNN_description.up.sql` and `NNN_description.down.sql`
- Auto-runs at startup in `main.go` via `repository.RunMigrations()`
- Current highest: migration 008 (adds entry_types table and type_id to entries)
- To add a migration: create `009_description.up.sql` + `.down.sql`

## API Routes

### Public
- POST /api/v1/auth/apple
- POST /api/v1/auth/email/send-code
- POST /api/v1/auth/email/resend-code
- POST /api/v1/auth/email/verify
- POST /api/v1/auth/refresh
- GET  /api/v1/images/{id}  — serves entry_images or seed_images by UUID, no auth

### Protected (Bearer JWT required)
- GET  /api/v1/auth/me
- POST /api/v1/auth/logout
- DELETE /api/v1/auth/account

- GET    /api/v1/collections
- POST   /api/v1/collections
- POST   /api/v1/collections/default  — creates Movies/Books/Games if user has none
- GET    /api/v1/collections/{id}
- PUT    /api/v1/collections/{id}
- DELETE /api/v1/collections/{id}

- GET    /api/v1/entries?collection_id=&limit=&offset=
- POST   /api/v1/entries
- GET    /api/v1/entries/search?q=&limit=&offset=
- GET    /api/v1/entries/{id}
- PUT    /api/v1/entries/{id}
- DELETE /api/v1/entries/{id}

- POST   /api/v1/search  — AI search

- GET    /api/v1/types   — returns system + user's own types
- POST   /api/v1/types   — creates a user-owned type

## Authentication Flow
- JWT Bearer token extracted by `middleware.AuthMiddleware`
- UserID string stored in context under key "userID"
- Retrieved in handlers via `getUserIDFromContext(ctx)` (local handler helper)
- Also available via `middleware.GetUserIDFromContext(ctx)` (middleware package)

## New User Initialization
1. `CreateUserWithProvider` called in a transaction (creates users row + user_auth_providers row)
2. No collections or entries created automatically
3. Client must explicitly call `POST /api/v1/collections/default` to create Movies/Books/Games
4. Guard: `CollectionService.CreateDefaultCollections` returns error "user already has collections" if any exist

## Service Layer Pattern
- Services hold: validation, ownership checks, cross-repo coordination
- Repos hold: raw SQL queries only, return typed structs or sentinel errors
- Sentinel errors defined per-repo: `ErrCollectionNotFound`, `ErrEntryNotFound`, `ErrUserNotFound`, etc.
- Handler maps sentinel errors to HTTP status codes

## Entry Additional Fields
- `additional_fields` is a `JSONB` column storing `map[string]string`
- Used by AI search to store metadata (e.g., director, author, genre)
- No schema enforcement — arbitrary key-value pairs
- GIN index on `entries.additional_fields` for fast queries

## Default Collections (hardcoded in repository layer)
Location: `collection_repository.go` `CreateDefaultCollections` method
```go
{"Movies", "🎬"}
{"Books", "📚"}
{"Games", "🎮"}
```
These are user-scoped collections, not shared/global types.
