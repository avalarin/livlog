# SwiftUI Recipes

## Image Sizing in LazyVGrid Cards

### Problem
`scaledToFill()` inside a grid card VStack causes the image to "push" the card wider than the column, breaking the grid layout.

### Root Cause
SwiftUI calculates the image's preferred size from its native aspect ratio before the parent width is resolved. Without `maxWidth: .infinity`, the image proposes its own width to the parent.

### Solution: two separate `.frame()` calls
```swift
Image(uiImage: photo)
    .resizable()
    .scaledToFill()
    .frame(maxWidth: .infinity)  // adapts to column width — does NOT push it
    .frame(height: 140)          // fix height separately
    .clipped()                   // always after the final frame
```

**Why two frames?** `.frame(maxWidth: .infinity)` tells the image to take whatever width the parent offers. `.frame(height: 140)` then constrains height. This order prevents the image from dictating its own width.

### Anti-patterns
```swift
// ❌ Fixed CGFloat.infinity — not "flexible", it's a huge fixed number
.frame(width: .infinity, height: 140)

// ❌ clipped before frame — clips to wrong bounds
.clipped()
.frame(height: 140)

// ❌ scaledToFill without clipped — image renders over neighboring views
.scaledToFill()
.frame(maxWidth: .infinity)
// missing .clipped()
```

### Card container must also declare maxWidth
```swift
VStack { ... }
    .frame(maxWidth: .infinity)   // prevent VStack from shrinking to content
    .background(Color(.systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 16))
```

### Modifier order mental model
```
1. .resizable()         → opt-in to resizing
2. .scaledToFill/Fit()  → set scaling rule
3. .frame(maxWidth:)    → constrain width (adapt to parent)
4. .frame(height:)      → constrain height
5. .clipped()           → clip overflow to final frame bounds
```

---

## Image Cropping Alignment (portrait vs landscape)

To show a specific part of a `scaledToFill` image, control the ZStack alignment:

```swift
// Portrait image → show top (align overflow to bottom)
ZStack(alignment: .top) {
    Image(uiImage: photo)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity)
}
.frame(height: 140)
.clipped()

// Landscape image → show center (default)
ZStack(alignment: .center) { ... }
```

Dynamic variant using image dimensions:
```swift
ZStack(alignment: photo.size.width > photo.size.height ? .center : .top) {
    Image(uiImage: photo)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity)
}
.frame(height: 140)
.clipped()
```

---

## Adaptive Grid Column Count (iPhone + iPad)

```swift
@Environment(\.horizontalSizeClass) private var horizontalSizeClass
@Environment(\.verticalSizeClass) private var verticalSizeClass
@State private var containerWidth: CGFloat = 0

private func columnCount() -> Int {
    if horizontalSizeClass == .compact {
        return verticalSizeClass == .compact ? 3 : 2  // iPhone landscape : portrait
    }
    return containerWidth > 1050 ? 4 : 3  // iPad landscape : portrait
}

private var gridColumns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount())
}
```

Capture container width without breaking layout — attach to scroll content:
```swift
LazyVStack { ... }
    .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
    } action: { width in
        containerWidth = width
    }
```

> `onGeometryChange` requires iOS 17+. For iOS 16: use `.background(GeometryReader { ... })` with a PreferenceKey.

iPad width thresholds (empirical):
- iPad mini / Air / Pro 11" portrait: 744–834pt → threshold 1050pt → 3 columns ✓
- iPad Pro 13" portrait: 1024pt → 3 columns ✓
- All iPads landscape: 1133–1366pt → 4 columns ✓
