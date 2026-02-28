# Software Engineer Memory

## Topic Index

- [SwiftUI image sizing recipes](swiftui-recipes.md) — frame/scaledToFill/clipped patterns, grid card images
- [SwiftUI pitfalls](pitfalls.md) — type-checker timeout fix, Equatable for onChange

## SwiftUI conventions

**ForEach with multiple layouts (grid + list)** — when the same conditional interaction wrapper (e.g. `if isSelectMode { Button } else { NavigationLink }`) must be applied in multiple `ForEach` bodies, extract it into a `@ViewBuilder` helper function on the view. Never copy-paste the branch into each loop body — layouts drift and bugs must be fixed in N places.

**Generic `View` extensions belong in `Extensions/`** — utilities like `View.if(_:transform:)` must live in a dedicated file (e.g. `Extensions/View+Conditional.swift`), never inside a feature view file. Defining app-wide extensions in `ContentView.swift` or similar makes them invisible to other views and invites duplication.

**Always use `defer { isLoading = false }` in async load functions** — placing `isLoading = false` at the end of a function is fragile: if a `catch` clause adds a `return`, the flag sticks at `true` forever. Pattern to use in every view load function:
```swift
func loadData() async {
    isLoading = true
    defer { isLoading = false }
    do { ... }
    catch is CancellationError { return }
    catch let e as URLError where e.code == .cancelled { return }
    catch { errorMessage = ...; showError = true }
}
```

## Swift async/await patterns

**Cancellation detection in catch blocks** — `Task.isCancelled` is unreliable inside a `catch` block because the task may have already resumed by the time execution reaches `catch`. Instead:
```swift
} catch is CancellationError {
    return
} catch let urlError as URLError where urlError.code == .cancelled {
    return  // URLSession throws URLError(.cancelled), NOT CancellationError
} catch {
    // real error — show to user
}
```
Always handle both: Swift structured concurrency throws `CancellationError`; `URLSession` throws `URLError(.cancelled)`.

**safeAreaInset + NavigationStack** — `safeAreaInset` placed on a view *inside* a `NavigationStack` gets torn down when that view is pushed off the stack. If the inset content (e.g. a search bar) must persist at root level only, place `safeAreaInset` on the `NavigationStack` wrapper itself and gate visibility with `NavigationPath`:
```swift
@State private var path = NavigationPath()
NavigationStack(path: $path) { ... }
.safeAreaInset(edge: .bottom) {
    if path.isEmpty { searchBar }
}
```

## Go patterns

**mcp-go (mark3labs/mcp-go) SSE handler per-request pattern** — create a new `MCPServer` + `SSEServer` per HTTP request (not a singleton). This lets you inject per-user context (userID) into tool closures. Key API (v0.44.1):
```go
mcpSrv := server.NewMCPServer("name", "1.0.0")
tool := mcp.NewTool("tool-name", mcp.WithDescription("..."), mcp.WithString("param", mcp.Required(), mcp.Description("...")))
mcpSrv.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    args := req.Params.Arguments.(map[string]interface{})  // type-assert, not index directly
    val := args["param"].(string)
    return mcp.NewToolResultText(jsonStr), nil
})
sseServer := server.NewSSEServer(mcpSrv, server.WithBaseURL(baseURL))
sseServer.ServeHTTP(w, r)
```
- `req.Params.Arguments` is `interface{}` — must type-assert to `map[string]interface{}` before indexing
- Arrays in arguments: marshal raw value back to JSON, then unmarshal into typed slice
- Run `go mod tidy` after adding — mcp-go has transitive deps (invopop/jsonschema, yosida95/uritemplate)

**golangci-lint v2 config migration** — v2 requires `version: "2"` at top; `gofmt`/`goimports` move to `formatters:` section; `gosimple` merged into `staticcheck` and no longer exists as separate linter.

**Context key type safety** — `staticcheck SA1029`: never use `string` as context key type. Define a package-private type:
```go
type contextKey string
const UserIDContextKey contextKey = "userID"
ctx = context.WithValue(ctx, UserIDContextKey, value)
```
All readers must also use the same typed constant, not a raw string.

## Common pitfalls

**SwiftUI type-checker timeout** — "the compiler is unable to type-check this expression in reasonable time"
- Happens when `body` or a `@ViewBuilder` has too many modifiers/children in one expression chain
- Fix: extract into sub-`@ViewBuilder` computed vars (`scrollContent`, `formContent`, `toolbarContent`)
- Use `@ToolbarContentBuilder` for toolbar extraction
- Adding one more section/modifier to an already-complex view can push it over the limit

**`onChange(of:)` requires `Equatable`** — when observing a custom model type
- Add `Equatable` conformance to the model (`struct EntryTypeModel: Codable, Identifiable, Equatable`)
- Struct with only `Codable`-conforming stored properties can use synthesized `Equatable`

**pgx unique constraint violation detection** — pgx v5 wraps the PgError; check `err.Error()` for "23505" or constraint name
- Use `strings.Contains(err.Error(), "23505")` or the constraint name string
- Pattern: `if strings.Contains(msg, "23505") || strings.Contains(msg, "uq_my_constraint") { return ErrAlreadyX }`

**Transactional collection creation** — when creating a collection also needs a share row:
- Use `tx, err := r.db.Begin(ctx)` + `defer func() { _ = tx.Rollback(ctx) }()` + `tx.Commit(ctx)` in repo
- Insert collection, insert share row in same tx, return assembled struct with hardcoded role/count
- Note: `defer tx.Rollback(ctx)` (without `_ =`) triggers `errcheck` lint error — always use the func wrapper

**Xcode PBXFileSystemSynchronizedRootGroup** — project uses filesystem-synchronized groups; new Swift files placed in the correct folder are automatically included in the target without modifying `project.pbxproj`.
