# Code Reviewer Memory

## Recurring Patterns to Check

### Swift / iOS

- **[bug] `guard !Task.isCancelled` in catch block** — unreliable; the task may have already resumed by the time catch runs. Always pattern-match `catch is CancellationError` or `catch let e as URLError where e.code == .cancelled`.

- **[bug] Missing cancellation catch in async load helpers** — when a secondary async function (e.g. `loadMembers`) omits `catch is CancellationError`, a task cancellation (e.g. sheet dismissed mid-load) shows a spurious error alert. Apply the same pattern as `loadData`: `catch is CancellationError { return }` + `catch let urlError as URLError where urlError.code == .cancelled { return }` + move the loading flag reset into `defer`. Seen 2 times. NOTE: `loadData` in ContentView.swift now has both cancellation catches and `defer { isLoading = false }` — FIXED for this function. The pattern still needs checking in other load helpers.
  - Last seen: EntryDetailView.swift:269 (`isLoading = false` placed at end of function body instead of `defer`; if a future early-return is added the flag will stick)
  - Also seen: CollectionsView.swift:541 (`loadMembers` has no cancellation catch; `isLoadingMembers = false` not in defer)

- **[bug] `@State` seeded via `init` overwritten by `.task`/`.onAppear`** — initial value set in `init` is replaced on first appear when a network load unconditionally reassigns the same state. Either skip the load when state is already populated, or don't seed from `init`.

- **[bug] Singleton wrapped in `@StateObject` instead of `@ObservedObject`** — `@StateObject` implies ownership of the object lifetime. Singletons are externally owned; use `@ObservedObject`. Seen in livlogiosApp.swift (`connectionMonitor`), LoginView.swift, and SettingsView.swift — check every site that initialises a `.shared` singleton via a property wrapper.

- **[code-smell] `ForEach` with `id: \.offset`** — provides unstable identity; any insertion or deletion causes downstream items to be treated as new by SwiftUI, breaking animations and state. Always use a stable, unique id.

- **[code-smell] Generic `View` extensions defined in feature files** — utilities like `View.if(_:)`, `.glassOrMaterial`, `.shimmerLoading`, etc. belong in a dedicated `Extensions/` file, not in the file where they were first needed. Seen 6 times.
  - Last seen: ContentView.swift:752 (`shimmerLoading` and `ShimmerModifier` added again in ContentView.swift in this commit — still not moved to an Extensions file)

### Go / Backend

- **[bug] Sentinel errors wrapped with `fmt.Errorf` lose identity for `errors.Is`** — wrapping with `%w` preserves the chain, but when the wrapping is too deep or uses a plain `errors.New` copy, `errors.Is` fails in the handler and the wrong HTTP status is returned. Always use `%w` for sentinel errors and verify the handler's error switch covers all sentinels.

- **[bug] Service-layer validation errors surfacing as HTTP 500** — if a handler does not explicitly check a service error before the default 500 branch, input-validation rejections become server errors. Every service error type must be explicitly mapped in the handler.

- **[code-smell] Magic string role literals (`"owner"`, `"write"`, `"read"`)** — scattered across handler, service, and repository layers with no named constants. Changes to role names require grep-based search; a typo silently passes. Seen 3 times.
  - Last seen: entry_service.go:118,230,265,319 (`if role == "read"` checks inline across CreateEntry, UpdateEntry, and DeleteEntry service methods)
  - Also seen: collection_handler.go:350,413 and collection_repository.go:311,367 (UpdateShare and RemoveShare path; role strings appear inline in both handler validation and repo SQL guards)
  - Also seen: entry_repository.go:583 (`permission_level IN ('owner', 'write')` in DeleteEntriesByIDs SQL)

- **[code-smell] SQL `RETURNING` clause missing columns** — when a table gains a new column the existing `INSERT … RETURNING` queries often stay unchanged, causing the Go model field to always be zero/nil after insert without any error.

- **[bug] `AsyncSemaphore` signal not called on task cancellation** — when a `Task` is cancelled before or during a download, the `defer { Task { await semaphore.signal() } }` detached task may or may not run depending on cancellation timing, leaking a semaphore slot and eventually deadlocking the throttle. Use `withTaskCancellationHandler` or check `Task.isCancelled` and unconditionally signal in a cancellation handler. Fixed in session 2 by replacing the defer with explicit try/catch signal calls. Seen 1 time.
  - Last seen: ImageLoaderService.swift:78 (`defer { Task { await capturedSemaphore.signal() } }` inside a cancellable Task)

- **[bug] `GROUP BY` too broad in queries with `LEFT JOIN` to multi-row tables** — joining a table where a user can have multiple rows (e.g. `collection_shares`) and grouping by a column from that join produces duplicate result rows for the same entity.

- **[error-handling] Image metadata error silently discarded with `_`** — `GetEntryImageMetas` errors were swallowed in `CreateEntry`, `GetEntry`, and `UpdateEntry` handlers. FIXED in 013_add_image_hash branch: errors are now checked and logged with zap.Warn; response still proceeds with empty image list (intentional degraded-mode design). Seen 1 time.
  - Last seen (fixed): entry_handler.go:249,286,403

- **[bug] Migration uses `pgcrypto` extension function without verifying it is installed** — `013_add_image_hash.up.sql` calls `encode(sha256(image_data), 'hex')` which requires the `pgcrypto` extension. FIXED in same migration by prepending `CREATE EXTENSION IF NOT EXISTS pgcrypto;`. Seen 1 time.
  - Last seen (fixed): backend/migrations/013_add_image_hash.up.sql:1

- **[code-smell] `COALESCE(hash, '')` retained after column is made NOT NULL** — the `COALESCE` guard in `GetEntryImageMetas` and `GetImageMetasByEntryIDs` queries is now a no-op because the migration sets `hash NOT NULL`. FIXED in add-images-caching commit: both queries now select `hash` directly without COALESCE. Seen 1 time.
  - Last seen (fixed): entry_repository.go:391,454 (COALESCE removed; hash column selected directly)

- **[bug] `http.StatusText` misused for `Retry-After` header value** — `Retry-After` must be a decimal integer string (seconds). Passing an int through `http.StatusText` returns an empty string for any value that is not a recognised HTTP status code, silently dropping the header value. FIXED in implement-mcp commit. Seen 1 time.
  - Last seen (fixed): auth.go:208 (`strconv.Itoa(retryAfter)` now used correctly)

- **[error-handling] Inline response path bypasses shared `respondWithJSON`** — the rate-limit branch in `ResendVerificationCode` writes headers and encodes JSON directly, silently discarding the encode error with `_ = json.NewEncoder(w).Encode(resp)` while every other path in the same file now logs this via `respondWithJSON`. FIXED in implement-mcp commit. Seen 1 time.
  - Last seen (fixed): auth.go:222 (`respondWithJSON(h.log, w, ...)` now used in rate-limit branch)

- **[bug] Early return from `respondWithError` on context cancellation leaves response unwritten** — when `context.Canceled`/`context.DeadlineExceeded` is detected, returning without writing anything causes the Go `net/http` server to fall through and emit a default `200 OK` with an empty body. FIXED in implement-mcp commit: `respondWithJSON` is now called with `503`/`504` status and a proper body. Remaining concern: the guard fires only when the caller passed `http.StatusInternalServerError`, so 4xx callers wrapping a cancelled context still get their intended 4xx (acceptable behaviour). Seen 1 time.
  - Last seen (fixed): auth.go:283-291

- **[wrong-layer] `getUserIDFromContext` duplicated between handler and middleware packages** — `middleware.GetUserIDFromContext` already exists and is exported. The private copy in auth.go adds no value and risks drifting. FULLY FIXED in implement-mcp commit: `helpers.go` wrapper delegates to `middleware.GetUserIDFromContext` and all call sites (including auth.go:116,132) now use the package-private wrapper consistently. Seen 1 time.
  - Last seen (fixed): helpers.go:9–11 and auth.go:116,132
