# iOS App Architecture Notes

## Navigation Structure

- Root: `livlogiosApp.swift` — switches between `LoginView` and `ContentView` based on `AppState.isAuthenticated`
- `ContentView` owns a `NavigationStack` — the sole root navigation container for the authenticated experience
- Navigation to `EntryDetailView` is via `NavigationLink(destination: EntryDetailView(entryID:))`
- Sheets used for: `AddEntryView` (new/edit entry), `CollectionsView` (manage collections), `AISearchBottomSheet`, date/score pickers
- No TabView anywhere — single-screen architecture with sheet-based flows

## Data Models (`/livlogios/Models/Item.swift`)

- `CollectionModel`: id, name, icon (emoji string), createdAt, updatedAt — user-created folders
- `EntryModel`: id, collectionID (String?, optional FK), title, description, score (ScoreRating enum), date, additionalFields ([String:String]), images ([ImageMeta])
- `ScoreRating`: enum with rawValue Int (0=undecided, 1=bad, 2=okay, 3=great)
- `ImageMeta`: id (UUID string), isCover, position
- Entry types are NOT a separate enum or field — they are represented purely by which collection an entry belongs to
- An entry with collectionID == nil is uncategorized (no type/folder)

## ContentView State & Logic

- `@State private var items: [EntryModel]` — all entries loaded flat
- `@State private var collections: [CollectionModel]` — all collections
- `@State private var selectedCollection: CollectionModel?` — nil = "All" filter
- `filteredItems` computed var filters by `selectedCollection?.id == entry.collectionID` then by search text
- Both items and collections are loaded together via `loadData()` calling `CollectionService` and `EntryService` in parallel
- `EntryService.getEntries()` loads ALL entries (limit 50, no collection filter used in practice)
- `FilterBar` and `FilterPill` structs live in ContentView.swift
- `FilterBar` only shows collections that have at least one entry (collectionsWithItems filter)
- Grid/list layout controlled by `@AppStorage("viewMode")` enum `ViewMode`
- The `+` FAB button and search bar are in `safeAreaInset(edge: .bottom)`

## FilterBar (collection filter chips)

Defined inline in `ContentView.swift` (lines 372-455):
- Renders "All" pill + one pill per collection that has entries
- Selecting a pill sets `selectedCollection` binding
- `FilterPill` shows icon (emoji), name, count badge
- Uses `collectionsWithItems` computed property to hide empty collections

## AddEntryView Flow

- Opened as `.sheet` from ContentView FAB or from EntryDetailView edit button
- Takes optional `editingEntryID: String?` — nil = create, non-nil = edit
- On load: fetches EntryTypeModel list from TypeService, selects matching type for edit mode
- `typePickerSection`: horizontal scroll of `TypeButton` tiles — user picks entry type (Movie/Book/Game/etc.)
- `textSection`: plain TextField for title + TextEditor for description/notes (notes = summaryLine + description from AI)
- `imagesSection`: horizontal scroll of `ImageThumbnail` (up to 3 images)
- Score picker via bottom sheet (`ScoreSelectionSheet`), date picker via bottom sheet (`DatePickerSheet`)
- Save calls `EntryService.createEntry` or `EntryService.updateEntry`; disabled if `title.isEmpty`
- AI search via `AISearchBottomSheet` sheet — calls backend `/search` endpoint
- Only validation: Save button `.disabled(title.isEmpty || isSaving)` — no other validation

## AddEntryView State Variables

- `@State private var types: [EntryTypeModel]` — loaded from TypeService on appear
- `@State private var selectedType: EntryTypeModel?` — nil until user or AI picks a type
- `@State private var title: String` — plain text, required (save disabled if empty)
- `@State private var entryDescription: String` — multiline notes/description
- `@State private var score: ScoreRating = .undecided` — modified via ScoreSelectionSheet
- `@State private var date: Date = Date()` — modified via DatePickerSheet
- `@State private var selectedImages: [UIImage]` — up to 3 images; first = cover
- `@FocusState private var focus: FocusedField?` — controls keyboard toolbar vs bottom bar
- Boolean flags: `showAISearchSheet`, `showDatePicker`, `showScoreSheet`, `isLoading`, `isSaving`, `showError`

## EntryDetailView Layout Patterns

- 2-column grid for `additionalFields` using `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12)`
- Each cell: VStack with caption label + subheadline value, padded with `Color(.systemGray6)` background, `cornerRadius: 10`
- `metadataItems` sorted by fixed key order: Year, Genre, Author, Platform
- Full-width image gallery via `TabView` with `.page` style; gradient placeholder if no images

## AISearchService.EntryOption Fields

- `id: String`, `title: String`, `entryType: String` (free string: "movie","book","game","show","tv","music")
- `year: String?`, `genre: String?`, `author: String?`, `platform: String?` (optional metadata)
- `summaryLine: String` (brief tagline), `description: String` (longer text)
- `imageUrls: [String]` (direct image URLs), `downloadedImages: [Data]` (populated after download)
- `additionalFields: [String:String]` computed property aggregates non-nil optional fields
- Type icon via `suggestedIcon` computed property (switch on `entryType.lowercased()`)

## applyOptionToEntry Mapping

In AddEntryView, `applyOptionToEntry(_ option: EntryOption)` maps AI result to form:
- `title` = option.title (direct)
- `entryDescription` = option.summaryLine + "\n" + option.description (concatenated)
- `selectedType` matched by name from loaded types array (case-insensitive switch on option.entryType)
- Images downloaded async via `AISearchService.downloadImages(for:)`, then `selectedImages` updated on MainActor
- Note: `additionalFields` (Year, Genre, etc.) from EntryOption are NOT applied to the form — they are only displayed in search result cards

## CollectionsView

- Accessed via toolbar menu ("Manage Collections") in ContentView
- Shows a List of all collections with entry counts
- Supports add (sheet: `AddEditCollectionView(mode: .add)`), edit (sheet: `AddEditCollectionView(mode: .edit(collection))`), delete (with alert)
- Delete also deletes all entries in the collection (backend enforces this per alert message)
- Empty state shows "Create Default Collections" button which calls `/collections/default`
- On dismiss: ContentView calls `loadData()` to refresh

## Services

- All services are `actor` singletons (thread-safe, `static let shared`)
- `CollectionService`: CRUD on `/collections`, `/collections/default`, `/collections/:id`
- `EntryService`: CRUD on `/entries`, `/entries/:id`, `/entries/search`, `/images/:id`
- `BackendService`: core HTTP layer, handles auth token injection from Keychain, error handling (401, 429, 4xx)
- `AISearchService`: calls `/search` POST, downloads images from URLs

## AppState

- Only manages authentication state: `isAuthenticated`, `currentUser`, `isCheckingAuth`
- Does NOT hold collections or entries — those are local to each View's `@State`
- This means every sheet/screen must reload data independently
