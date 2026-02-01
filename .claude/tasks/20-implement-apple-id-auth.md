Реализовать полноценную авторизацию пользователей через Apple ID с интеграцией между iOS приложением и backend сервисом.

## Задача

Внедрить Sign in with Apple как основной метод авторизации для livlogios. Пользователь должен авторизоваться через Apple ID при первом запуске приложения, после чего все запросы к API будут аутентифицированы через JWT токены.

Files to reference:
- @docs/auth.md (полная спецификация авторизации)
- @docs/api.md (API endpoints)
- @docs/database.md (схема БД)
- @backend/migrations/001_create_users_table.up.sql (существующая миграция users)

Files to create:
- **iOS App:**
  - livlogios/Services/AuthService.swift (сервис авторизации)
  - livlogios/Services/KeychainManager.swift (хранение токенов)
  - livlogios/Views/Auth/LoginView.swift (экран авторизации)
  - livlogios/Models/User.swift (модель пользователя)
  - livlogios/Config/AppState.swift (глобальное состояние авторизации)

- **Backend:**
  - backend/internal/handler/auth.go (handlers для auth endpoints)
  - backend/internal/service/auth_service.go (бизнес-логика авторизации)
  - backend/internal/service/jwt_service.go (генерация/валидация JWT)
  - backend/internal/service/apple_verifier.go (верификация Apple токенов)
  - backend/internal/middleware/auth.go (middleware для защищенных роутов)
  - backend/internal/repository/user_repository.go (работа с users, user_auth_providers, user_tokens)
  - backend/migrations/002_create_auth_tables.up.sql (миграции для auth таблиц)
  - backend/migrations/002_create_auth_tables.down.sql

- **Documentation:**
  - Обновить docs/api.md с примерами использования auth endpoints

## Функциональные требования

### 1. iOS App - Экран авторизации

**LoginView.swift:**
- Показывается если пользователь не авторизован (проверка через AppState)
- Надпись для пользователя: "This is where the good stuff starts"
- Кнопка "Sign in with Apple" (стандартная кнопка Apple, SignInWithAppleButton)
- Обработка успешной авторизации и ошибок
- Современный UI с поддержкой темной темы
- Полноэкранный presentation, нельзя dismiss без авторизации

**Состояния:**
- Начальное: кнопка авторизации
- Loading: показывать индикатор во время обработки
- Ошибка: показать alert с текстом ошибки и кнопкой "Try Again"

### 2. iOS App - AuthService

**AuthService.swift:**

Должен предоставлять следующие методы:

```swift
class AuthService: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    @Published var error: Error?

    // Sign in with Apple
    func signInWithApple() async throws -> User

    // Check if user has valid token
    func checkAuthStatus() async -> Bool

    // Refresh access token
    func refreshAccessToken() async throws

    // Logout
    func logout() async throws

    // Delete account
    func deleteAccount() async throws
}
```

**Логика:**
1. Использовать AuthenticationServices framework для Sign in with Apple
2. Получить identity token, authorization code, fullName, email от Apple
3. Отправить на backend `POST /api/v1/auth/apple`
4. Сохранить accessToken и refreshToken в Keychain
5. Обновить состояние isAuthenticated = true, currentUser = user

**Обработка ошибок:**
- Пользователь отменил авторизацию (ASAuthorizationError.canceled)
- Неверный токен от Apple
- Сетевые ошибки (URLError)
- Backend ошибки (4xx, 5xx)

### 3. iOS App - KeychainManager

**KeychainManager.swift:**

```swift
class KeychainManager {
    static let shared = KeychainManager()
    private let service = "net.avalarin.livlog"

    func saveAccessToken(_ token: String)
    func getAccessToken() -> String?
    func deleteAccessToken()

    func saveRefreshToken(_ token: String)
    func getRefreshToken() -> String?
    func deleteRefreshToken()

    func clearAll()
}
```

**Требования:**
- Использовать kSecClassGenericPassword
- kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
- Безопасное хранение токенов
- Обработка ошибок Keychain API

### 4. iOS App - AppState (глобальное состояние)

**AppState.swift:**

```swift
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?

    let authService: AuthService

    init() {
        authService = AuthService()
        Task {
            await checkAuth()
        }
    }

    func checkAuth() async {
        isAuthenticated = await authService.checkAuthStatus()
    }

    func logout() async {
        await authService.logout()
        isAuthenticated = false
        currentUser = nil
    }
}
```

**Интеграция в App:**
- Создать @StateObject var appState = AppState() в livlogiosApp.swift
- Передавать через .environmentObject() всем view
- Показывать LoginView если !isAuthenticated
- Показывать ContentView если isAuthenticated

### 5. iOS App - Модель User

**Models/User.swift:**

```swift
struct User: Codable, Identifiable {
    let id: UUID
    let email: String?
    let displayName: String?
    let emailVerified: Bool
    let authProviders: [String]
    let createdAt: Date
    let updatedAt: Date?
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User
}
```

### 6. iOS App - Автоматическое обновление токенов

**Требования:**
- Перехватывать 401 Unauthorized от любого API endpoint
- Автоматически вызывать `POST /api/v1/auth/refresh`
- Повторить оригинальный запрос с новым access token
- Если refresh тоже вернул 401 → разлогинить пользователя (показать LoginView)

**Реализация:**
- Создать URLSession с custom delegate или использовать Interceptor pattern
- Можно использовать библиотеку Alamofire с RequestInterceptor
- Или реализовать кастомный URLProtocol/middleware

### 7. Backend - Database Migrations

**002_create_auth_tables.up.sql:**

Создать таблицы (если их еще нет после task 19):
- `user_auth_providers` (см. @docs/database.md)
- `user_tokens` (см. @docs/database.md)
- `user_passwords` (для будущего email auth, можно пропустить на первом этапе)

**002_create_auth_tables.down.sql:**
- DROP TABLE user_tokens;
- DROP TABLE user_auth_providers;
- DROP TABLE user_passwords;

**Важно:**
- Проверить что таблица users уже создана в 001_create_users_table.up.sql
- Использовать правильные индексы из @docs/database.md
- Cascade delete при удалении пользователя

### 8. Backend - Apple Token Verification

**internal/service/apple_verifier.go:**

```go
type AppleVerifier struct {
    jwkClient *jwk.Set
}

type AppleTokenClaims struct {
    Sub            string `json:"sub"`
    Email          string `json:"email"`
    EmailVerified  bool   `json:"email_verified"`
    IsPrivateEmail bool   `json:"is_private_email"`
}

func NewAppleVerifier() *AppleVerifier
func (v *AppleVerifier) VerifyIdentityToken(identityToken string) (*AppleTokenClaims, error)
```

**Логика:**
1. Fetch Apple public keys: https://appleid.apple.com/auth/keys
2. Parse JWT identity token (use library like golang-jwt/jwt)
3. Verify signature using Apple's public key
4. Check issuer = "https://appleid.apple.com"
5. Check audience = "net.avalarin.livlog" (bundle ID)
6. Check expiration
7. Return claims: sub (Apple user ID), email, email_verified

**Библиотеки:**
- github.com/golang-jwt/jwt/v5
- github.com/lestrrat-go/jwx/v2/jwk (для работы с JWK)

### 9. Backend - JWT Service

**internal/service/jwt_service.go:**

```go
type JWTService struct {
    privateKey *rsa.PrivateKey
    publicKey  *rsa.PublicKey
}

type AccessTokenClaims struct {
    UserID string `json:"sub"`
    Email  string `json:"email"`
    jwt.RegisteredClaims
}

func NewJWTService(privateKeyPath, publicKeyPath string) (*JWTService, error)
func (s *JWTService) GenerateAccessToken(userID, email string) (string, error)
func (s *JWTService) ValidateAccessToken(tokenString string) (*AccessTokenClaims, error)
func (s *JWTService) GenerateRefreshToken() (string, error)
```

**Требования:**
- Access token: RS256, lifetime 1 hour
- Claims: sub (user ID), email, iat, exp, iss, aud
- Refresh token: random 32-byte string, base64 encoded
- Приватный/публичный ключи читать из файлов или env variables
- Для разработки: генерировать ключи при первом запуске (если файлов нет)

**Генерация RSA ключей (для разработки):**
```bash
# В Justfile добавить команду
openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem
```

### 10. Backend - Auth Service

**internal/service/auth_service.go:**

```go
type AuthService struct {
    userRepo      *repository.UserRepository
    appleVerifier *AppleVerifier
    jwtService    *JWTService
}

type AppleAuthRequest struct {
    IdentityToken     string                  `json:"identityToken"`
    AuthorizationCode string                  `json:"authorizationCode,omitempty"`
    FullName          *PersonNameComponents   `json:"fullName,omitempty"`
    Email             string                  `json:"email,omitempty"`
}

type PersonNameComponents struct {
    GivenName  string `json:"givenName,omitempty"`
    FamilyName string `json:"familyName,omitempty"`
}

type AuthResponse struct {
    AccessToken  string `json:"accessToken"`
    RefreshToken string `json:"refreshToken"`
    ExpiresIn    int    `json:"expiresIn"`
    User         *User  `json:"user"`
}

func NewAuthService(userRepo, appleVerifier, jwtService) *AuthService
func (s *AuthService) AuthenticateWithApple(req *AppleAuthRequest) (*AuthResponse, error)
func (s *AuthService) RefreshToken(refreshToken string) (*AuthResponse, error)
func (s *AuthService) Logout(refreshToken string) error
func (s *AuthService) GetUserByID(userID string) (*User, error)
```

**Логика AuthenticateWithApple:**
1. Verify Apple identity token → get Apple user ID, email
2. Find user by provider='apple' and provider_user_id=apple_user_id
3. Если нашли → Login (обновить tokens)
4. Если не нашли → Register:
   - INSERT INTO users (email, email_verified, display_name)
   - INSERT INTO user_auth_providers (user_id, provider='apple', provider_user_id)
5. Generate access token and refresh token
6. INSERT INTO user_tokens (user_id, refresh_token_hash, expires_at)
7. Return AuthResponse

**Логика RefreshToken:**
1. Hash incoming refresh token (SHA-256)
2. Find token in user_tokens where refresh_token_hash = hash AND revoked_at IS NULL AND expires_at > NOW()
3. Если не нашли → return 401 INVALID_REFRESH_TOKEN
4. Generate new access token and new refresh token
5. Revoke old refresh token (set revoked_at = NOW())
6. Insert new refresh token to user_tokens
7. Return new tokens

### 11. Backend - User Repository

**internal/repository/user_repository.go:**

```go
type UserRepository struct {
    db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository

// Users
func (r *UserRepository) CreateUser(email, displayName string, emailVerified bool) (*User, error)
func (r *UserRepository) GetUserByID(id string) (*User, error)
func (r *UserRepository) GetUserByEmail(email string) (*User, error)
func (r *UserRepository) DeleteUser(id string) error

// Auth Providers
func (r *UserRepository) FindUserByProvider(provider, providerUserID string) (*User, error)
func (r *UserRepository) CreateAuthProvider(userID, provider, providerUserID string) error
func (r *UserRepository) GetUserAuthProviders(userID string) ([]string, error)

// Tokens
func (r *UserRepository) SaveRefreshToken(userID, tokenHash string, expiresAt time.Time) error
func (r *UserRepository) FindRefreshToken(tokenHash string) (*RefreshToken, error)
func (r *UserRepository) RevokeRefreshToken(tokenHash string) error
func (r *UserRepository) RevokeAllUserTokens(userID string) error
```

**SQL запросы:**
- Использовать context.Context для всех запросов
- Использовать pgx named parameters ($1, $2, etc.)
- Обрабатывать pgx.ErrNoRows → return nil, nil (not found)
- Transaction для создания пользователя + auth provider (атомарность)

### 12. Backend - Auth Handlers

**internal/handler/auth.go:**

```go
type AuthHandler struct {
    authService *service.AuthService
}

func NewAuthHandler(authService *service.AuthService) *AuthHandler

func (h *AuthHandler) RegisterRoutes(r chi.Router)

// Endpoints
func (h *AuthHandler) AppleAuth(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) RefreshToken(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) Logout(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) GetMe(w http.ResponseWriter, r *http.Request)
func (h *AuthHandler) DeleteAccount(w http.ResponseWriter, r *http.Request)
```

**Endpoints:**
- POST /api/v1/auth/apple → AppleAuth
- POST /api/v1/auth/refresh → RefreshToken
- POST /api/v1/auth/logout → Logout (требует auth middleware)
- GET /api/v1/auth/me → GetMe (требует auth middleware)
- DELETE /api/v1/auth/account → DeleteAccount (требует auth middleware)

**Обработка ошибок:**
- 400 Bad Request → invalid JSON, validation errors
- 401 Unauthorized → invalid token
- 500 Internal Server Error → database errors, unexpected errors
- Использовать стандартный формат ошибок из @docs/api.md

### 13. Backend - Auth Middleware

**internal/middleware/auth.go:**

```go
func AuthMiddleware(jwtService *service.JWTService) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            // 1. Extract Bearer token from Authorization header
            // 2. Validate JWT token
            // 3. Extract user ID from claims
            // 4. Add user ID to request context
            // 5. Call next.ServeHTTP()
            // 6. If validation fails → return 401 Unauthorized
        })
    }
}

// Helper to get user ID from context
func GetUserIDFromContext(ctx context.Context) string
```

**Логика:**
1. Прочитать header: `Authorization: Bearer <token>`
2. Если header отсутствует → 401
3. Validate token через JWTService
4. Если невалидный/expired → 401
5. Извлечь user ID из claims
6. Добавить в context: `context.WithValue(r.Context(), "userID", userID)`
7. Передать управление следующему handler

### 14. Backend - Integration

**cmd/server/main.go (обновить):**

```go
func main() {
    // ... existing code ...

    // Initialize services
    appleVerifier := service.NewAppleVerifier()
    jwtService := service.NewJWTService(config.JWTPrivateKeyPath, config.JWTPublicKeyPath)

    userRepo := repository.NewUserRepository(db)
    authService := service.NewAuthService(userRepo, appleVerifier, jwtService)

    // Initialize handlers
    authHandler := handler.NewAuthHandler(authService)

    // Setup routes
    r := chi.NewRouter()

    // Public routes
    r.Route("/api/v1", func(r chi.Router) {
        r.Post("/auth/apple", authHandler.AppleAuth)
        r.Post("/auth/refresh", authHandler.RefreshToken)

        // Protected routes
        r.Group(func(r chi.Router) {
            r.Use(middleware.AuthMiddleware(jwtService))

            r.Get("/auth/me", authHandler.GetMe)
            r.Post("/auth/logout", authHandler.Logout)
            r.Delete("/auth/account", authHandler.DeleteAccount)

            // Future: collections, entries endpoints will use this group
        })
    })

    // ... existing code ...
}
```

### 15. Backend - Configuration Updates

**backend/config.yaml (добавить):**

```yaml
jwt:
  private_key_path: "./keys/private_key.pem"
  public_key_path: "./keys/public_key.pem"
  access_token_lifetime: 3600  # 1 hour
  refresh_token_lifetime: 2592000  # 30 days

apple:
  bundle_id: "net.avalarin.livlog"
```

**backend/internal/config/config.go (обновить):**

```go
type Config struct {
    // ... existing fields ...
    JWT JWTConfig `mapstructure:"jwt"`
    Apple AppleConfig `mapstructure:"apple"`
}

type JWTConfig struct {
    PrivateKeyPath       string `mapstructure:"private_key_path"`
    PublicKeyPath        string `mapstructure:"public_key_path"`
    AccessTokenLifetime  int    `mapstructure:"access_token_lifetime"`
    RefreshTokenLifetime int    `mapstructure:"refresh_token_lifetime"`
}

type AppleConfig struct {
    BundleID string `mapstructure:"bundle_id"`
}
```

### 16. Backend - Justfile Commands

**backend/Justfile (добавить):**

```makefile
# Generate RSA keys for JWT signing (development only)
generate-keys:
    mkdir -p keys
    openssl genrsa -out keys/private_key.pem 2048
    openssl rsa -in keys/private_key.pem -pubout -out keys/public_key.pem
    chmod 600 keys/private_key.pem

# Run migrations
migrate-auth:
    migrate -path migrations -database "postgres://user:password@localhost:5432/livlog?sslmode=disable" up
```

### 17. iOS App - Обновление BackendService

Если уже есть BackendService из task 19, обновить его:

**livlogios/Services/BackendService.swift:**

```swift
class BackendService {
    static let shared = BackendService()
    private let baseURL = "http://localhost:8080/api/v1" // TODO: move to config

    // Add authorization header to all requests
    private func makeRequest(url: URL, method: String, body: Data?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method

        // Add access token if available
        if let token = KeychainManager.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // Handle 401 Unauthorized → trigger token refresh
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // TODO: implement automatic token refresh
            throw AuthError.unauthorized
        }

        return (data, response)
    }

    // Add auth-specific methods
    func appleAuth(identityToken: String, authorizationCode: String?, fullName: PersonNameComponents?, email: String?) async throws -> AuthResponse
    func refreshToken(_ refreshToken: String) async throws -> AuthResponse
    func logout(refreshToken: String) async throws
    func getCurrentUser() async throws -> User
    func deleteAccount() async throws
}
```

### 18. iOS App - UI/UX Details

**LoginView Design:**
- Фоновый gradient или цвет из design system
- Логотип приложения вверху (если есть)
- Заголовок: "Welcome to livlog"
- Подзаголовок: "Track and rate your experiences"
- Sign in with Apple button по центру
- Кнопка должна быть стандартной Apple кнопкой (SignInWithAppleButton)
- Использовать .signInWithApple(onRequest:onCompletion:) modifier

**Пример:**
```swift
import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text("Welcome to livlog")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Track and rate your experiences")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isLoading {
                ProgressView()
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .frame(height: 50)
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("Try Again") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        // Implementation
    }
}
```

### 19. Testing Requirements

**iOS App Tests:**
- Unit tests для KeychainManager (save, get, delete)
- Unit tests для AuthService (mock URLSession)
- UI tests для LoginView (XCTest)

**Backend Tests:**
- Unit tests для AppleVerifier (mock Apple public keys)
- Unit tests для JWTService (generate, validate)
- Unit tests для AuthService (mock repositories)
- Integration tests для auth endpoints (testcontainers для PostgreSQL)

**Test Coverage:**
- Минимум 70% coverage для auth-related code

### 20. Documentation

**Обновить docs/api.md:**
- Добавить примеры curl запросов для всех auth endpoints
- Добавить примеры успешных и ошибочных ответов
- Примеры использования Authorization header

**Создать docs/development.md (опционально):**
- Инструкции по настройке Apple Developer account
- Как получить Bundle ID
- Как настроить Sign in with Apple capability в Xcode
- Как сгенерировать JWT ключи для разработки

## Stack and Dependencies

**iOS App:**
- SwiftUI
- AuthenticationServices (Sign in with Apple)
- Security framework (Keychain)
- Foundation (URLSession, Codable)

**Backend (Golang):**
- github.com/golang-jwt/jwt/v5 - JWT generation and validation
- github.com/lestrrat-go/jwx/v2 - JWK support for Apple keys
- github.com/jackc/pgx/v5 - PostgreSQL driver
- golang.org/x/crypto - для SHA-256 hashing (refresh tokens)

**Инфраструктура:**
- PostgreSQL 15+
- OpenSSL (для генерации RSA ключей)

## Важные детали

### Apple Developer Setup

Перед началом работы нужно:
1. Включить Sign in with Apple capability в Xcode project
2. Настроить Bundle ID: `net.avalarin.livlog`
3. Включить Sign in with Apple в Apple Developer Console для этого Bundle ID
4. Тестировать можно на симуляторе с любым Apple ID

### Security

- Токены хранятся ТОЛЬКО в Keychain, никогда в UserDefaults
- Refresh token должен быть хэширован (SHA-256) перед сохранением в БД
- Access token короткоживущий (1 час) для минимизации рисков
- Приватный RSA ключ никогда не коммитится в git (добавить keys/ в .gitignore)
- HTTPS only для production (в разработке можно HTTP для localhost)

### Error Handling

Все ошибки должны быть понятны пользователю:
- "Failed to sign in with Apple" → пользователь понимает что произошло
- "Network error, please try again" → проблемы с сетью
- "Session expired, please sign in again" → токен истек

НЕ показывать технические детали:
- "Invalid JWT signature" → too technical
- "Database error: connection refused" → too technical

### Edge Cases

**Обработать:**
- Пользователь отменил авторизацию через Apple
- Токен от Apple уже истек (редко, но возможно)
- Backend недоступен
- Одновременные запросы на refresh token (race condition)
- Пользователь удалил приложение → токены в Keychain остались
- Apple account был удален или заблокирован

## Dependencies

- Зависит от задачи @.claude/tasks/19-initial-backend-setup.md (backend инфраструктура должна быть готова)
- Зависит от @docs/auth.md (research завершен)
- Зависит от @docs/database.md (схема БД определена)

## Important

- Check Definition of Done from ./CLAUDE.md
- Все коммиты должны проходить SwiftLint для iOS кода
- Все коммиты должны проходить golangci-lint для Go кода
- Тесты должны запускаться и проходить
- Нельзя коммитить приватные ключи (добавить backend/keys/ в .gitignore)
- Backend должен работать с docker-compose up
- iOS app должен собираться в Xcode без ошибок

## Result

<hint>Опишите что было сделано:
- Какие файлы созданы
- Какие endpoints работают
- Как протестировать авторизацию
- Скриншоты LoginView (опционально)
- Проблемы которые возникли и как решили
Удалите эту подсказку после заполнения</hint>
