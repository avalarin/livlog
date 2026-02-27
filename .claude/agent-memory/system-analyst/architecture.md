# iOS App Architecture Notes (livlogios-ag1)

## File Structure

```
livlogios/
  App/
    livlogiosApp.swift          — @main entry, root auth gate
  Config/
    AppConfig.swift             — Environment enum (preview/dev/prod), base URL
    AppState.swift              — ObservableObject: auth state only
  Models/
    Item.swift                  — CollectionModel, EntryModel, EntryTypeModel, ScoreRating, ImageMeta, FieldDefinition
    User.swift                  — User, AuthResponse, AuthError, SendCodeResponse
  Services/
    BackendService.swift        — Core HTTP actor, token injection, error handling
    AuthService.swift           — Apple + email sign-in, token refresh, keychain wrapper
    CollectionService.swift     — CRUD: /collections
    EntryService.swift          — CRUD: /entries, /entries/search, /images/:id
    TypeService.swift           — GET /types
    AISearchService.swift       — POST /search, image download
    ConnectionMonitor.swift     — Periodic health checks, toast state
    KeychainManager.swift       — Secure token storage
  Views/
    ContentView.swift           — Entry list (grid/list), multiselect, FAB, search trigger
    CollectionsView.swift       — Collections list, add/edit/delete, AddEditCollectionView
    AddEntryView.swift          — Create/edit entry, AI search sheet, score/date pickers
    EntryDetailView.swift       — Entry detail, image gallery, edit/delete
    SearchView.swift            — Full-screen entry search with debounce
    ConnectionToastView.swift   — Toast view + ViewModifier + View extension
    Auth/
      LoginView.swift           — Email + Sign in with Apple
      EmailVerificationView.swift — 6-digit code input, resend timer
```

## Navigation Pattern

- Root in `livlogiosApp`: `if isCheckingAuth → ProgressView; else if isAuthenticated → CollectionsView; else → LoginView`
- `CollectionsView` owns the root `NavigationStack` for authenticated flow
- `CollectionsView → ContentView` via `NavigationLink` (push)
- `ContentView → EntryDetailView` via `NavigationLink(destination:)` (push)
- `ContentView` presents `AddEntryView` as `.sheet` (from FAB)
- `ContentView` presents `SearchView` as `.fullScreenCover`
- `EntryDetailView` presents `AddEntryView` as `.sheet` (edit mode)
- `AddEntryView` presents `AISearchBottomSheet`, `DatePickerSheet`, `ScoreSelectionSheet` as `.sheet` with `presentationDetents`
- `CollectionsView` presents `AddEditCollectionView` as `.sheet`
- Auth flow: `LoginView → EmailVerificationView` via `NavigationLink` (push, using `navigationDestination(isPresented:)`)
- NO TabView anywhere — single navigation stack with sheets

## State Management

- `AppState` (@MainActor, ObservableObject): only auth — `isAuthenticated`, `currentUser`, `isCheckingAuth`
- Injected via `.environmentObject(appState)` at root; consumed in `LoginView` and `EmailVerificationView`
- No global data state — each View holds its own `@State` for entries/collections/types
- This means each screen independently fetches data on `.task`; no shared cache
- `@AppStorage("viewMode")` persists grid/list preference across launches
- `@Environment(\.dismiss)` used throughout for sheet dismissal

## Networking Layer

- `BackendService` is a Swift `actor` singleton — thread-safe
- HTTP client: raw `URLSession.shared.data(for:)` — no third-party networking library
- Base URL: `AppConfig.baseURL` = `{backendBaseURL}/api/v1`
  - Preview: `http://localhost:8080`
  - Development: `http://192.168.1.42:8080`
  - Production: `https://prod.livlog.avalarin.net`
- Auth: Bearer token injected from `KeychainManager.shared.getAccessToken()` in `Authorization` header
- Error handling: 401 → `AuthError.unauthorized`; 429 → `AuthError.rateLimitExceeded`; 4xx → `AuthError.serverError`
- `CollectionService`, `EntryService`, `TypeService`, `AISearchService` are all `actor` singletons that call `BackendService.makeAuthenticatedRequest(...)`
- Images: `GET /api/v1/images/{id}` returns raw binary data; inline base64 encoding on upload
- No token auto-refresh on 401 mid-flow — only on app start in `AuthService.checkAuthStatus`

## Data Models

### CollectionModel
- `id: String`, `name: String`, `icon: String` (emoji), `entryCount: Int`, `createdAt/updatedAt: Date`
- ISO8601 date decoding (with/without fractional seconds)

### EntryTypeModel
- `id: String`, `name: String`, `icon: String` (emoji), `fields: [FieldDefinition]`
- `FieldDefinition`: `key: String`, `label: String`, `type: String` ("string" | "number")
- Types are server-managed, fetched from `GET /api/v1/types` (not hardcoded)
- Preview types: Movie, Book, Game, Show, Music, Other

### EntryModel
- `id: String`, `collectionID: String?`, `typeID: String?`, `title: String`, `description: String`
- `score: ScoreRating` (0=undecided, 1=bad, 2=okay, 3=great)
- `date: Date` — encoded as `yyyy-MM-dd` string
- `additionalFields: [String: String]` — flexible key-value metadata per type
- `images: [ImageMeta]` — ordered list with cover flag
- `createdAt/updatedAt: Date` — ISO8601

### ScoreRating
- Int enum: `.undecided=0`, `.bad=1`, `.okay=2`, `.great=3`
- Has `.emoji` and `.label` display properties

### User
- `id: UUID`, `email: String?`, `displayName: String?`, `emailVerified: Bool`
- `authProviders: [String]`, `createdAt: Date`, `updatedAt: Date?`

## Existing Screens

1. `LoginView` — Email + Apple Sign In; no settings/profile
2. `EmailVerificationView` — 6-digit OTP with resend timer (60s)
3. `CollectionsView` — Root post-auth screen; collection list + create/edit/delete
4. `ContentView` — Entry list in grid or list mode; multiselect; bulk delete; fill/clear test data
5. `EntryDetailView` — Full detail view; image gallery (TabView paged); edit + delete
6. `AddEntryView` — Create/edit entry with type picker, AI search, photo picker, score/date sheets
7. `SearchView` — Full-screen search with debounce (300ms), results in list

NO settings screen, NO profile screen, NO account management screen currently exists.

## Toast / Alert UI Patterns

### Toast
- `ConnectionToastView`: custom `View` struct (not a system toast)
- Applied via `ConnectionToastModifier: ViewModifier` using `.overlay(alignment: .bottom)`
- Exposed as `.connectionToast(monitor:)` View extension
- Shows for offline (`isToastSuccess=false`, stays until reconnected) and reconnection (`isToastSuccess=true`, auto-dismisses after 3s)
- `ConnectionMonitor` drives state via `@Published` properties observed via `@ObservedObject`

### Alerts
- All error alerts use the system `.alert("Error", isPresented: $showingError)` pattern
- Every screen that fetches data has its own `@State var errorMessage: String?` + `@State var showingError: Bool`
- Destructive actions (delete) use `.alert` with role `.destructive` Button
- No custom alert styling — pure SwiftUI `.alert` throughout

### Copy-to-clipboard
- No copy-to-clipboard functionality exists anywhere in the codebase currently

## Services Summary

| Service | Type | Endpoints |
|---|---|---|
| `BackendService` | actor | Health, Auth, Token refresh |
| `AuthService` | @MainActor ObservableObject | Apple/email sign-in, logout, deleteAccount |
| `CollectionService` | actor | GET/POST/PUT/DELETE /collections |
| `EntryService` | actor | GET/POST/PUT/DELETE /entries, GET /images/:id |
| `TypeService` | actor | GET /types |
| `AISearchService` | actor | POST /search, image download from URLs |
| `ConnectionMonitor` | @MainActor ObservableObject | Periodic health check every 10s |
| `KeychainManager` | class singleton | access_token, refresh_token in Keychain |

## AppState — Auth Flow

- Checks token on launch via `AuthService.checkAuthStatus()` (calls GET /auth/me; falls back to token refresh)
- `logout()` and `deleteAccount()` both clear Keychain and set `isAuthenticated = false`
- The `authService` property on `AppState` is accessed directly by `LoginView` and `EmailVerificationView` via `@EnvironmentObject`
