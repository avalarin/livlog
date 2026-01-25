# AGENT instructions

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**livlogios** is a SwiftUI-based iOS life logging app that helps users track and rate their experiences with movies, books, games, and other activities. The app features AI-powered smart entry with automatic metadata and image fetching via OpenRouter's Perplexity API.

## Agreements

### Definition of Done

**MANDATORY**: After completing ANY code changes, you MUST run the following checks in order:

1. **Linting**: `swiftlint` - Fix all errors and warnings
2. **Build**: `xcodebuild -scheme livlogios -configuration Debug build` - Ensure project compiles
3. **Tests**: `xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15'` - Verify all tests pass

**Do NOT consider a task complete until all three checks pass successfully.** If any check fails, fix the issues before proceeding or asking for further instructions.

## Build and Run

```bash
# Build the project
xcodebuild -scheme livlogios -configuration Debug build

# Run tests
xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15'

# Run unit tests only
xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:livlogiosTests

# Run UI tests only
xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:livlogiosUITests

# Clean build artifacts
xcodebuild clean -scheme livlogios
```

## Linting

The project uses SwiftLint for code quality enforcement. Configuration is in `.swiftlint.yml`.

```bash
# Run linting (must pass before committing)
swiftlint

# Auto-fix issues where possible
swiftlint --fix

# Lint specific directory
swiftlint lint --path livlogios/

# Strict mode (warnings as errors)
swiftlint --strict
```

**Common SwiftLint fixes:**
- Line length violations: Break long lines at 120 characters
- Force unwrapping: Replace `!` with safe unwrapping (`if let`, `guard let`, `??`)
- Trailing whitespace: Remove spaces at end of lines (or use `swiftlint --fix`)

**Installation** (if not installed):
```bash
brew install swiftlint
```

## Architecture

### Data Layer (SwiftData)

The app uses SwiftData for persistence with two main models:

- **Collection** (`Models/Item.swift`): Organizes entries into categories (Movies, Books, Games). Each collection has a name, emoji icon, and cascade-deletes its items.
- **Item** (`Models/Item.swift`): Individual log entries with title, description, score rating (bad/okay/great), date, and dynamic additional fields (Year, Genre, Author, Platform). Supports 1-3 images stored as Data.

The ModelContainer is initialized in `livlogiosApp.swift` with automatic creation of default collections on first launch.

### View Structure

**Main Views:**
- `ContentView.swift`: Home screen with filterable grid of entries, search, and collection filters. Contains debug utilities (test data fill, clear all data).
- `AddEntryView.swift`: Manual entry creation/editing with collection picker, dynamic fields (Year, Genre, Author, Platform), photo picker (up to 3 images), and score/date selectors.
- `SmartAddEntryView.swift`: AI-powered entry creation flow with two-phase UI (search → confirmation). Searches OpenRouter API, downloads images automatically, and pre-fills metadata.
- `EntryDetailView.swift`: Detail view for viewing/editing individual entries.
- `CollectionsView.swift`: Collection management interface.

**Key UI Patterns:**
- Two-column lazy grid layout for entry cards
- Horizontal scrolling filter pills for collections
- Material design with rounded corners, shadows, and blur effects
- Empty state guidance for new users

### Services

**OpenAIService** (`Services/OpenAIService.swift`):
- Uses OpenRouter API (https://openrouter.ai) with Perplexity Sonar model
- `searchOptions(for:)`: Searches for movies/books/games and returns structured JSON with title, type, year, genre, description, and image URLs
- `downloadImages(for:)`: Downloads up to 3 images with compression and validation
- Handles JSON response cleaning (removes markdown code blocks from LLM output)

**API Configuration:**
- Base URL: `https://openrouter.ai/api/v1/chat/completions`
- Model: `perplexity/sonar`
- API key is hardcoded in `OpenAIService.swift:12` (should be moved to environment variable or secure storage)

## Key Implementation Details

### Dynamic Fields Architecture

Items support flexible metadata via `additionalFields: [String: String]` dictionary. The UI provides predefined field inputs (Year, Genre, Author, Platform) that map to this dictionary, but the system supports arbitrary key-value pairs.

### Image Handling

- Images are stored as compressed JPEG Data (0.8 quality) in the Item model
- First image is designated as the "cover" and displayed prominently
- SmartAdd automatically downloads and compresses images from search results
- Manual entry uses PhotosPicker with 3-image limit

### Collection Matching

SmartAdd auto-selects collections by fuzzy matching the entry type (from API) against collection names. For example, `entryType: "movie"` matches `Collection.name: "Movies"`.

## Testing Utilities

ContentView includes debug menu (gear icon) with:
- **Fill with Test Data**: Creates sample entries across all collections
- **Clear All Data**: Removes all entries (with confirmation)

Access these via the toolbar gear button in the main view.

## Important Notes

- The OpenRouter API key in `OpenAIService.swift` should be secured before production
- SwiftData schema changes may require app reinstall during development
- Image storage uses Data directly in SwiftData; consider file references for production scale
- Default collections (Movies, Books, Games) are created on first launch only if database is empty

## Common Workflows

**Adding a new Collection type:**
1. Modify `Collection.defaultCollections` in `Models/Item.swift`
2. App will create new defaults only on fresh install; existing users need manual creation
3. Run quality checks: `swiftlint` → build → tests

**Modifying Item schema:**
1. Update `Item` model in `Models/Item.swift`
2. May require deleting app and reinstalling to reset SwiftData container
3. Consider migration strategy for production
4. Run quality checks: `swiftlint` → build → tests

**Changing AI search behavior:**
1. Modify the prompt in `OpenAIService.searchOptions(for:)` at line 76
2. Update `EntryOptionDTO` struct if response structure changes
3. Test JSON parsing with various query types
4. Run quality checks: `swiftlint` → build → tests

**After ANY code modification:**
1. `swiftlint` (fix all issues)
2. `xcodebuild -scheme livlogios -configuration Debug build`
3. `xcodebuild test -scheme livlogios -destination 'platform=iOS Simulator,name=iPhone 15'`
