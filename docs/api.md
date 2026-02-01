# Livlogios Backend API Specification

**Version:** 1.0
**Base URL:** `https://api.livlogios.app/api/v1`

## Table of Contents

1. [Authentication](#authentication)
2. [Common Headers](#common-headers)
3. [Error Responses](#error-responses)
4. [AI Search](#ai-search)
5. [Collections](#collections)
6. [Entries](#entries)

---

## Authentication

The API uses JWT (JSON Web Token) for authentication. The primary login method is Sign in with Apple.

> Detailed documentation: [docs/auth.md](./auth.md)

### Headers

```
Authorization: Bearer <access_token>
```

### POST /auth/apple

Authentication via Apple Sign In.

**Request:**
```json
{
  "identity_token": "eyJraWQiOiJXNldjT0...",
  "authorization_code": "c1234567890abcdef...",
  "full_name": {
    "given_name": "John",
    "family_name": "Doe"
  },
  "email": "user@example.com"
}
```

**Note:** `full_name` and `email` are only provided on the first authorization. All fields except `identity_token` are optional.

**Response (200):**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2g...",
  "expires_in": 3600,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "email_verified": true,
    "display_name": "John Doe",
    "auth_providers": ["apple"],
    "created_at": "2025-01-20T10:00:00Z",
    "updated_at": "2025-01-20T10:00:00Z"
  }
}
```

**curl:**
```bash
curl -X POST https://api.livlogios.app/api/v1/auth/apple \
  -H "Content-Type: application/json" \
  -d '{"identity_token": "eyJraWQiOiJXNldjT0..."}'
```

### POST /auth/refresh

Refresh access token using refresh token.

**Request:**
```json
{
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2g..."
}
```

**Response (200):**
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "refresh_token": "bmV3IHJlZnJlc2ggdG9rZW4...",
  "expires_in": 3600,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "email_verified": true,
    "display_name": "John Doe",
    "auth_providers": ["apple"],
    "created_at": "2025-01-20T10:00:00Z",
    "updated_at": "2025-01-20T10:00:00Z"
  }
}
```

**curl:**
```bash
curl -X POST https://api.livlogios.app/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "dGhpcyBpcyBhIHJlZnJlc2g..."}'
```

### POST /auth/logout

Invalidate refresh token.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Request:**
```json
{
  "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2g..."
}
```

**Response (200):**
```json
{
  "message": "Logged out successfully"
}
```

### GET /auth/me

Get current user information.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "email_verified": true,
  "display_name": "John Doe",
  "auth_providers": ["apple"],
  "created_at": "2025-01-20T10:00:00Z",
  "updated_at": "2025-01-20T10:00:00Z"
}
```

### DELETE /auth/account

Delete user account (soft delete).

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "message": "Account deleted successfully"
}
```

---

## Common Headers

All requests must include:

```
Content-Type: application/json
Authorization: Bearer <jwt_token>
```

---

## Error Responses

### Standard Error Format

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": {}
  }
}
```

### Error Codes

| HTTP Code | Error Code | Description |
|-----------|------------|-------------|
| 400 | `BAD_REQUEST` | Invalid request data |
| 401 | `UNAUTHORIZED` | Missing or invalid token |
| 403 | `FORBIDDEN` | No access to resource |
| 404 | `NOT_FOUND` | Resource not found |
| 422 | `VALIDATION_ERROR` | Data validation error |
| 500 | `INTERNAL_ERROR` | Internal server error |

**Validation Error Example (422):**
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": {
      "title": ["Title is required", "Title must be at least 1 character"]
    }
  }
}
```

---

## AI Search

### POST /search

Search for content (movies, books, games) using AI.

**Request:**
```json
{
  "query": "Inception movie"
}
```

**Response (200):**
```json
{
  "options": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Inception",
      "entryType": "movie",
      "year": "2010",
      "genre": "Sci-Fi, Thriller",
      "author": null,
      "platform": null,
      "summaryLine": "2010 • Sci-Fi, Thriller • Christopher Nolan",
      "description": "A thief who steals corporate secrets through dream-sharing technology is given the task of planting an idea into the mind of a C.E.O.",
      "imageUrls": [
        "https://example.com/inception-poster.jpg",
        "https://example.com/inception-scene1.jpg"
      ]
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "title": "Inception: The Shooting Script",
      "entryType": "book",
      "year": "2010",
      "genre": "Screenplay",
      "author": "Christopher Nolan",
      "platform": null,
      "summaryLine": "2010 • Screenplay • Christopher Nolan",
      "description": "The complete shooting script of the film with an introduction by the director.",
      "imageUrls": [
        "https://example.com/inception-book.jpg"
      ]
    }
  ]
}
```

**curl:**
```bash
curl -X POST https://api.livlogios.app/api/v1/search \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"query": "Inception movie"}'
```

---

## Collections

### Collection Object

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Movies",
  "icon": "🎬",
  "createdAt": "2025-01-15T10:30:00Z",
  "entriesCount": 42
}
```

### GET /collections

Get list of all user's collections.

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `sort` | string | `createdAt` | Sort field: `name`, `createdAt`, `entriesCount` |
| `order` | string | `desc` | Direction: `asc`, `desc` |

**Response (200):**
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Movies",
      "icon": "🎬",
      "createdAt": "2025-01-15T10:30:00Z",
      "entriesCount": 42
    },
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "Books",
      "icon": "📚",
      "createdAt": "2025-01-15T10:30:00Z",
      "entriesCount": 15
    }
  ]
}
```

**curl:**
```bash
curl -X GET "https://api.livlogios.app/api/v1/collections?sort=name&order=asc" \
  -H "Authorization: Bearer <token>"
```

### GET /collections/{id}

Get a single collection by ID.

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Movies",
  "icon": "🎬",
  "createdAt": "2025-01-15T10:30:00Z",
  "entriesCount": 42
}
```

**Response (404):**
```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Collection not found"
  }
}
```

### POST /collections

Create a new collection.

**Request:**
```json
{
  "name": "TV Shows",
  "icon": "📺"
}
```

**Response (201):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440002",
  "name": "TV Shows",
  "icon": "📺",
  "createdAt": "2025-01-20T14:00:00Z",
  "entriesCount": 0
}
```

**curl:**
```bash
curl -X POST https://api.livlogios.app/api/v1/collections \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"name": "TV Shows", "icon": "📺"}'
```

### PUT /collections/{id}

Update an existing collection.

**Request:**
```json
{
  "name": "Favorite Movies",
  "icon": "🎥"
}
```

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Favorite Movies",
  "icon": "🎥",
  "createdAt": "2025-01-15T10:30:00Z",
  "entriesCount": 42
}
```

### DELETE /collections/{id}

Delete a collection. **Warning:** deletes all entries in the collection (cascade delete).

**Response (204):** No Content

**Response (404):**
```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Collection not found"
  }
}
```

**curl:**
```bash
curl -X DELETE https://api.livlogios.app/api/v1/collections/550e8400-e29b-41d4-a716-446655440000 \
  -H "Authorization: Bearer <token>"
```

---

## Entries

### Entry Object

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440100",
  "collectionId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Inception",
  "description": "2010 • Sci-Fi, Thriller • Christopher Nolan\nA mind-bending thriller about dream infiltration.",
  "score": 3,
  "date": "2025-01-18T00:00:00Z",
  "createdAt": "2025-01-18T15:30:00Z",
  "additionalFields": {
    "Year": "2010",
    "Genre": "Sci-Fi, Thriller"
  },
  "images": [
    {
      "id": "img-001",
      "url": "https://cdn.livlogios.app/images/img-001.jpg",
      "isCover": true
    },
    {
      "id": "img-002",
      "url": "https://cdn.livlogios.app/images/img-002.jpg",
      "isCover": false
    }
  ]
}
```

### Score Values

| Value | Name | Emoji | Description |
|-------|------|-------|-------------|
| 0 | `undecided` | 🆕 | Undecided, ask me later |
| 1 | `bad` | 👎 | Not my thing at all |
| 2 | `okay` | 👌 | Fine for once |
| 3 | `great` | 🤩 | Absolutely unhinged |

### GET /entries

Get list of entries with pagination and filtering.

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `collectionId` | uuid | - | Filter by collection |
| `score` | int | - | Filter by score (0-3) |
| `search` | string | - | Search by title and description |
| `sort` | string | `date` | Sort field: `date`, `createdAt`, `title`, `score` |
| `order` | string | `desc` | Direction: `asc`, `desc` |
| `limit` | int | 20 | Number of records (max: 100) |
| `offset` | int | 0 | Offset for pagination |

**Response (200):**
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440100",
      "collectionId": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Inception",
      "description": "2010 • Sci-Fi, Thriller • Christopher Nolan\nA mind-bending thriller.",
      "score": 3,
      "date": "2025-01-18T00:00:00Z",
      "createdAt": "2025-01-18T15:30:00Z",
      "additionalFields": {
        "Year": "2010",
        "Genre": "Sci-Fi, Thriller"
      },
      "images": [
        {
          "id": "img-001",
          "url": "https://cdn.livlogios.app/images/img-001.jpg",
          "isCover": true
        }
      ]
    }
  ],
  "pagination": {
    "total": 42,
    "limit": 20,
    "offset": 0,
    "hasMore": true
  }
}
```

**curl:**
```bash
curl -X GET "https://api.livlogios.app/api/v1/entries?collectionId=550e8400-e29b-41d4-a716-446655440000&limit=20&offset=0" \
  -H "Authorization: Bearer <token>"
```

### GET /entries/{id}

Get a single entry by ID.

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440100",
  "collectionId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Inception",
  "description": "2010 • Sci-Fi, Thriller • Christopher Nolan\nA mind-bending thriller about dream infiltration.",
  "score": 3,
  "date": "2025-01-18T00:00:00Z",
  "createdAt": "2025-01-18T15:30:00Z",
  "additionalFields": {
    "Year": "2010",
    "Genre": "Sci-Fi, Thriller"
  },
  "images": [
    {
      "id": "img-001",
      "url": "https://cdn.livlogios.app/images/img-001.jpg",
      "isCover": true
    },
    {
      "id": "img-002",
      "url": "https://cdn.livlogios.app/images/img-002.jpg",
      "isCover": false
    }
  ]
}
```

### POST /entries

Create a new entry.

**Request (JSON with base64 images):**
```json
{
  "collectionId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "The Matrix",
  "description": "1999 • Sci-Fi, Action • Wachowski Sisters\nA computer hacker learns about the true nature of reality.",
  "score": 3,
  "date": "2025-01-20T00:00:00Z",
  "additionalFields": {
    "Year": "1999",
    "Genre": "Sci-Fi, Action"
  },
  "images": [
    {
      "data": "base64_encoded_image_data...",
      "isCover": true
    }
  ]
}
```

**Alternative: Multipart Form Data**

For uploading images, you can use `multipart/form-data`:

```
POST /entries
Content-Type: multipart/form-data

--boundary
Content-Disposition: form-data; name="data"
Content-Type: application/json

{"collectionId": "...", "title": "The Matrix", ...}
--boundary
Content-Disposition: form-data; name="images"; filename="cover.jpg"
Content-Type: image/jpeg

<binary image data>
--boundary
Content-Disposition: form-data; name="images"; filename="scene1.jpg"
Content-Type: image/jpeg

<binary image data>
--boundary--
```

**Response (201):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440101",
  "collectionId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "The Matrix",
  "description": "1999 • Sci-Fi, Action • Wachowski Sisters\nA computer hacker learns about the true nature of reality.",
  "score": 3,
  "date": "2025-01-20T00:00:00Z",
  "createdAt": "2025-01-20T16:45:00Z",
  "additionalFields": {
    "Year": "1999",
    "Genre": "Sci-Fi, Action"
  },
  "images": [
    {
      "id": "img-003",
      "url": "https://cdn.livlogios.app/images/img-003.jpg",
      "isCover": true
    }
  ]
}
```

**curl (JSON):**
```bash
curl -X POST https://api.livlogios.app/api/v1/entries \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "collectionId": "550e8400-e29b-41d4-a716-446655440000",
    "title": "The Matrix",
    "description": "1999 • Sci-Fi, Action",
    "score": 3,
    "date": "2025-01-20T00:00:00Z"
  }'
```

**curl (Multipart):**
```bash
curl -X POST https://api.livlogios.app/api/v1/entries \
  -H "Authorization: Bearer <token>" \
  -F 'data={"collectionId":"...","title":"The Matrix","score":3};type=application/json' \
  -F 'images=@cover.jpg'
```

### PUT /entries/{id}

Update an existing entry.

**Request:**
```json
{
  "title": "The Matrix Reloaded",
  "score": 2,
  "additionalFields": {
    "Year": "2003",
    "Genre": "Sci-Fi, Action"
  }
}
```

**Response (200):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440101",
  "collectionId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "The Matrix Reloaded",
  "description": "1999 • Sci-Fi, Action • Wachowski Sisters\nA computer hacker learns about the true nature of reality.",
  "score": 2,
  "date": "2025-01-20T00:00:00Z",
  "createdAt": "2025-01-20T16:45:00Z",
  "additionalFields": {
    "Year": "2003",
    "Genre": "Sci-Fi, Action"
  },
  "images": [
    {
      "id": "img-003",
      "url": "https://cdn.livlogios.app/images/img-003.jpg",
      "isCover": true
    }
  ]
}
```

### DELETE /entries/{id}

Delete an entry.

**Response (204):** No Content

**curl:**
```bash
curl -X DELETE https://api.livlogios.app/api/v1/entries/550e8400-e29b-41d4-a716-446655440101 \
  -H "Authorization: Bearer <token>"
```

---

## Image Management

### PUT /entries/{id}/images

Manage entry images (add, remove, reorder).

**Request:**
```json
{
  "images": [
    {
      "id": "img-002",
      "isCover": true
    },
    {
      "id": "img-001",
      "isCover": false
    }
  ],
  "add": [
    {
      "data": "base64_encoded_image_data...",
      "isCover": false
    }
  ],
  "remove": ["img-003"]
}
```

**Response (200):**
```json
{
  "images": [
    {
      "id": "img-002",
      "url": "https://cdn.livlogios.app/images/img-002.jpg",
      "isCover": true
    },
    {
      "id": "img-001",
      "url": "https://cdn.livlogios.app/images/img-001.jpg",
      "isCover": false
    },
    {
      "id": "img-004",
      "url": "https://cdn.livlogios.app/images/img-004.jpg",
      "isCover": false
    }
  ]
}
```

---

## Rate Limiting

The API uses rate limiting to protect against abuse.

**Response Headers:**
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1706540400
```

**When limit is exceeded (429):**
```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests. Please try again later.",
    "details": {
      "retryAfter": 60
    }
  }
}
```

---

## Changelog

### v1.1 (2025-01-28)
- Updated Authentication section with Sign in with Apple
- Added `/auth/apple`, `/auth/refresh`, `/auth/logout`, `/auth/me`, `/auth/account` endpoints
- Removed email/password authentication (planned for future)
- Added link to detailed auth documentation

### v1.0 (2025-01-28)
- Initial API specification
- Authentication with JWT
- Collections CRUD
- Entries CRUD with pagination and filtering
- AI Search endpoint
- Image management
