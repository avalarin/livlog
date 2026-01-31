# Authentication System

**Version:** 1.0
**Last Updated:** 2025-01-28

## Overview

Livlogios uses Sign in with Apple as the primary authentication method. The architecture is designed to support additional auth providers in the future (email/password, Google, etc.) without breaking changes.

### Key Principles

- **Apple Sign In** - the only active authentication method
- **JWT tokens** - for API request authentication
- **Multi-provider architecture** - ready for expansion
- **Secure by default** - all best practices out of the box

---

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   iOS Client    │────▶│   Apple Auth    │     │                 │
│                 │◀────│   Services      │     │                 │
└────────┬────────┘     └─────────────────┘     │                 │
         │                                      │    Livlogios    │
         │ identity_token                       │    Backend      │
         │                                      │                 │
         ▼                                      │                 │
┌─────────────────┐     ┌─────────────────┐     │                 │
│  POST /auth/    │────▶│  Verify token   │────▶│                 │
│     apple       │     │  with Apple     │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │   PostgreSQL    │
                                                │   - users       │
                                                │   - providers   │
                                                │   - tokens      │
                                                └─────────────────┘
```

---

## Sign in with Apple Flow

### Step 1: iOS Client - Initiate Sign In

```swift
import AuthenticationServices

class AppleSignInManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var error: Error?

    func signIn() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }
}

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            return
        }

        // Send to backend
        Task {
            await authenticateWithBackend(
                identityToken: tokenString,
                authorizationCode: String(data: credential.authorizationCode ?? Data(), encoding: .utf8),
                fullName: credential.fullName,
                email: credential.email
            )
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        self.error = error
    }
}
```

### Step 2: Send Identity Token to Backend

```swift
struct AppleAuthRequest: Encodable {
    let identityToken: String
    let authorizationCode: String?
    let fullName: PersonNameComponents?
    let email: String?
}

func authenticateWithBackend(
    identityToken: String,
    authorizationCode: String?,
    fullName: PersonNameComponents?,
    email: String?
) async {
    let url = URL(string: "https://api.livlogios.app/api/v1/auth/apple")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body = AppleAuthRequest(
        identityToken: identityToken,
        authorizationCode: authorizationCode,
        fullName: fullName,
        email: email
    )
    request.httpBody = try? JSONEncoder().encode(body)

    let (data, _) = try await URLSession.shared.data(for: request)
    let response = try JSONDecoder().decode(AuthResponse.self, from: data)

    // Store tokens in Keychain
    KeychainManager.save(accessToken: response.accessToken)
    KeychainManager.save(refreshToken: response.refreshToken)
}
```

### Step 3: Backend - Verify Apple Token

The backend must verify the identity token with Apple:

```python
# Python example (FastAPI)
import jwt
import httpx
from jwt import PyJWKClient

APPLE_PUBLIC_KEY_URL = "https://appleid.apple.com/auth/keys"
APPLE_TOKEN_ISSUER = "https://appleid.apple.com"
APP_BUNDLE_ID = "net.avalarin.livlogios"

async def verify_apple_token(identity_token: str) -> dict:
    """
    Verify Apple identity token and extract user info.

    Returns:
        dict with 'sub' (Apple user ID), 'email', 'email_verified'
    """
    # Fetch Apple's public keys
    jwk_client = PyJWKClient(APPLE_PUBLIC_KEY_URL)
    signing_key = jwk_client.get_signing_key_from_jwt(identity_token)

    # Verify and decode token
    payload = jwt.decode(
        identity_token,
        signing_key.key,
        algorithms=["RS256"],
        audience=APP_BUNDLE_ID,
        issuer=APPLE_TOKEN_ISSUER
    )

    return {
        "apple_user_id": payload["sub"],
        "email": payload.get("email"),
        "email_verified": payload.get("email_verified", False),
        "is_private_email": payload.get("is_private_email", False)
    }
```

```javascript
// Node.js example (Express)
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const client = jwksClient({
  jwksUri: 'https://appleid.apple.com/auth/keys',
  cache: true,
  rateLimit: true
});

async function verifyAppleToken(identityToken) {
  const decoded = jwt.decode(identityToken, { complete: true });
  const key = await client.getSigningKey(decoded.header.kid);

  const payload = jwt.verify(identityToken, key.getPublicKey(), {
    algorithms: ['RS256'],
    issuer: 'https://appleid.apple.com',
    audience: 'net.avalarin.livlogios'
  });

  return {
    appleUserId: payload.sub,
    email: payload.email,
    emailVerified: payload.email_verified
  };
}
```

### Step 4: Backend - Create/Login User

```python
async def authenticate_apple(request: AppleAuthRequest) -> AuthResponse:
    # 1. Verify Apple token
    apple_data = await verify_apple_token(request.identity_token)

    # 2. Find or create user
    auth_provider = await db.query(
        "SELECT * FROM user_auth_providers WHERE provider = 'apple' AND provider_user_id = $1",
        apple_data["apple_user_id"]
    )

    if auth_provider:
        # Existing user - login
        user = await db.query("SELECT * FROM users WHERE id = $1", auth_provider.user_id)
    else:
        # New user - register
        user = await db.execute("""
            INSERT INTO users (email, email_verified, display_name)
            VALUES ($1, $2, $3)
            RETURNING *
        """, apple_data["email"], apple_data["email_verified"], request.full_name)

        await db.execute("""
            INSERT INTO user_auth_providers (user_id, provider, provider_user_id)
            VALUES ($1, 'apple', $2)
        """, user.id, apple_data["apple_user_id"])

    # 3. Generate JWT tokens
    access_token = generate_access_token(user)
    refresh_token = generate_refresh_token(user)

    # 4. Store refresh token
    await db.execute("""
        INSERT INTO user_tokens (user_id, refresh_token_hash, expires_at)
        VALUES ($1, $2, $3)
    """, user.id, hash(refresh_token), datetime.now() + timedelta(days=30))

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=3600,
        user=UserResponse.from_model(user)
    )
```

---

## JWT Tokens

### Access Token

Short-lived token for authenticating API requests.

**Structure:**
```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT"
  },
  "payload": {
    "sub": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "iat": 1706540400,
    "exp": 1706544000,
    "iss": "https://api.livlogios.app",
    "aud": "livlogios-ios"
  }
}
```

**Claims:**

| Claim | Description |
|-------|-------------|
| `sub` | User ID (UUID) |
| `email` | User email (may be Apple private relay) |
| `iat` | Issued at (Unix timestamp) |
| `exp` | Expiration (Unix timestamp) |
| `iss` | Issuer |
| `aud` | Audience |

**Lifetime:** 1 hour (3600 seconds)

**Signing Algorithm:** RS256 (RSA + SHA-256)

### Refresh Token

Long-lived token for obtaining new access tokens.

**Structure:**
- Random 256-bit string
- Base64 encoded
- Stored as SHA-256 hash in database

**Lifetime:** 30 days

**Rotation:** A new refresh token is issued on each use (rotation strategy)

### Token Generation

```python
import jwt
from datetime import datetime, timedelta
from cryptography.hazmat.primitives import serialization

# Load private key from environment/secrets manager
PRIVATE_KEY = load_private_key()

def generate_access_token(user: User) -> str:
    payload = {
        "sub": str(user.id),
        "email": user.email,
        "iat": datetime.utcnow(),
        "exp": datetime.utcnow() + timedelta(hours=1),
        "iss": "https://api.livlogios.app",
        "aud": "livlogios-ios"
    }
    return jwt.encode(payload, PRIVATE_KEY, algorithm="RS256")

def generate_refresh_token() -> str:
    import secrets
    return secrets.token_urlsafe(32)
```

---

## API Endpoints

### POST /auth/apple

Authentication via Apple Sign In.

**Request:**
```json
{
  "identityToken": "eyJraWQiOiJXNldjT0...",
  "authorizationCode": "c1234567890abcdef...",
  "fullName": {
    "givenName": "John",
    "familyName": "Doe"
  },
  "email": "user@example.com"
}
```

**Note:** `fullName` and `email` are only provided on the first authorization. Apple does not return them on subsequent logins.

**Response (200):**
```json
{
  "accessToken": "eyJhbGciOiJSUzI1NiIs...",
  "refreshToken": "dGhpcyBpcyBhIHJlZnJlc2g...",
  "expiresIn": 3600,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "displayName": "John Doe",
    "createdAt": "2025-01-20T10:00:00Z"
  }
}
```

**Response (401) - Invalid Token:**
```json
{
  "error": {
    "code": "INVALID_TOKEN",
    "message": "Apple identity token is invalid or expired"
  }
}
```

**curl:**
```bash
curl -X POST https://api.livlogios.app/api/v1/auth/apple \
  -H "Content-Type: application/json" \
  -d '{
    "identityToken": "eyJraWQiOiJXNldjT0...",
    "authorizationCode": "c1234567890abcdef..."
  }'
```

### POST /auth/refresh

Refresh access token using refresh token.

**Request:**
```json
{
  "refreshToken": "dGhpcyBpcyBhIHJlZnJlc2g..."
}
```

**Response (200):**
```json
{
  "accessToken": "eyJhbGciOiJSUzI1NiIs...",
  "refreshToken": "bmV3IHJlZnJlc2ggdG9rZW4...",
  "expiresIn": 3600
}
```

**Note:** A new refresh token is returned (token rotation). The old one becomes invalid.

**Response (401) - Invalid/Expired Token:**
```json
{
  "error": {
    "code": "INVALID_REFRESH_TOKEN",
    "message": "Refresh token is invalid or expired"
  }
}
```

**curl:**
```bash
curl -X POST https://api.livlogios.app/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refreshToken": "dGhpcyBpcyBhIHJlZnJlc2g..."}'
```

### POST /auth/logout

Invalidate refresh token (logout).

**Headers:**
```
Authorization: Bearer <access_token>
```

**Request:**
```json
{
  "refreshToken": "dGhpcyBpcyBhIHJlZnJlc2g..."
}
```

**Response (204):** No Content

**curl:**
```bash
curl -X POST https://api.livlogios.app/api/v1/auth/logout \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{"refreshToken": "dGhpcyBpcyBhIHJlZnJlc2g..."}'
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
  "displayName": "John Doe",
  "emailVerified": true,
  "authProviders": ["apple"],
  "createdAt": "2025-01-20T10:00:00Z",
  "updatedAt": "2025-01-25T15:30:00Z"
}
```

**curl:**
```bash
curl -X GET https://api.livlogios.app/api/v1/auth/me \
  -H "Authorization: Bearer <access_token>"
```

### DELETE /auth/account

Delete user account (GDPR compliance).

**Headers:**
```
Authorization: Bearer <access_token>
```

**Response (204):** No Content

**Note:** Deletes the user and all associated data (collections, entries, images).

---

## Database Schema

### users

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255),
    email_verified BOOLEAN DEFAULT FALSE,
    display_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE  -- soft delete
);

CREATE UNIQUE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL AND deleted_at IS NULL;
```

**Notes:**
- `email` can be NULL (Apple private relay user may not provide email)
- `email` is unique only among active users
- Soft delete for GDPR compliance

### user_auth_providers

```sql
CREATE TABLE user_auth_providers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,  -- 'apple', 'email', 'google'
    provider_user_id VARCHAR(255) NOT NULL,  -- Apple user ID, email, Google ID
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    UNIQUE(provider, provider_user_id)
);

CREATE INDEX idx_auth_providers_user ON user_auth_providers(user_id);
CREATE INDEX idx_auth_providers_lookup ON user_auth_providers(provider, provider_user_id);
```

**Provider Types:**

| Provider | provider_user_id |
|----------|------------------|
| `apple` | Apple user ID (sub claim) |
| `email` | User's email address |
| `google` | Google user ID |

### user_tokens

```sql
CREATE TABLE user_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(64) NOT NULL,  -- SHA-256 hash
    device_info JSONB,  -- optional: device name, OS version
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at TIMESTAMP WITH TIME ZONE  -- for logout
);

CREATE INDEX idx_user_tokens_user ON user_tokens(user_id);
CREATE INDEX idx_user_tokens_hash ON user_tokens(refresh_token_hash) WHERE revoked_at IS NULL;
CREATE INDEX idx_user_tokens_cleanup ON user_tokens(expires_at) WHERE revoked_at IS NULL;
```

### user_passwords (future - email auth)

```sql
-- For future email authentication
CREATE TABLE user_passwords (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    password_hash VARCHAR(255) NOT NULL,  -- Argon2id hash
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    UNIQUE(user_id)
);
```

---

## Future: Email Authentication

The architecture is designed to add email auth without breaking changes.

### Registration Flow

```
POST /auth/register
{
  "email": "user@example.com",
  "password": "securePassword123",
  "displayName": "John Doe"
}

Response (201):
{
  "message": "Verification email sent",
  "email": "user@example.com"
}
```

### Email Verification

```
POST /auth/verify-email
{
  "token": "verification_token_from_email"
}

Response (200):
{
  "accessToken": "...",
  "refreshToken": "...",
  "user": {...}
}
```

### Login

```
POST /auth/login
{
  "email": "user@example.com",
  "password": "securePassword123"
}
```

### Password Reset

```
POST /auth/forgot-password
{
  "email": "user@example.com"
}

POST /auth/reset-password
{
  "token": "reset_token_from_email",
  "newPassword": "newSecurePassword123"
}
```

### Integration with Multi-Provider

When adding email auth:

1. Add record to `user_auth_providers`:
   ```sql
   INSERT INTO user_auth_providers (user_id, provider, provider_user_id)
   VALUES ($1, 'email', $2);  -- provider_user_id = email
   ```

2. Add record to `user_passwords`:
   ```sql
   INSERT INTO user_passwords (user_id, password_hash)
   VALUES ($1, $2);  -- Argon2id hash
   ```

3. A user can have multiple auth providers:
   - Sign in via Apple → link email/password
   - Sign in via email → link Apple ID

---

## Security Considerations

### Token Storage (iOS)

```swift
import Security

class KeychainManager {
    private static let service = "net.avalarin.livlogios"

    static func save(accessToken: String) {
        save(key: "accessToken", value: accessToken)
    }

    static func save(refreshToken: String) {
        save(key: "refreshToken", value: refreshToken)
    }

    private static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### Rate Limiting

| Endpoint | Limit | Window |
|----------|-------|--------|
| `POST /auth/apple` | 10 requests | 1 minute |
| `POST /auth/refresh` | 30 requests | 1 minute |
| `POST /auth/logout` | 10 requests | 1 minute |
| `POST /auth/login` (future) | 5 requests | 1 minute |
| `POST /auth/forgot-password` (future) | 3 requests | 1 hour |

### Password Handling (future)

```python
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError

ph = PasswordHasher(
    time_cost=2,
    memory_cost=65536,  # 64 MB
    parallelism=4
)

def hash_password(password: str) -> str:
    return ph.hash(password)

def verify_password(hash: str, password: str) -> bool:
    try:
        ph.verify(hash, password)
        return True
    except VerifyMismatchError:
        return False
```

### HTTPS Only

All auth endpoints must work only over HTTPS:

```python
# Middleware example
@app.middleware("http")
async def enforce_https(request: Request, call_next):
    if request.url.scheme != "https" and not settings.DEBUG:
        return Response(status_code=400, content="HTTPS required")
    return await call_next(request)
```

### Token Expiration Policy

| Token Type | Lifetime | Renewal |
|------------|----------|---------|
| Access Token | 1 hour | Via refresh token |
| Refresh Token | 30 days | Rotation on each use |
| Apple Identity Token | ~10 minutes | Re-authenticate with Apple |

---

## Implementation Checklist

### iOS Client

- [ ] Integrate AuthenticationServices framework
- [ ] Implement `ASAuthorizationControllerDelegate`
- [ ] Handle first-time vs returning user (fullName/email)
- [ ] Send identity token to backend
- [ ] Store tokens in Keychain
- [ ] Implement token refresh logic
- [ ] Handle 401 responses (auto-refresh or re-login)
- [ ] Implement logout (clear Keychain)
- [ ] Handle Apple credential revocation

### Backend

- [ ] Create database tables with migrations
- [ ] Implement Apple token verification
- [ ] Implement JWT token generation (RS256)
- [ ] Implement `/auth/apple` endpoint
- [ ] Implement `/auth/refresh` endpoint
- [ ] Implement `/auth/logout` endpoint
- [ ] Implement `/auth/me` endpoint
- [ ] Implement `/auth/account` DELETE endpoint
- [ ] Add auth middleware for protected routes
- [ ] Implement rate limiting
- [ ] Set up RSA key pair for JWT signing
- [ ] Add token cleanup job (expired tokens)

### Security

- [ ] HTTPS only for all endpoints
- [ ] Secure key storage (environment variables or KMS)
- [ ] Rate limiting on auth endpoints
- [ ] Audit logging for auth events
- [ ] Token revocation on password change (future)

### Testing

- [ ] Unit tests for token verification
- [ ] Integration tests for auth flow
- [ ] Test token expiration handling
- [ ] Test rate limiting
- [ ] Test concurrent refresh requests
- [ ] Test account deletion cascade

---

## Changelog

### v1.0 (2025-01-28)
- Initial authentication specification
- Sign in with Apple implementation
- JWT token structure
- Database schema for multi-provider auth
- Future email authentication design
