# Software Engineer Memory

## Topic Index

- [SwiftUI image sizing recipes](swiftui-recipes.md) — frame/scaledToFill/clipped patterns, grid card images
- [SwiftUI pitfalls](pitfalls.md) — type-checker timeout fix, Equatable for onChange

## SwiftUI conventions

**ForEach with multiple layouts (grid + list)** — when the same conditional interaction wrapper (e.g. `if isSelectMode { Button } else { NavigationLink }`) must be applied in multiple `ForEach` bodies, extract it into a `@ViewBuilder` helper function on the view. Never copy-paste the branch into each loop body — layouts drift and bugs must be fixed in N places.

**Generic `View` extensions belong in `Extensions/`** — utilities like `View.if(_:transform:)` must live in a dedicated file (e.g. `Extensions/View+Conditional.swift`), never inside a feature view file. Defining app-wide extensions in `ContentView.swift` or similar makes them invisible to other views and invites duplication.

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

## Common pitfalls

**SwiftUI type-checker timeout** — "the compiler is unable to type-check this expression in reasonable time"
- Happens when `body` or a `@ViewBuilder` has too many modifiers/children in one expression chain
- Fix: extract into sub-`@ViewBuilder` computed vars (`scrollContent`, `formContent`, `toolbarContent`)
- Use `@ToolbarContentBuilder` for toolbar extraction
- Adding one more section/modifier to an already-complex view can push it over the limit

**`onChange(of:)` requires `Equatable`** — when observing a custom model type
- Add `Equatable` conformance to the model (`struct EntryTypeModel: Codable, Identifiable, Equatable`)
- Struct with only `Codable`-conforming stored properties can use synthesized `Equatable`
