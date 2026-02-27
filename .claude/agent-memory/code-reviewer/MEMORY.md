# Code Reviewer Memory

## Recurring Issues

- **[code-smell] Duplicated ISO8601 date decoding logic across Codable models** — seen 1 time
  - Last seen: Item.swift:47-78, 122-160, 287-319 (CollectionModel, EntryTypeModel, EntryModel all copy the same two-pass ISO8601 parse block)

- **[bug] Sheet presented with conditionally empty ViewBuilder body** — seen 1 time
  - Last seen: EntryDetailView.swift:197-206 (edit sheet body is empty when entry.collectionID is nil, resulting in a blank sheet with no feedback to the user)

- **[wrong-layer] Placeholder model constructed with fake data to satisfy API boundary** — seen 1 time
  - Last seen: EntryDetailView.swift:202 (CollectionModel(id: collectionID, name: "", icon: "📝") passed to AddEntryView because EntryDetailView only holds entryID, not the full CollectionModel)

- **[bug] Singleton wrapped in @StateObject instead of @ObservedObject** — seen 1 time
  - Last seen: livlogiosApp.swift:12 (ConnectionMonitor.shared used with @StateObject; should be @ObservedObject since the app does not own the singleton's lifetime)

- **[bug] Event-driven side effect only wired to onAppear, misses post-login state transitions** — seen 1 time
  - Last seen: livlogiosApp.swift:28-31 (connectionMonitor.startMonitoring() never called when user logs in after cold launch unauthenticated)

- **[bug] Task.isCancelled used to detect URLError(.cancelled) in catch block** — seen 1 time
  - Last seen: ContentView.swift:70 (guard !Task.isCancelled unreliable; task may have already resumed by the time catch executes; should pattern-match CancellationError or URLError.code == .cancelled instead)

- **[bug] .refreshable moved off ZStack onto ScrollView, leaving EmptyStateView without pull-to-refresh** — seen 1 time
  - Last seen: ContentView.swift:98-198 (when items.isEmpty && !isLoading the ScrollView branch is not shown, so user cannot pull-to-refresh after a failed initial load)

- **[bug] Concurrent loadData() calls not guarded — task and refreshable can run in parallel** — seen 1 time
  - Last seen: ContentView.swift:59-74 (.task and .refreshable both call loadData() with no in-flight guard; parallel writes to items/types are non-deterministic)

- **[code-smell] Duplicated ISO8601 date decoding logic across Codable models** — seen 2 times
  - Last seen: Item.swift (EntryTypeModel init(from:) lines 135-175 — identical two-pass ISO8601 parse block already flagged for CollectionModel and EntryModel)

- **[bug] isSaving never reset to false on successful save** — seen 1 time (FIXED)
  - Last seen: AddEntryView.swift:399-437 (saveEntry() calls dismiss() on success without setting isSaving = false; if dismiss is cancelled or sheet stays visible the button remains permanently disabled)
  - Fixed: isSaving = false added before dismiss() at line 433

- **[wrong-layer] Field-type validation silently skips when type lookup fails** — seen 1 time (FIXED)
  - Last seen: entry_service.go:51-55 (validateAdditionalFields returns nil when GetTypeByID errors, allowing any field value through if the type row is temporarily unavailable)
  - Fixed: error now propagated via fmt.Errorf wrapping

- **[code-smell] CreateType repository method omits fields column in RETURNING clause** — seen 1 time (FIXED)
  - Last seen: type_repository.go:133-153 (INSERT RETURNING does not include fields, so the returned EntryType.Fields is always nil/empty even though the column has a NOT NULL DEFAULT)
  - Fixed: fields added to RETURNING clause and scanned/unmarshalled

- **[bug] ErrTypeNotFound surfaces as HTTP 500 from validateAdditionalFields** — seen 1 time (FIXED)
  - Last seen: entry_service.go:51-54 + entry_handler.go:223-231 (GetTypeByID returns ErrTypeNotFound when type_id is invalid; error is wrapped by fmt.Errorf and not matched in handler's error switch, so client receives 500 instead of 400)
  - Fixed: errors.Is(err, repository.ErrTypeNotFound) added to 400 Bad Request check in CreateEntry and UpdateEntry handlers

- **[bug] Image delete closure captures stale index in ForEach(enumerated)** — seen 1 time (FIXED)
  - Last seen: AddEntryView.swift:274-286 (onDelete captures item.offset at render time; after first deletion the remaining items' offsets are stale, risking wrong element removal; id: \.offset compounds the issue by not providing stable identity)
  - Fixed: onDelete now uses firstIndex(where: { $0 === item.element }) for identity-based lookup

- **[error-handling] try? silently drops photo load errors with no user feedback** — seen 1 time (FIXED)
  - Last seen: AddEntryView.swift:368 (loadImages(from:) uses try? on loadTransferable; failures are silently skipped and selectedPhotos is cleared, giving the user no indication the load failed)
  - Fixed: do/catch now sets errorMessage and showError = true on failure

- **[error-handling] try? silently drops image load errors in edit-mode image loading** — seen 1 time (FIXED)
  - Last seen: AddEntryView.swift:393 (loadImages(imageIDs:) uses try? on EntryService.shared.getImage; load failures silently return nil and the image is dropped from the edit form with no feedback)
  - Fixed: do/catch now collects errors per-task and surfaces the first via errorMessage/showError

- **[bug] UIImage(data:) nil return silently drops image with no error surfaced** — seen 1 time
  - Last seen: AddEntryView.swift:396-398 (loadImages(imageIDs:) returns (index, nil, nil) when data arrives but UIImage init fails; slot is dropped silently at compactMap with no user feedback)

- **[code-smell] ForEach id: \.offset remains after stale-index bug fix** — seen 3 times
  - Last seen: AddEntryView.swift:280 (id: \.offset still used after onDelete was fixed to use identity-based lookup; unstable id causes SwiftUI to treat every downstream item as new on deletion and animates all of them; should use a stable id such as ObjectIdentifier)

- **[code-smell] Scan-then-unmarshal JSONB pattern duplicated across three repository methods** — seen 1 time
  - Last seen: type_repository.go (GetAllTypes:65-80, GetTypeByID:103-122, CreateType:139-156 — identical fieldsStr scan + json.Unmarshal block repeated three times)

- **[bug] @State seeded via init overwritten unconditionally by loadData() on first appear** — seen 1 time
  - Last seen: AddEntryView.swift:347 (initialTypes written to State(initialValue:) in init, but .task always calls loadData() which immediately reassigns types = try await TypeService.shared.getTypes(); preview shows error alert instead of seeded types after network failure)

- **[code-smell] additionalFields key matching relies on hardcoded English key strings** — seen 1 time
  - Last seen: AISearchService.swift:47-51 (additionalFields computed property maps year/genre/author/platform to hardcoded keys "Year", "Genre", "Author", "Platform"; if FieldDefinition.key ever differs from these strings, AI fields silently fail to populate; no compile-time safety)

- **[bug] Service-layer input-validation error surfaces as HTTP 500** — seen 2 times (FIXED — handler now validates and returns 400 before calling service)
  - Last seen: entry_handler.go:486-488 (DeleteEntries returns fmt.Errorf("too many entries: maximum 100") for >100 IDs; handler maps all errors from entryService.DeleteEntries to 500; client receives 500 instead of 400 for an invalid-input condition)

- **[code-smell] Validation duplicated in both handler and service after "move to handler" refactor** — seen 1 time
  - Last seen: entry_service.go:296-303 + entry_handler.go:470-478 (BulkDeleteEntries empty-list and 100-cap checks now exist in both layers; service checks are dead code and the two limits can drift independently)

- **[bug] selectedIDs not cleared on loadData() — stale IDs survive a data refresh** — seen 1 time (FIXED — selectedIDs.removeAll() added to loadData())
  - Last seen: ContentView.swift:89-100 / 62-77 (bulkDeleteEntries resets selectedIDs on success only; if loadData() is triggered via pull-to-refresh while in select mode, selectedIDs may contain IDs that no longer exist in items, resulting in a delete request for ghost entries)

- **[error-handling] bulkDeleteEntries does not exit select mode on error** — seen 1 time (FIXED — isSelectMode = false and selectedIDs.removeAll() added in catch block)
  - Last seen: ContentView.swift:96-99 (on network failure, isSelectMode stays true and selectedIDs stays populated; user sees an error alert but remains stuck in select mode with the previous selection intact)

- **[bug] bulkDeleteEntries filters items by live selectedIDs after await — stale capture hazard** — seen 1 time
  - Last seen: ContentView.swift:94 (ids captured before await, but items.removeAll reads selectedIDs live after await; concurrent UI interaction during network round-trip causes mismatch between sent IDs and locally removed items)

- **[code-smell] isSelectMode branch duplicated in both grid and list ForEach bodies** — seen 3 times
  - Last seen: ContentView.swift:138-202 (identical if isSelectMode / else NavigationLink structure repeated for EntryCard and EntryListRow; a shared @ViewBuilder helper would eliminate ~35 duplicated lines; pattern grown again in select-mode wiring)

- **[bug] bulkDeleteEntries items.removeAll reads selectedIDs live after await** — seen 2 times
  - Last seen: ContentView.swift:94 (ids captured before await via `let ids = Array(selectedIDs)`, but items.removeAll { ids.contains($0.id) } — this iteration is now correct; however the stale-capture pattern persists structurally and was flagged in the prior session too)

- **[code-smell] Validation duplication resolved — service layer dead code removed** — seen 1 time (FIXED)
  - Last seen: entry_service.go:295-303 (empty-list and 100-cap checks removed from DeleteEntries; validation now lives solely in entry_handler.go:470-478)

- **[bug] Select All / Deselect All operates on filteredItems, not items** — seen 2 times (PARTIALLY FIXED — set equality applied)
  - Last seen: ContentView.swift:267-274 (set equality fix correct; but Select All still scopes to filteredItems only, so toggling while a search is active then clearing the filter leaves a partial selection invisible to the user; the underlying scope issue remains unfixed)

- **[bug] Select All toggle condition compares counts not set membership** — seen 1 time (FIXED — set equality now used)
  - Last seen: ContentView.swift:274 (selectedIDs == Set(filteredItems.map { $0.id }) replaces count comparison; label and action are now consistent)

- **[code-smell] View.if(_:transform:) extension placed in ContentView.swift** — seen 3 times
  - Last seen: ContentView.swift:738-748 (generic View extension still defined in the feature file; used by both EntryCard and EntryListRow; should move to a dedicated Extensions/ file)

- **[bug] bulkDeleteEntries items.removeAll reads selectedIDs live after await — concurrent delete hazard** — seen 1 time
  - Last seen: ContentView.swift:90-103 (ids captured correctly before await, but if user taps more items during the network round-trip, selectedIDs.removeAll() in the catch path also clears IDs that were never sent; minor but structurally the same stale-capture pattern flagged previously)

- **[code-smell] isSelectMode branch duplicated in both grid and list ForEach bodies** — seen 4 times
  - Last seen: ContentView.swift:136-203 (if isSelectMode / else NavigationLink structure now fully duplicated for both grid and list; a shared @ViewBuilder helper would eliminate ~70 duplicated lines)

- **[bug] Task.isCancelled guard in catch block is unreliable** — seen 2 times (FIXED in SearchView)
  - Last seen: SearchView.swift (performSearch now pattern-matches CancellationError and URLError.cancelled — fix applied); ContentView.swift:66 still uses `guard !Task.isCancelled` in loadData() catch block — unfixed

- **[bug] searchTask not cancelled on view dismiss — in-flight request orphaned** — seen 1 time (FIXED)
  - Last seen: SearchView.swift:182 (searchTask?.cancel() now called before dismiss() in the cancel button action)

- **[bug] entryType always nil in SearchView results — wrong-layer data missing** — seen 1 time (FIXED)
  - Last seen: SearchView.swift:9,132 (types now received as a parameter and used in results list)

- **[code-smell] hasSearched flag redundant with results.isEmpty disambiguation** — seen 1 time (FIXED)
  - Last seen: SearchView.swift:18 (replaced by Optional<[EntryModel]>; nil = not yet searched, [] = no results)

- **[bug] Task.isCancelled guard in loadData() catch block still unreliable** — seen 3 times
  - Last seen: ContentView.swift:66 (guard !Task.isCancelled in catch block; same pattern flagged twice before for SearchView and ContentView; task may have resumed before catch runs; should pattern-match CancellationError)

- **[bug] stale results visible during debounce window in SearchView** — seen 1 time
  - Last seen: SearchView.swift:160-164 (new searchTask is created but results state is not reset; prior results stay on screen for the 300 ms debounce period plus network time, showing outdated data to the user)

- **[code-smell] glassOrMaterial extension defined in ContentView.swift, used cross-file** — seen 2 times
  - Last seen: SearchView.swift:182, 193 (now used in SearchView.swift as well; extension still lives only in ContentView; should move to a dedicated Extensions/ file)

- **[bug] onDelete parameter made optional without clear contract** — seen 1 time
  - Last seen: ContentView.swift:413, 551 (EntryCard and EntryListRow.onDelete now optional closure; always passed non-nil from ContentView but may be nil from SearchView; contextMenu condition guards on onDelete != nil but delete button logic still wraps in if let, allowing silent failure)

- **[bug] Task.isCancelled guard in loadData catch block fixed, but pattern may recur elsewhere** — seen 3 times (FIXED in ContentView and SearchView)
  - Last seen: ContentView.swift:66-69 (now correctly uses catch is CancellationError instead of guard !Task.isCancelled); SearchView.swift:205-208 (same fix applied); Pattern is correct but the recurring nature suggests need for codebase-wide standardization

- **[error-handling] Search error alert shown but no retry mechanism** — seen 1 time
  - Last seen: SearchView.swift:200-213 (performSearch catches errors and shows alert, but user must type again to retry; no inline retry button)

- **[bug] MCP SSE server and MCP server instantiated fresh on every HTTP request** — seen 1 time
  - Last seen: mcp_protocol_handler.go:65-219 (NewMCPServer + NewSSEServer called inside handleMCP on every request; for an SSE long-lived connection this creates a new server object each time, and for the /message and /sse sub-routes each hit creates a completely separate server instance with no shared session state; the SSE handshake and the subsequent /message POST will hit different server objects and the session will never be found)

- **[security] MCP unique_code bearer token has no rate limiting or brute-force protection** — seen 1 time
  - Last seen: mcp_protocol_handler.go:54-63 (GetUserIDByCode called on every request with no rate limiting; 64-char hex code is strong, but there is no lockout, no logging of failed attempts, and no IP-based throttle; any leaked code cannot be rotated without full Disable+Enable)

- **[code-smell] URL scheme inference duplicated between config.PublicURL() and service.buildMCPURL()** — seen 1 time
  - Last seen: config.go:85-90 + mcp_service.go:33-42 (identical port-presence heuristic to choose http vs https written twice; main.go passes cfg.Server.PublicHost to NewMCPService instead of calling cfg.Server.PublicURL(), so the config helper is dead for MCP; either pass the full URL from config or remove the helper)

- **[bug] add-entries MCP tool does not declare entries parameter in tool schema** — seen 1 time
  - Last seen: mcp_protocol_handler.go:103-109 (mcp.NewTool("add-entries") only registers collection_id via mcp.WithString; the required entries array is never declared with mcp.WithArray or equivalent; AI clients that introspect the schema will not know entries is accepted and may omit it)

- **[wrong-layer] MCPService holds raw publicHost string and re-implements URL construction** — seen 1 time (FIXED)
  - Last seen: mcp_service.go:22-42 (service layer owned the http/https scheme logic; now receives cfg.Server.PublicURL() from main.go — fix applied)

- **[bug] add-entries MCP tool score out-of-range silently clamped to 0 instead of returning an error** — seen 1 time
  - Last seen: mcp_protocol_handler.go:234-237 (score < 0 || score > 3 is silently reset to 0; entryService.CreateEntry will always receive a valid score and never return ErrInvalidScore; client receives a 200 with the clamped value, not a validation error)

- **[bug] down migration 011 leaves the DEFAULT '{}' in place after dropping NOT NULL** — seen 1 time (FIXED)
  - Last seen: migrations/011_fix_additional_fields_not_null.down.sql:1 (only drops NOT NULL constraint; the DEFAULT '{}'::jsonb set in the up migration remains, making the column NOT NULL-compatible again without the constraint; functionally harmless but the down does not fully reverse the up)
  - Fixed: DROP DEFAULT added as second statement in the down migration

- **[bug] add-entries MCP tool score out-of-range silently clamped to 0 instead of returning an error** — seen 1 time (FIXED)
  - Last seen: mcp_protocol_handler.go:234-237 (score < 0 || score > 3 is silently reset to 0; entryService.CreateEntry will always receive a valid score and never return ErrInvalidScore; client receives a 200 with the clamped value, not a validation error)
  - Fixed: now returns an error instead of clamping

- **[code-smell] get-entry-types tool uses local struct types (fieldResult, typeResult) duplicating what a shared DTO would provide** — seen 1 time
  - Last seen: mcp_protocol_handler.go:116-140 (anonymous inner structs defined inside the closure; identical structure to what the type repository already returns; a shared projection in the service or handler package would remove duplication)

- **[bug] find-entries fetches at most 100 entries from DB regardless of limit, then filters in-memory — silently truncates results** — seen 1 time
  - Last seen: mcp_protocol_handler.go:401 (GetEntriesByUserID called with hardcoded limit=100 and offset=0; name-filter applied client-side after; a user with >100 entries who searches by title may never see matching entries beyond page 1; the limit parameter applies to the already-filtered slice, but only up to the first 100 DB rows are ever considered)

- **[bug] edit-entry UpdateEntry called with collectionID nil when entry has no collection — may wipe collection assignment** — seen 1 time
  - Last seen: mcp_protocol_handler.go:502-509 (collectionID starts as current.CollectionID, which can be nil; if no collection_id arg is provided the nil is passed through to UpdateEntry; whether this is safe depends on repository semantics, but the nil-pass-through is subtle and not documented)

- **[code-smell] find-entries and add-entries both use hardcoded magic value 100 for DB fetch limit** — seen 1 time
  - Last seen: mcp_protocol_handler.go:401 (GetEntriesByUserID called with literal 100; same constant as maxAddEntriesBatch but not reused; a named constant would make the relationship explicit)

- **[bug] UpdateEntry collection role check only validates target collection, not current one** — seen 1 time (FIXED)
  - Last seen: entry_service.go:219-235 — existing.CollectionID now checked first; both current and target collection write-access verified; nil collectionID path now falls back to owner-only check

- **[bug] isUniqueViolation uses string-matching instead of typed pgx error** — seen 1 time (FIXED)
  - Last seen: collection_repository.go:393-395 — now uses errors.As(*pgconn.PgError) and compares Code == "23505"

- **[security] TOCTOU race in RemoveShare last-owner guard** — seen 1 time (FIXED)
  - Last seen: collection_repository.go:280-329 — last-owner guard now runs inside a single transaction with FOR UPDATE row lock

- **[security] BulkDelete uses creator-only auth while single Delete uses collection-role auth — inconsistent** — seen 1 time (FIXED)
  - Last seen: entry_repository.go:563-588 — DeleteEntriesByIDs now mirrors single-delete logic: allows creator OR owner/write role via EXISTS subquery

- **[security] Shared collection entries invisible to non-creator members** — seen 1 time (FIXED)
  - Last seen: entry_repository.go:120-133 — GetEntriesByUserID now uses collection_shares EXISTS subquery when collectionID provided; GetEntryByID backed by GetUserRole for non-creator access

- **[bug] ErrCollectionNotFound wrapped via fmt.Errorf loses sentinel** — seen 1 time (FIXED)
  - Last seen: entry_handler.go:424-426 — handler now explicitly checks errors.Is(err, repository.ErrCollectionNotFound) for DeleteEntry

- **[code-smell] Error compared by string value instead of sentinel** — seen 2 times (FIXED for CreateDefaultCollections)
  - Last seen: collection_handler.go now uses errors.Is(err, service.ErrAlreadyHasCollections)

- **[code-smell] Magic string role values** — seen 3 times
  - Last seen: backend/internal/service/collection_service.go:91, 153, 185 + entry_service.go:117, 230, 265, 318 — inline string literals "owner", "write", "read" still scattered with no named constants

- **[bug] Down migration too broad** — seen 2 times
  - Last seen: backend/migrations/010_collection_shares_membership.down.sql — `WHERE owner_id = shared_with_user_id AND permission_level = 'owner'` still deletes legitimately-shared owner rows that happen to be self-invited; the backfill pattern (owner_id = shared_with_user_id) is ambiguous for rows where an owner later re-added themselves with their own ID as both inviter and invitee

- **[bug] EntryDetailView edit sheet blank when entry has no collectionID** — seen 2 times
  - Last seen: EntryDetailView.swift:208-213 — if entry.collectionID is nil the sheet body has no content; user taps edit, sheet appears empty with no feedback

- **[wrong-layer] Placeholder CollectionModel constructed in view layer with fake data** — seen 2 times
  - Last seen: EntryDetailView.swift:210 — CollectionModel(id: collectionID, name: "", icon: "📝") passed to AddEntryView because EntryDetailView holds only entryID, not the full model

- **[bug] EntryDetailView default role is .owner in init** — seen 1 time
  - Last seen: EntryDetailView.swift:16 — init(entryID:myRole:) defaults myRole to .owner; callers that forget the argument silently grant full write access; default should be .read

- **[bug] GetUserRole returns ErrCollectionNotFound for non-member — misleading sentinel reuse** — seen 1 time
  - Last seen: collection_repository.go:202-204 — when a user has no row in collection_shares, GetUserRole returns ErrCollectionNotFound; callers in entry_service.go treat that as "collection doesn't exist" and surface HTTP 404/403 correctly, but the semantic is "not a member", not "not found"; DeleteEntry wraps it as "invalid collection: %w" which the handler maps to 403, masking the real reason

- **[bug] GetCollectionsByUserID GROUP BY duplicates rows for user who is both creator and sharee from two different inviters** — seen 1 time
  - Last seen: collection_repository.go:119-120 — GROUP BY includes cs.owner_id, u_inviter.display_name, u_inviter.email; a user can appear in collection_shares twice (owner self-row + re-added by another owner), producing two rows for the same collection in the list

- **[bug] Edit sheet blank when entry.collectionID is nil — existing recurring issue not fixed** — seen 3 times
  - Last seen: EntryDetailView.swift:208-213 — sheet body is empty when entry.collectionID is nil; user taps edit and sees a blank sheet

- **[wrong-layer] Placeholder CollectionModel with fake data constructed in view layer** — seen 3 times
  - Last seen: EntryDetailView.swift:210 — CollectionModel(id: collectionID, name: "", icon: "📝") passed to AddEntryView

- **[code-smell] Magic string role values** — seen 4 times
  - Last seen: collection_service.go:91, 153, 185 + collection_handler.go:342 — inline string literals "owner", "write", "read" still scattered with no named constants
