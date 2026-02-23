Refactor the main screen (ContentView) toolbar and navigation controls to simplify the UI: remove the defunct SmartAdd menu item, convert the + button into a floating action button, move the view toggle into the settings menu, relocate the settings button to the top-right, and update its icon to an ellipsis.

## Functional requirements:
- Remove the "Quick Add (AI)" menu item and the associated dead state (`showingSmartAdd`) from ContentView
- The + button must become a floating action button positioned at the bottom-right of the screen, visible on top of the scroll content
- The floating + button must directly trigger `showingAddEntry = true` (no menu — single action)
- On the empty state screen, the existing "Add First Entry" button must remain and still trigger `showingAddEntry = true`
- The view toggle button (grid/list) must be removed from the leading toolbar and added as the first item inside the settings Menu, above "Manage Collections"
- The settings Menu button must be moved from the leading toolbar to the trailing toolbar (`ToolbarItem(placement: .primaryAction)` or `.navigationBarTrailing`)
- The settings button icon must change from `"gear"` to `"ellipsis"` (SF Symbol for three horizontal dots)

## Non-functional requirements:
- The floating button must not obscure the last list/grid item; the existing `padding(.bottom, 100)` on the scroll content is already sufficient — verify it remains in place
- The floating button must respect the safe area and sit above the home indicator on all iPhone sizes
- The animation for view mode toggle (`withAnimation(.spring(response: 0.3))`) must be preserved when triggered from the menu item
- No new files should be created; all changes are confined to `ContentView.swift`

## Acceptance criteria:
- The toolbar contains only one button in the top-right: the ellipsis settings button
- Tapping the ellipsis button opens a menu with: "Grid / List" toggle item at the top, a Divider, "Manage Collections", another Divider, debug items
- No "Quick Add (AI)" or "Manual Add" menu items exist anywhere in the view
- A floating circular + button is visible in the bottom-right corner when entries exist
- Tapping the floating + button opens AddEntryView sheet
- The empty state view still shows the "Add First Entry" button and opens AddEntryView
- `showingSmartAdd` state variable is deleted
- Build passes with no SwiftLint errors

## Step-by-step solution

### Step 1: Remove SmartAdd dead code
Files:
- `/Users/avprokopev/Projects/livlogios/livlogios/Views/ContentView.swift`

Changes to implement:
- Delete `@State private var showingSmartAdd = false` (line 19)
- Delete the entire `ToolbarItem(placement: .primaryAction)` block (lines 201–219) which contains the Menu with "Quick Add (AI)" and "Manual Add" buttons

### Step 2: Restructure the leading toolbar — remove view toggle, update settings icon and placement
Files:
- `/Users/avprokopev/Projects/livlogios/livlogios/Views/ContentView.swift`

Changes to implement:
- Delete the entire `ToolbarItem(placement: .navigationBarLeading)` block (lines 161–199) containing the `HStack` with the grid/list toggle button and the gear Menu
- Add a new `ToolbarItem(placement: .primaryAction)` (or `.navigationBarTrailing`) containing only the settings Menu button
- Set the new menu button's label icon to `Image(systemName: "ellipsis")` with `.symbolRenderingMode(.hierarchical)`
- Inside the new menu, add a toggle action as the first item before the existing "Manage Collections" entry:
  - Button label: `viewMode == .grid ? "Switch to List" : "Switch to Grid"` with `systemImage: viewMode == .grid ? "list.bullet" : "square.grid.2x2"`
  - Action: `withAnimation(.spring(response: 0.3)) { viewMode = viewMode == .grid ? .list : .grid }`
- Place a `Divider()` between the view toggle item and the "Manage Collections" item

### Step 3: Add floating + button overlay
Files:
- `/Users/avprokopev/Projects/livlogios/livlogios/Views/ContentView.swift`

Changes to implement:
- Inside the outer `ZStack` in `body`, add a new `VStack` / `HStack` overlay that is always anchored to the bottom-right
- The overlay structure: `VStack { Spacer(); HStack { Spacer(); floatingButton } .padding(.trailing, 20) .padding(.bottom, 24) }`
- The floating button: a `Button { showingAddEntry = true }` with label `Image(systemName: "plus")` styled as a filled circle — e.g., `font(.title2)`, `foregroundStyle(.white)`, `frame(width: 56, height: 56)`, `background(Color.accentColor)`, `clipShape(Circle())`, `shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)`
- This overlay must be placed after (on top of) the existing gradient background and the `if items.isEmpty` / `else` branch, so it is visible in both states
- Alternatively, if the floating button should only show when there are entries (empty state has its own CTA), place it inside the `else` branch of `if items.isEmpty`

### Step 4: Verify scroll content bottom padding
Files:
- `/Users/avprokopev/Projects/livlogios/livlogios/Views/ContentView.swift`

Changes to implement:
- Confirm `.padding(.bottom, 100)` on the `LazyVStack` (line 155) is still present after the edits; if it was removed during Step 3 refactoring, restore it so the last item is not hidden behind the floating button

## Test automation plan:
- Verify existing unit tests in `livlogiosTests/livlogiosTests.swift` still compile and pass after the state variable removal
- Manual UI test: launch app with no entries — confirm "Add First Entry" button is visible and opens AddEntryView
- Manual UI test: launch app with entries — confirm floating + button is visible and opens AddEntryView
- Manual UI test: tap ellipsis button — confirm menu contains view toggle as first item, followed by Divider, then "Manage Collections"
- Manual UI test: tap view toggle item in menu — confirm grid/list switch animates correctly
- Manual UI test: confirm no "Quick Add (AI)" button or SmartAdd sheet appears anywhere
- SwiftLint: run `swiftlint` and confirm zero errors/warnings
