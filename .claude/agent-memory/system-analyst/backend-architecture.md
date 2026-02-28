# Backend Architecture Notes

## Project Layout

```
backend/
  cmd/server/main.go          -- entry point, wires everything together
  internal/
    config/                   -- config loading
    handler/                  -- HTTP handlers (thin, delegate to services)
    middleware/                -- auth, logging, metrics middleware
    repository/                -- DB access layer, plain pgx queries
    service/                   -- business logic
    seed/                      -- seed images for dev
    logger/                    -- zap logger setup
  migrations/                  -- numbered .up.sql / .down.sql files
  Justfile                     -- build/lint/test commands
```

## Router

Framework: `github.com/go-chi/chi/v5`

Routes registered in `cmd/server/main.go`:
- Public: `GET /health`, auth endpoints, `GET /images/{id}`
- Protected (behind AuthMiddleware): collections, entries, types, AI search

## Auth Flow

- JWT RS256 tokens (private/public key PEM files)
- `middleware.AuthMiddleware` in `backend/internal/middleware/auth.go`:
  - Reads `Authorization: Bearer <token>`
  - Validates via `jwtService.ValidateAccessToken()`
  - Stores `claims.UserID` (string UUID) in `ctx` under plain string key `"userID"`
- Handlers retrieve it with `getUserIDFromContext(ctx)` (defined in `auth.go` handler file), then parse to `uuid.UUID`

## Database Schema

Migration files in `backend/migrations/`

### users (001)
- id, email, email_verified, display_name, created_at, updated_at, deleted_at (soft delete)

### user_auth_providers (002)
- id, user_id, provider, provider_user_id — for Apple Sign In etc.

### user_tokens (002)
- id, user_id, refresh_token_hash (sha256), device_info, expires_at, revoked_at

### verification_codes (003)
- email-based OTP codes

### collections (004)
- id, user_id, name (varchar 50), icon (varchar 20), created_at, updated_at
- Index on user_id

### collection_shares (004) -- EXISTS IN DB, NO BACKEND CODE YET
- id, collection_id, owner_id, shared_with_user_id, permission_level (varchar 20, default 'read'), created_at
- UNIQUE constraint: (collection_id, shared_with_user_id)
- Indexes on collection_id and shared_with_user_id

### entries (004)
- id, collection_id (nullable FK), user_id, title, description, score (0-3), date, additional_fields (jsonb), created_at, updated_at

### entry_images (004)
- id, entry_id, image_data (bytea), is_cover, position, created_at

### ai_search_usage (005), ai_usage_policy on users (006), seed_images (007), entry types (008, 009)

## Collection Layer

Handler: `backend/internal/handler/collection_handler.go`
- Routes: GET/POST /collections, POST /collections/default, GET/PUT/DELETE /collections/{id}
- Ownership check: service fetches collection, compares collection.UserID == callerUID

Service: `backend/internal/service/collection_service.go`
- Validates name (1-50 chars) and icon (1-20 chars)
- GetCollectionByID returns ErrCollectionNotFound if user doesn't own it (ownership enforcement)
- No sharing logic exists yet

Repository: `backend/internal/repository/collection_repository.go`
- Collection struct: ID, UserID, Name, Icon, EntryCount, CreatedAt, UpdatedAt
- GetCollectionsByUserID: filters strictly by user_id — shared collections NOT returned
- No queries against collection_shares table

## What's Missing for Sharing Feature

1. Repository methods: query collection_shares (create share, list members, delete share, get collections shared with user)
2. Service layer: CollectionService needs sharing methods + access-control logic
3. Handler routes: new endpoints (POST/DELETE /collections/{id}/members, GET /collections/{id}/members)
4. GetCollections must be updated to also return collections shared with the caller
5. GetCollectionByID ownership check must be updated to allow shared members to read
6. User lookup: need to find user by email to invite by email
