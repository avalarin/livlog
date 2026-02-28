# Code Reviewer Memory

## Recurring Patterns to Check

### Swift / iOS

- **[bug] `guard !Task.isCancelled` in catch block** — unreliable; the task may have already resumed by the time catch runs. Always pattern-match `catch is CancellationError` or `catch let e as URLError where e.code == .cancelled`.

- **[bug] Missing cancellation catch in async load helpers** — when a secondary async function (e.g. `loadMembers`) omits `catch is CancellationError`, a task cancellation (e.g. sheet dismissed mid-load) shows a spurious error alert. Apply the same pattern as `loadData`: `catch is CancellationError { return }` + `catch let urlError as URLError where urlError.code == .cancelled { return }` + move the loading flag reset into `defer`. Seen 1 time.
  - Last seen: CollectionsView.swift:541 (`loadMembers` has no cancellation catch; `isLoadingMembers = false` not in defer)

- **[bug] `@State` seeded via `init` overwritten by `.task`/`.onAppear`** — initial value set in `init` is replaced on first appear when a network load unconditionally reassigns the same state. Either skip the load when state is already populated, or don't seed from `init`.

- **[bug] Singleton wrapped in `@StateObject` instead of `@ObservedObject`** — `@StateObject` implies ownership of the object lifetime. Singletons are externally owned; use `@ObservedObject`.

- **[code-smell] `ForEach` with `id: \.offset`** — provides unstable identity; any insertion or deletion causes downstream items to be treated as new by SwiftUI, breaking animations and state. Always use a stable, unique id.

- **[code-smell] Generic `View` extensions defined in feature files** — utilities like `View.if(_:)`, `.glassOrMaterial`, `.shimmerLoading`, etc. belong in a dedicated `Extensions/` file, not in the file where they were first needed. Seen 3 times.
  - Last seen: ContentView.swift:750 (`shimmerLoading` and `ShimmerModifier` added/confirmed again in ContentView instead of an Extensions file)

### Go / Backend

- **[bug] Sentinel errors wrapped with `fmt.Errorf` lose identity for `errors.Is`** — wrapping with `%w` preserves the chain, but when the wrapping is too deep or uses a plain `errors.New` copy, `errors.Is` fails in the handler and the wrong HTTP status is returned. Always use `%w` for sentinel errors and verify the handler's error switch covers all sentinels.

- **[bug] Service-layer validation errors surfacing as HTTP 500** — if a handler does not explicitly check a service error before the default 500 branch, input-validation rejections become server errors. Every service error type must be explicitly mapped in the handler.

- **[code-smell] Magic string role literals (`"owner"`, `"write"`, `"read`)** — scattered across service and repository layers with no named constants. Changes to role names require grep-based search; a typo silently passes.

- **[code-smell] SQL `RETURNING` clause missing columns** — when a table gains a new column the existing `INSERT … RETURNING` queries often stay unchanged, causing the Go model field to always be zero/nil after insert without any error.

- **[bug] `AsyncSemaphore` signal not called on task cancellation** — when a `Task` is cancelled before or during a download, the `defer { Task { await semaphore.signal() } }` detached task may or may not run depending on cancellation timing, leaking a semaphore slot and eventually deadlocking the throttle. Use `withTaskCancellationHandler` or check `Task.isCancelled` and unconditionally signal in a cancellation handler. Fixed in session 2 by replacing the defer with explicit try/catch signal calls. Seen 1 time.
  - Last seen: ImageLoaderService.swift:78 (`defer { Task { await capturedSemaphore.signal() } }` inside a cancellable Task)

- **[bug] `GROUP BY` too broad in queries with `LEFT JOIN` to multi-row tables** — joining a table where a user can have multiple rows (e.g. `collection_shares`) and grouping by a column from that join produces duplicate result rows for the same entity.
