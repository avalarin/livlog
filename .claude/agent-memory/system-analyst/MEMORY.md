# System Analyst Memory

Notes:
- Agent threads always have their cwd reset between bash calls, as a result please only use absolute file paths.
- In your final response always share relevant file names and code snippets. Any file paths you return in your response MUST be absolute. Do NOT use relative paths.
- For clear communication with the user the assistant MUST avoid using emojis.
- Do not use a colon before tool calls. Text like "Let me read the file:" followed by a read tool call should just be "Let me read the file." with a period.

Here is useful information about the environment you are running in:
<env>
Working directory: /Users/avprokopev/Projects/livlogios-ag2
Is directory a git repo: Yes
Platform: darwin
Shell: zsh
OS Version: Darwin 25.3.0
</env>
You are powered by the model named Sonnet 4.6. The exact model ID is claude-sonnet-4-6.

## Backend Architecture

See detailed notes: `backend-architecture.md`

Key facts:
- Router: go-chi/chi/v5
- DB: PostgreSQL via pgx/v5 pgxpool
- Auth: RSA-signed JWT (RS256), userID stored in context under key "userID" (plain string)
- Layers: handler -> service -> repository (concrete structs, no interfaces)
- `getUserIDFromContext()` is defined in `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/handler/auth.go` and duplicated in middleware
- `collection_shares` table exists in migration 004, fully implemented in service/repository/handler via feature-sharing branch

## iOS App Architecture

iOS app root: `/Users/avprokopev/Projects/livlogios-ag2/livlogios/` (NOT `livloios`)

### Key Models (`/Users/avprokopev/Projects/livlogios-ag2/livlogios/Models/Item.swift`)
- `CollectionRole` enum — owner, write, read; `canEdit: Bool` (owner only), `canWrite: Bool` (owner or write)
- `CollectionMember` — userId, email, displayName, role: CollectionRole
- `CollectionModel` — id, name, icon (emoji), entryCount, memberCount, myRole: CollectionRole
- `EntryModel` — id, collectionID, typeID, title, description, score, date, additionalFields, images
- `User` — id (UUID), email, displayName, emailVerified, authProviders (in `Models/User.swift`)

### Service Layer (all Swift actors)
- `BackendService` — single HTTP entry point: `makeAuthenticatedRequest(path:method:body:)`, URLSession async/await, Bearer token from Keychain
- `CollectionService` — CRUD /collections + /collections/default + getMembers + addShare + removeShare
- `EntryService` — CRUD /entries, bulk delete, /images/:id
- `KeychainManager` — stores access_token + refresh_token (service: net.avalarin.livlog)
- `AuthService` (@MainActor ObservableObject) — Apple Sign-In + email OTP, holds currentUser: User?
- `AppState` (@MainActor ObservableObject) — top-level auth gate: isAuthenticated, currentUser, isCheckingAuth

### UI Patterns
- Delete confirmation: `.alert(isPresented:)` with Cancel + destructive Delete button used everywhere
- Collection list: `CollectionsView` — List+NavigationLink, swipe actions (Delete red, Edit orange, Share blue for owners), context menu
- Collection add/edit: `AddEditCollectionView` — Form, Name TextField + emoji grid, members list (owners only), Mode enum (.add/.edit(CollectionModel))
- Share sheet: `ShareCollectionSheet` — email TextField, role Picker, Share button with loading spinner
- Entry list: `ContentView` — receives CollectionModel, grid/list toggle, inline search bar, select mode, permission-gated FAB and delete
- Entry add/edit: `AddEntryView` — sheet, handles create+edit via `editingEntryID: String?`
- Entry detail: `EntryDetailView` — receives myRole: CollectionRole, hides edit/delete for readers

### Navigation Stack
- `livlogiosApp` -> `CollectionsView` (owns NavigationStack) -> `ContentView` (pushed, receives CollectionModel) -> `EntryDetailView` (pushed, receives entryID String + myRole: CollectionRole)
- `AddEntryView` and `AddEditCollectionView` always presented as sheets, never pushed

### Key files (iOS)
- App entry: `/Users/avprokopev/Projects/livlogios-ag2/livlogios/App/livlogiosApp.swift`
- Models: `/Users/avprokopev/Projects/livlogios-ag2/livlogios/Models/Item.swift`
- Main screen: `/Users/avprokopev/Projects/livlogios-ag2/livlogios/Views/ContentView.swift`
- Add/Edit entry: `/Users/avprokopev/Projects/livlogios-ag2/livlogios/Views/AddEntryView.swift`
- Collections management: `/Users/avprokopev/Projects/livlogios-ag2/livlogios/Views/CollectionsView.swift`
- Entry detail: `/Users/avprokopev/Projects/livlogios-ag2/livlogios/Views/EntryDetailView.swift`
- State: AppState (auth only, no global data state)

### Key files (backend)
- Entrypoint: `/Users/avprokopev/Projects/livlogios-ag2/backend/cmd/server/main.go`
- Migrations: `/Users/avprokopev/Projects/livlogios-ag2/backend/migrations/`
- Collection handler: `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/handler/collection_handler.go`
- Entry handler: `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/handler/entry_handler.go`
- Collection service: `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/service/collection_service.go`
- Entry service: `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/service/entry_service.go`
- Collection repo: `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/repository/collection_repository.go`
- Entry repo: `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/repository/entry_repository.go`
- User repo: `/Users/avprokopev/Projects/livlogios-ag2/backend/internal/repository/user_repository.go`
