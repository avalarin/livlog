# System Analyst Memory

Notes:
- Agent threads always have their cwd reset between bash calls, as a result please only use absolute file paths.
- In your final response always share relevant file names and code snippets. Any file paths you return in your response MUST be absolute. Do NOT use relative paths.
- For clear communication with the user the assistant MUST avoid using emojis.
- Do not use a colon before tool calls. Text like "Let me read the file:" followed by a read tool call should just be "Let me read the file." with a period.

Here is useful information about the environment you are running in:
<env>
Working directory: /Users/avprokopev/Projects/livlogios
Is directory a git repo: Yes
Platform: darwin
Shell: zsh
OS Version: Darwin 25.3.0
</env>
You are powered by the model named Sonnet 4.6. The exact model ID is claude-sonnet-4-6.

## Project Architecture

See `/Users/avprokopev/Projects/livlogios/.claude/agent-memory/system-analyst/architecture.md` for full details.

Key files (iOS):
- App entry: `/Users/avprokopev/Projects/livlogios/livlogios/App/livlogiosApp.swift`
- Models: `/Users/avprokopev/Projects/livlogios/livlogios/Models/Item.swift` (CollectionModel, EntryModel, ScoreRating, ImageMeta)
- Main screen: `/Users/avprokopev/Projects/livlogios/livlogios/Views/ContentView.swift`
- Add/Edit entry: `/Users/avprokopev/Projects/livlogios/livlogios/Views/AddEntryView.swift`
- Collections management: `/Users/avprokopev/Projects/livlogios/livlogios/Views/CollectionsView.swift`
- Entry detail: `/Users/avprokopev/Projects/livlogios/livlogios/Views/EntryDetailView.swift`
- Services: CollectionService, EntryService, BackendService, AISearchService, AuthService
- State: AppState (auth only, no global data state)

## Backend Architecture (Go)

See `/Users/avprokopev/Projects/livlogios/.claude/agent-memory/system-analyst/backend.md` for full details.

Key files (backend):
- Entrypoint: `/Users/avprokopev/Projects/livlogios/backend/cmd/server/main.go`
- Migrations: `/Users/avprokopev/Projects/livlogios/backend/migrations/` (NNN_name.up.sql / .down.sql, golang-migrate)
- Collection handler: `/Users/avprokopev/Projects/livlogios/backend/internal/handler/collection_handler.go`
- Entry handler: `/Users/avprokopev/Projects/livlogios/backend/internal/handler/entry_handler.go`
- Collection service: `/Users/avprokopev/Projects/livlogios/backend/internal/service/collection_service.go`
- Entry service: `/Users/avprokopev/Projects/livlogios/backend/internal/service/entry_service.go`
- Collection repo: `/Users/avprokopev/Projects/livlogios/backend/internal/repository/collection_repository.go`
- Entry repo: `/Users/avprokopev/Projects/livlogios/backend/internal/repository/entry_repository.go`
- User repo: `/Users/avprokopev/Projects/livlogios/backend/internal/repository/user_repository.go`

Entry types: currently NO type/kind field on entries. Category implied by collection name. Default collections: Movies/Books/Games created via POST /api/v1/collections/default.
