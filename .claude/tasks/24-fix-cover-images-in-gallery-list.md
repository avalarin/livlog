Cover images are not displayed in Gallery and List views

## Task

Files:
- @livlogios/Views/ContentView.swift
- @livlogios/Services/EntryService.swift
- @livlogios/Models/Item.swift

Expected behaviour:
- When viewing entries in Grid mode (gallery), each entry card should display its cover image if available
- When viewing entries in List mode, each entry row should display its cover image thumbnail if available
- Cover images should be loaded asynchronously and efficiently
- If an entry has no images, the current placeholder gradient with collection icon should be shown

Actual behaviour:
- In both Grid and List views, entry cards/rows only show placeholder gradients with collection icons
- Cover images are never loaded or displayed
- The functionality works correctly in `EntryDetailView`, where images are loaded via `EntryService.shared.getEntryImages(entryID:)` and displayed properly

How to reproduce:
1. Create an entry with images using AddEntryView or SmartAddEntry
2. Navigate to the main ContentView
3. Observe that the entry card (in Grid mode) or row (in List mode) shows only a gradient placeholder, not the actual cover image
4. Tap on the entry to open EntryDetailView - the images display correctly there

What to do:
- Modify `EntryCard` component in @livlogios/Views/ContentView.swift (lines 401-500) to:
  - Load cover image asynchronously on appear using `EntryService.shared.getEntryImages(entryID:)`
  - Filter images to get only the cover image (where `isCover == true` or `position == 0`)
  - Display the cover image in the card header area (currently lines 420-443)
  - Keep the gradient placeholder as fallback when no images exist or while loading
  - Handle loading and error states gracefully
  - Consider caching to avoid repeated network requests for the same image

- Modify `EntryListRow` component in @livlogios/Views/ContentView.swift (lines 502-580) to:
  - Load cover image asynchronously in the same way as EntryCard
  - Display the cover as a thumbnail in the icon area (currently lines 521-527)
  - Keep the collection icon as fallback when no cover exists

- Performance considerations:
  - Images should load asynchronously without blocking the UI
  - Consider implementing a simple in-memory cache to avoid repeated API calls for the same entry images
  - Loading should happen in `.task {}` or `.onAppear {}` lifecycle methods
  - Ensure proper cancellation when views disappear to avoid unnecessary work

- Reference implementation:
  - See @livlogios/Views/EntryDetailView.swift lines 229-258 for the correct pattern of loading images from backend
  - The loading logic converts base64 encoded data to UIImage: `Data(base64Encoded: imageModel.data)` then `UIImage(data: data)`

Important:
- Check Definition of Done from ./CLAUDE.md
