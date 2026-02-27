# Software Engineer Memory

## Topic Index

- [SwiftUI image sizing recipes](swiftui-recipes.md) — frame/scaledToFill/clipped patterns, grid card images
- [SwiftUI pitfalls](pitfalls.md) — type-checker timeout fix, Equatable for onChange

## Common pitfalls

**SwiftUI type-checker timeout** — "the compiler is unable to type-check this expression in reasonable time"
- Happens when `body` or a `@ViewBuilder` has too many modifiers/children in one expression chain
- Fix: extract into sub-`@ViewBuilder` computed vars (`scrollContent`, `formContent`, `toolbarContent`)
- Use `@ToolbarContentBuilder` for toolbar extraction
- Adding one more section/modifier to an already-complex view can push it over the limit

**`onChange(of:)` requires `Equatable`** — when observing a custom model type
- Add `Equatable` conformance to the model (`struct EntryTypeModel: Codable, Identifiable, Equatable`)
- Struct with only `Codable`-conforming stored properties can use synthesized `Equatable`
