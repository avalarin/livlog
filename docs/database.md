# Database Schema

**Version:** 1.0
**Last Updated:** 2025-01-31
**Database:** PostgreSQL 15+

## Overview

### General Architecture

Livlogios uses PostgreSQL as the primary database. The schema is designed around three main domains:

1. **Authentication** - user accounts and auth providers
2. **Content** - collections and entries (user's logged items)
3. **Media** - images attached to entries

### Design Principles

- **UUID for primary keys** - all tables use UUID v4 for primary keys for security (non-guessable IDs) and distributed systems compatibility
- **Timestamps in UTC** - all `TIMESTAMP WITH TIME ZONE` fields store UTC values
- **Soft delete for users** - GDPR compliance; user data can be anonymized rather than immediately deleted
- **Hard delete for content** - collections and entries are permanently deleted
- **JSONB for flexible data** - `additionalFields` uses JSONB for arbitrary key-value metadata
- **Foreign keys with cascade** - data integrity through proper FK relationships

### Data Type Choices

| Type | Usage | Rationale |
|------|-------|-----------|
| `UUID` | Primary keys, foreign keys | Non-sequential, safe to expose in URLs |
| `VARCHAR(n)` | Short strings with known max length | Memory efficient, explicit constraints |
| `TEXT` | Long strings (descriptions) | No length limit needed |
| `SMALLINT` | Score (0-3) | Minimal storage for small range |
| `JSONB` | additionalFields, device_info | Flexible schema, indexable |
| `TIMESTAMP WITH TIME ZONE` | All timestamps | Timezone-aware, stored as UTC |
| `BOOLEAN` | Flags | Standard boolean type |

---

## Tables

### users

User accounts for the application.

**Purpose:** Store user profile information and account status.

| Column | Type | Nullable | Default | Index | FK | Description |
|--------|------|----------|---------|-------|----|----|
| `id` | UUID | NO | `gen_random_uuid()` | PK | - | Unique user identifier |
| `email` | VARCHAR(255) | YES | NULL | UNIQUE* | - | User email (may be Apple private relay) |
| `email_verified` | BOOLEAN | NO | FALSE | - | - | Whether email is verified |
| `display_name` | VARCHAR(255) | YES | NULL | - | - | User's display name |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | - | - | Account creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `NOW()` | - | - | Last profile update timestamp |
| `deleted_at` | TIMESTAMPTZ | YES | NULL | IDX | - | Soft delete timestamp |

*Unique index on `email` only where `email IS NOT NULL AND deleted_at IS NULL`

**SQL Definition:**

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255),
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    display_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- Unique email only for active users
CREATE UNIQUE INDEX idx_users_email
    ON users(email)
    WHERE email IS NOT NULL AND deleted_at IS NULL;

-- For finding soft-deleted users (cleanup jobs)
CREATE INDEX idx_users_deleted_at
    ON users(deleted_at)
    WHERE deleted_at IS NOT NULL;
```

**Indexes:**

| Index Name | Columns | Type | Purpose |
|------------|---------|------|---------|
| `users_pkey` | `id` | B-tree (PK) | Primary key lookups |
| `idx_users_email` | `email` | Unique partial | Email uniqueness for active users |
| `idx_users_deleted_at` | `deleted_at` | B-tree partial | Cleanup job queries |

**Data Operations:**

- **Read:** Auth flows (`/auth/me`), profile display
- **Write:** Registration, profile updates
- **Soft Delete:** Account deletion (GDPR), sets `deleted_at`

**Typical Queries:**

```sql
-- Find user by ID
SELECT * FROM users WHERE id = $1 AND deleted_at IS NULL;

-- Find user by email
SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL;

-- Update profile
UPDATE users SET display_name = $1, updated_at = NOW() WHERE id = $2;

-- Soft delete user
UPDATE users SET deleted_at = NOW() WHERE id = $1;

-- Count active users
SELECT COUNT(*) FROM users WHERE deleted_at IS NULL;
```

---

### user_auth_providers

Links users to external authentication providers (Apple, Google, etc.).

**Purpose:** Support multiple auth methods per user without modifying the users table.

| Column | Type | Nullable | Default | Index | FK | Description |
|--------|------|----------|---------|-------|----|----|
| `id` | UUID | NO | `gen_random_uuid()` | PK | - | Unique record identifier |
| `user_id` | UUID | NO | - | IDX | `users(id)` | Reference to user |
| `provider` | VARCHAR(50) | NO | - | UNIQUE* | - | Provider name: 'apple', 'email', 'google' |
| `provider_user_id` | VARCHAR(255) | NO | - | UNIQUE* | - | User ID from provider |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | - | - | When provider was linked |

*Composite unique on `(provider, provider_user_id)`

**SQL Definition:**

```sql
CREATE TABLE user_auth_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_auth_provider UNIQUE (provider, provider_user_id)
);

-- Fast lookup by user
CREATE INDEX idx_auth_providers_user_id
    ON user_auth_providers(user_id);

-- Fast lookup for login
CREATE INDEX idx_auth_providers_lookup
    ON user_auth_providers(provider, provider_user_id);
```

**Provider Types:**

| Provider | `provider_user_id` Content |
|----------|---------------------------|
| `apple` | Apple user ID (JWT `sub` claim) |
| `email` | User's email address |
| `google` | Google user ID |

**Indexes:**

| Index Name | Columns | Type | Purpose |
|------------|---------|------|---------|
| `user_auth_providers_pkey` | `id` | B-tree (PK) | Primary key |
| `uq_auth_provider` | `(provider, provider_user_id)` | Unique | Prevent duplicate provider links |
| `idx_auth_providers_user_id` | `user_id` | B-tree | Find all providers for a user |
| `idx_auth_providers_lookup` | `(provider, provider_user_id)` | B-tree | Login flow lookups |

**Data Operations:**

- **Read:** Login (find user by provider), list user's providers
- **Write:** First-time registration, linking new provider
- **Delete:** Cascade on user deletion, unlinking provider

**Typical Queries:**

```sql
-- Find user by Apple ID (login flow)
SELECT u.* FROM users u
JOIN user_auth_providers p ON u.id = p.user_id
WHERE p.provider = 'apple' AND p.provider_user_id = $1
AND u.deleted_at IS NULL;

-- Get all providers for user
SELECT provider, created_at FROM user_auth_providers WHERE user_id = $1;

-- Link new provider
INSERT INTO user_auth_providers (user_id, provider, provider_user_id)
VALUES ($1, 'apple', $2);
```

---

### user_tokens

Stores refresh tokens for authenticated sessions.

**Purpose:** Track and manage user sessions with refresh token rotation.

| Column | Type | Nullable | Default | Index | FK | Description |
|--------|------|----------|---------|-------|----|----|
| `id` | UUID | NO | `gen_random_uuid()` | PK | - | Unique token record ID |
| `user_id` | UUID | NO | - | IDX | `users(id)` | Owner user |
| `refresh_token_hash` | VARCHAR(64) | NO | - | IDX* | - | SHA-256 hash of refresh token |
| `device_info` | JSONB | YES | NULL | - | - | Device metadata |
| `expires_at` | TIMESTAMPTZ | NO | - | IDX* | - | Token expiration time |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | - | - | Token creation time |
| `revoked_at` | TIMESTAMPTZ | YES | NULL | - | - | When token was revoked (logout) |

*Partial indexes where `revoked_at IS NULL`

**SQL Definition:**

```sql
CREATE TABLE user_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(64) NOT NULL,
    device_info JSONB,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMP WITH TIME ZONE
);

-- Find tokens by user
CREATE INDEX idx_user_tokens_user_id
    ON user_tokens(user_id);

-- Token lookup (only active tokens)
CREATE INDEX idx_user_tokens_hash
    ON user_tokens(refresh_token_hash)
    WHERE revoked_at IS NULL;

-- Cleanup expired tokens
CREATE INDEX idx_user_tokens_cleanup
    ON user_tokens(expires_at)
    WHERE revoked_at IS NULL;
```

**device_info JSONB Schema:**

```json
{
  "device_name": "iPhone 15 Pro",
  "os_version": "iOS 17.2",
  "app_version": "1.0.0"
}
```

**Indexes:**

| Index Name | Columns | Type | Purpose |
|------------|---------|------|---------|
| `user_tokens_pkey` | `id` | B-tree (PK) | Primary key |
| `idx_user_tokens_user_id` | `user_id` | B-tree | List user's sessions |
| `idx_user_tokens_hash` | `refresh_token_hash` | B-tree partial | Token validation (active only) |
| `idx_user_tokens_cleanup` | `expires_at` | B-tree partial | Expired token cleanup |

**Data Operations:**

- **Read:** Token refresh, session listing
- **Write:** Login (create token), refresh (rotate token)
- **Update:** Logout (set `revoked_at`)
- **Delete:** Cleanup job removes expired/revoked tokens

**Typical Queries:**

```sql
-- Validate refresh token
SELECT * FROM user_tokens
WHERE refresh_token_hash = $1
AND revoked_at IS NULL
AND expires_at > NOW();

-- Revoke token (logout)
UPDATE user_tokens SET revoked_at = NOW() WHERE refresh_token_hash = $1;

-- Revoke all user tokens (logout everywhere)
UPDATE user_tokens SET revoked_at = NOW()
WHERE user_id = $1 AND revoked_at IS NULL;

-- Cleanup expired tokens (background job)
DELETE FROM user_tokens
WHERE expires_at < NOW() - INTERVAL '7 days'
   OR revoked_at < NOW() - INTERVAL '7 days';
```

---

### user_passwords

Stores password hashes for email authentication (future feature).

**Purpose:** Enable email/password authentication alongside OAuth providers.

| Column | Type | Nullable | Default | Index | FK | Description |
|--------|------|----------|---------|-------|----|----|
| `id` | UUID | NO | `gen_random_uuid()` | PK | - | Unique record ID |
| `user_id` | UUID | NO | - | UNIQUE | `users(id)` | Owner user (one password per user) |
| `password_hash` | VARCHAR(255) | NO | - | - | - | Argon2id hash |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | - | - | Password creation time |
| `updated_at` | TIMESTAMPTZ | NO | `NOW()` | - | - | Last password change |

**SQL Definition:**

```sql
CREATE TABLE user_passwords (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_user_password UNIQUE (user_id)
);
```

**Notes:**
- Uses Argon2id for password hashing
- One password per user (UNIQUE constraint)
- `user_auth_providers` entry with `provider='email'` should exist when password is set

---

### collections

User's collections that group entries by category.

**Purpose:** Organize entries into logical groups (Movies, Books, Games, etc.).

| Column | Type | Nullable | Default | Index | FK | Description |
|--------|------|----------|---------|-------|----|----|
| `id` | UUID | NO | `gen_random_uuid()` | PK | - | Unique collection ID |
| `user_id` | UUID | NO | - | IDX | `users(id)` | Owner user |
| `name` | VARCHAR(100) | NO | - | - | - | Collection name (e.g., "Movies") |
| `icon` | VARCHAR(10) | NO | - | - | - | Emoji icon |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | IDX | - | Creation timestamp |

**SQL Definition:**

```sql
CREATE TABLE collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(10) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Primary query pattern: get user's collections
CREATE INDEX idx_collections_user_id
    ON collections(user_id);

-- Sorting by creation date
CREATE INDEX idx_collections_user_created
    ON collections(user_id, created_at DESC);
```

**Indexes:**

| Index Name | Columns | Type | Purpose |
|------------|---------|------|---------|
| `collections_pkey` | `id` | B-tree (PK) | Primary key lookups |
| `idx_collections_user_id` | `user_id` | B-tree | List user's collections |
| `idx_collections_user_created` | `(user_id, created_at DESC)` | B-tree | Sorted listing |

**Data Operations:**

- **Read:** List collections, get single collection
- **Write:** Create collection
- **Update:** Rename, change icon
- **Delete:** Cascade deletes all entries and their images

**Typical Queries:**

```sql
-- Get user's collections with entry counts
SELECT c.*, COUNT(e.id) as entries_count
FROM collections c
LEFT JOIN entries e ON e.collection_id = c.id
WHERE c.user_id = $1
GROUP BY c.id
ORDER BY c.created_at DESC;

-- Get single collection
SELECT * FROM collections WHERE id = $1 AND user_id = $2;

-- Create collection
INSERT INTO collections (user_id, name, icon)
VALUES ($1, $2, $3)
RETURNING *;

-- Update collection
UPDATE collections SET name = $1, icon = $2 WHERE id = $3 AND user_id = $4;

-- Delete collection (cascades to entries)
DELETE FROM collections WHERE id = $1 AND user_id = $2;
```

**entriesCount Calculation:**

The `entriesCount` field in API responses is computed dynamically, not stored:

```sql
-- Option 1: JOIN with COUNT (recommended for small-medium datasets)
SELECT c.*, COUNT(e.id) as entries_count
FROM collections c
LEFT JOIN entries e ON e.collection_id = c.id
WHERE c.user_id = $1
GROUP BY c.id;

-- Option 2: Subquery (alternative)
SELECT c.*,
    (SELECT COUNT(*) FROM entries e WHERE e.collection_id = c.id) as entries_count
FROM collections c
WHERE c.user_id = $1;
```

---

### entries

Individual logged items (movies, books, games, etc.).

**Purpose:** Store user's logged experiences with metadata and ratings.

| Column | Type | Nullable | Default | Index | FK | Description |
|--------|------|----------|---------|-------|----|----|
| `id` | UUID | NO | `gen_random_uuid()` | PK | - | Unique entry ID |
| `collection_id` | UUID | NO | - | IDX | `collections(id)` | Parent collection |
| `title` | VARCHAR(500) | NO | - | - | - | Entry title |
| `description` | TEXT | YES | NULL | - | - | Entry description |
| `score` | SMALLINT | NO | 0 | IDX | - | Rating: 0=undecided, 1=bad, 2=okay, 3=great |
| `date` | DATE | NO | `CURRENT_DATE` | IDX | - | When user experienced the item |
| `additional_fields` | JSONB | YES | '{}' | GIN | - | Flexible metadata (Year, Genre, etc.) |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | IDX | - | Entry creation timestamp |

**SQL Definition:**

```sql
CREATE TABLE entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    score SMALLINT NOT NULL DEFAULT 0 CHECK (score >= 0 AND score <= 3),
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    additional_fields JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Primary filter: entries by collection
CREATE INDEX idx_entries_collection_id
    ON entries(collection_id);

-- Sorting indexes
CREATE INDEX idx_entries_collection_date
    ON entries(collection_id, date DESC);

CREATE INDEX idx_entries_collection_created
    ON entries(collection_id, created_at DESC);

CREATE INDEX idx_entries_collection_title
    ON entries(collection_id, title);

CREATE INDEX idx_entries_collection_score
    ON entries(collection_id, score DESC);

-- Full-text search on title and description
CREATE INDEX idx_entries_search
    ON entries USING GIN (to_tsvector('english', title || ' ' || COALESCE(description, '')));

-- Filter by score
CREATE INDEX idx_entries_score
    ON entries(score);

-- GIN index for JSONB queries on additionalFields
CREATE INDEX idx_entries_additional_fields
    ON entries USING GIN (additional_fields);
```

**Score Values:**

| Value | Name | Emoji | Description |
|-------|------|-------|-------------|
| 0 | undecided | New | Not rated yet |
| 1 | bad | Thumbs down | Not my thing at all |
| 2 | okay | OK hand | Fine for once |
| 3 | great | Star-struck | Absolutely loved it |

**additional_fields JSONB Schema:**

```json
{
  "Year": "2010",
  "Genre": "Sci-Fi, Thriller",
  "Author": "Christopher Nolan",
  "Platform": "Netflix"
}
```

**Indexes:**

| Index Name | Columns | Type | Purpose |
|------------|---------|------|---------|
| `entries_pkey` | `id` | B-tree (PK) | Primary key lookups |
| `idx_entries_collection_id` | `collection_id` | B-tree | Filter by collection |
| `idx_entries_collection_date` | `(collection_id, date DESC)` | B-tree | Sort by date |
| `idx_entries_collection_created` | `(collection_id, created_at DESC)` | B-tree | Sort by creation |
| `idx_entries_collection_title` | `(collection_id, title)` | B-tree | Sort by title |
| `idx_entries_collection_score` | `(collection_id, score DESC)` | B-tree | Sort by score |
| `idx_entries_search` | `to_tsvector(...)` | GIN | Full-text search |
| `idx_entries_score` | `score` | B-tree | Filter by score |
| `idx_entries_additional_fields` | `additional_fields` | GIN | JSONB queries |

**Data Operations:**

- **Read:** List with filters/pagination, get single entry, search
- **Write:** Create entry with images
- **Update:** Edit fields, move to different collection
- **Delete:** Cascade deletes all images

**Typical Queries:**

```sql
-- List entries with pagination and filters
SELECT e.*,
    (SELECT json_agg(json_build_object(
        'id', i.id,
        'url', i.url,
        'isCover', i.is_cover
    ) ORDER BY i.is_cover DESC, i.position)
    FROM entry_images i WHERE i.entry_id = e.id) as images
FROM entries e
WHERE e.collection_id = $1           -- optional filter
  AND ($2::smallint IS NULL OR e.score = $2)  -- optional score filter
ORDER BY e.date DESC
LIMIT $3 OFFSET $4;

-- Search entries by title/description
SELECT e.*
FROM entries e
JOIN collections c ON c.id = e.collection_id
WHERE c.user_id = $1
  AND to_tsvector('english', e.title || ' ' || COALESCE(e.description, ''))
      @@ plainto_tsquery('english', $2)
ORDER BY ts_rank(to_tsvector('english', e.title || ' ' || COALESCE(e.description, '')),
                 plainto_tsquery('english', $2)) DESC
LIMIT $3;

-- Get single entry with images
SELECT e.*,
    json_agg(json_build_object(
        'id', i.id,
        'url', i.url,
        'isCover', i.is_cover
    ) ORDER BY i.is_cover DESC, i.position) FILTER (WHERE i.id IS NOT NULL) as images
FROM entries e
LEFT JOIN entry_images i ON i.entry_id = e.id
WHERE e.id = $1
GROUP BY e.id;

-- Create entry
INSERT INTO entries (collection_id, title, description, score, date, additional_fields)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- Update entry
UPDATE entries
SET title = $1, description = $2, score = $3, date = $4, additional_fields = $5
WHERE id = $6;

-- Move entry to different collection
UPDATE entries SET collection_id = $1 WHERE id = $2;

-- Count entries in collection
SELECT COUNT(*) FROM entries WHERE collection_id = $1;
```

---

### entry_images

Images attached to entries.

**Purpose:** Store references to images in object storage (S3/CDN).

| Column | Type | Nullable | Default | Index | FK | Description |
|--------|------|----------|---------|-------|----|----|
| `id` | UUID | NO | `gen_random_uuid()` | PK | - | Unique image ID |
| `entry_id` | UUID | NO | - | IDX | `entries(id)` | Parent entry |
| `url` | VARCHAR(500) | NO | - | - | - | CDN URL to the image |
| `is_cover` | BOOLEAN | NO | FALSE | - | - | Whether this is the cover image |
| `position` | SMALLINT | NO | 0 | - | - | Display order (0-based) |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | - | - | Upload timestamp |

**SQL Definition:**

```sql
CREATE TABLE entry_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    url VARCHAR(500) NOT NULL,
    is_cover BOOLEAN NOT NULL DEFAULT FALSE,
    position SMALLINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Get images for entry
CREATE INDEX idx_entry_images_entry_id
    ON entry_images(entry_id);

-- Ordered retrieval
CREATE INDEX idx_entry_images_entry_order
    ON entry_images(entry_id, is_cover DESC, position);
```

**Indexes:**

| Index Name | Columns | Type | Purpose |
|------------|---------|------|---------|
| `entry_images_pkey` | `id` | B-tree (PK) | Primary key lookups |
| `idx_entry_images_entry_id` | `entry_id` | B-tree | Get images for entry |
| `idx_entry_images_entry_order` | `(entry_id, is_cover DESC, position)` | B-tree | Ordered retrieval |

**Data Operations:**

- **Read:** Get images for entry (always with entry)
- **Write:** Upload images during entry creation
- **Update:** Change cover, reorder
- **Delete:** Remove specific images, cascade on entry deletion

**Typical Queries:**

```sql
-- Get images for entry (cover first)
SELECT * FROM entry_images
WHERE entry_id = $1
ORDER BY is_cover DESC, position;

-- Add image to entry
INSERT INTO entry_images (entry_id, url, is_cover, position)
VALUES ($1, $2, $3, $4);

-- Set cover image
UPDATE entry_images SET is_cover = FALSE WHERE entry_id = $1;
UPDATE entry_images SET is_cover = TRUE WHERE id = $2;

-- Remove image
DELETE FROM entry_images WHERE id = $1;

-- Reorder images
UPDATE entry_images SET position = $1 WHERE id = $2;
```

**Image Storage Strategy:**

Images are stored in object storage (S3, CloudFlare R2, etc.) and referenced by URL:

```
https://cdn.livlogios.app/images/{user_id}/{entry_id}/{image_id}.jpg
```

This approach:
- Keeps database small and fast
- Enables CDN caching
- Allows direct client uploads (presigned URLs)
- Simplifies backup (only metadata in DB)

---

## Performance Considerations

### Critical Queries and Their Indexes

#### 1. Get User's Collections with Entry Counts

```sql
-- Query
SELECT c.*, COUNT(e.id) as entries_count
FROM collections c
LEFT JOIN entries e ON e.collection_id = c.id
WHERE c.user_id = $1
GROUP BY c.id
ORDER BY c.created_at DESC;

-- Uses: idx_collections_user_id, idx_entries_collection_id
```

**EXPLAIN ANALYZE example:**
```
GroupAggregate  (cost=5.32..6.12 rows=5 width=80)
  ->  Nested Loop Left Join
        ->  Index Scan using idx_collections_user_id on collections c
              Index Cond: (user_id = $1)
        ->  Index Only Scan using idx_entries_collection_id on entries e
              Index Cond: (collection_id = c.id)
```

#### 2. List Entries with Filters

```sql
-- Query (collection + score filter, date sort)
SELECT e.* FROM entries e
WHERE e.collection_id = $1
  AND e.score = $2
ORDER BY e.date DESC
LIMIT 20 OFFSET 0;

-- Uses: idx_entries_collection_date (covering index)
-- Note: Add composite index for common filter+sort patterns
```

**Recommended additional index for filtered queries:**
```sql
CREATE INDEX idx_entries_collection_score_date
    ON entries(collection_id, score, date DESC);
```

#### 3. Full-Text Search

```sql
-- Query
SELECT e.* FROM entries e
JOIN collections c ON c.id = e.collection_id
WHERE c.user_id = $1
  AND to_tsvector('english', e.title || ' ' || COALESCE(e.description, ''))
      @@ plainto_tsquery('english', 'inception')
ORDER BY ts_rank(...) DESC
LIMIT 20;

-- Uses: idx_entries_search (GIN), idx_collections_user_id
```

**Performance tip:** For large datasets, consider a separate `search_vector` column with trigger-based updates:

```sql
ALTER TABLE entries ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || COALESCE(description, ''))) STORED;

CREATE INDEX idx_entries_search_vector ON entries USING GIN (search_vector);
```

### Pagination Best Practices

**Offset pagination** (used in API):
- Simple to implement
- Performance degrades for large offsets
- Acceptable for datasets < 10,000 rows per user

**Keyset pagination** (recommended for large datasets):
```sql
-- First page
SELECT * FROM entries
WHERE collection_id = $1
ORDER BY date DESC, id DESC
LIMIT 20;

-- Next page (using last row's date and id)
SELECT * FROM entries
WHERE collection_id = $1
  AND (date, id) < ($last_date, $last_id)
ORDER BY date DESC, id DESC
LIMIT 20;
```

### Join Optimization

For entries with images, use a single query with JSON aggregation instead of N+1 queries:

```sql
-- GOOD: Single query with JSON aggregation
SELECT e.*,
    COALESCE(json_agg(json_build_object(
        'id', i.id,
        'url', i.url,
        'isCover', i.is_cover
    ) ORDER BY i.is_cover DESC, i.position)
    FILTER (WHERE i.id IS NOT NULL), '[]') as images
FROM entries e
LEFT JOIN entry_images i ON i.entry_id = e.id
WHERE e.collection_id = $1
GROUP BY e.id
ORDER BY e.date DESC
LIMIT 20;

-- BAD: N+1 queries
-- 1. SELECT * FROM entries WHERE collection_id = $1 LIMIT 20;
-- 2. For each entry: SELECT * FROM entry_images WHERE entry_id = $entry_id;
```

---

## Data Retention

### Soft Delete Policy

**Users only:** Soft delete via `deleted_at` timestamp
- Allows data recovery within retention period
- Supports GDPR "right to be forgotten" with deferred anonymization
- Background job anonymizes data after 30 days

**Content:** Hard delete (cascade)
- Collections, entries, images are permanently deleted
- No soft delete needed as they cascade from user deletion

### Token Cleanup Procedure

Run daily via scheduled job (cron, pg_cron, or application scheduler):

```sql
-- Delete expired and revoked tokens older than 7 days
DELETE FROM user_tokens
WHERE expires_at < NOW() - INTERVAL '7 days'
   OR (revoked_at IS NOT NULL AND revoked_at < NOW() - INTERVAL '7 days');

-- Log cleanup result
-- Expected: removes thousands of rows daily for active apps
```

### GDPR Compliance (User Deletion)

**Immediate actions (DELETE /auth/account):**
1. Set `users.deleted_at = NOW()`
2. Revoke all refresh tokens
3. Delete all collections (cascades to entries and images)
4. Delete image files from object storage (async)

**Deferred anonymization (background job, 30 days later):**
```sql
UPDATE users
SET email = NULL,
    display_name = 'Deleted User',
    updated_at = NOW()
WHERE deleted_at < NOW() - INTERVAL '30 days'
  AND email IS NOT NULL;
```

---

## Changelog

### v1.0 (2025-01-31)
- Initial database schema documentation
- Tables: users, user_auth_providers, user_tokens, user_passwords, collections, entries, entry_images
- Performance considerations and index strategies
- Data retention policies and GDPR compliance
- Backup strategy recommendations
