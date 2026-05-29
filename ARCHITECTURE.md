# SQLiteo Architecture & Communication

## Overview

SQLiteo is a macOS app built with SwiftUI + AppKit. Each window gets its own
`DatabaseManager` and `SQLQueryStore` instances, injected into the view hierarchy
as `@EnvironmentObject`. A handful of singletons handle cross-window concerns
(window deduplication, recent files).

```
┌─────────────────────────────────────────────────────────────────┐
│                        SQLiteoApp (menu)                        │
│  @FocusedValue(\.databaseManager) → focused window's manager    │
│  @StateObject RecentFilesManager (menu list)                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │ openWindow / focusedValue
┌───────────────────────────▼─────────────────────────────────────┐
│                         RootView                                │
│  @State dbManager, queryStore (created fresh per window)        │
│  .environmentObject → ContentView                               │
│  .focusedSceneValue → SQLiteoApp                                │
│  .onOpenURL / .onAppear → dbManager.connect(to:)                │
│  .onDisappear → WindowManager.unregister                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │ environmentObject
┌───────────────────────────▼─────────────────────────────────────┐
│                         ContentView                              │
│  @EnvironmentObject dbManager, queryStore                       │
│                                                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────┐  │
│  │ SQL Editor  │  │ DataTableView│  │FilterView│  │StatusBar │  │
│  │ (CodeEditor)│  │(NSTableView) │  │(SwiftUI) │  │(SwiftUI) │  │
│  └──────┬──────┘  └──────┬───────┘  └────┬─────┘  └────┬─────┘  │
│         │                │               │             │         │
│         └──────────────┬───────────────────────────────┘         │
│                        ▼                                        │
│                  DatabaseManager                                 │
│                  SQLQueryStore                                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## 1. Per-Window State (no shared state between windows)

Each `WindowGroup(id: "main")` creates its own:

| Instance | Role | Created In |
|---|---|---|
| `DatabaseManager` | SQLite connection, schema, rows, edits, filters, sorts | `RootView` as `@State` |
| `SQLQueryStore` | Saved SQL queries for that database | `RootView` as `@State` |

Windows are isolated — there is no `NotificationCenter`, no shared `DatabaseManager`,
no inter-window messaging. Two windows on the same `.sqlite` file each hold their
own `DatabaseQueue` (separate GRDB connection).

---

## 2. Environment Object Flow

```
RootView
  ├── .environmentObject(dbManager)     → ContentView → all subviews
  └── .environmentObject(queryStore)    → ContentView → editor
```

All children access these via `@EnvironmentObject private var dbManager: DatabaseManager`
(and the same for `queryStore`). This is **the primary communication channel** —
views read `@Published` properties and call async methods.

---

## 3. Focused Value (Menu → Active Window)

```
RootView
  .focusedSceneValue(\.databaseManager, dbManager)

SQLiteoApp (menu commands)
  @FocusedValue(\.databaseManager) var dbManager
```

This is how menu items (Cmd+O, Cmd+R, etc.) reach the frontmost window's
`DatabaseManager`. The `RefreshCommand`, `OpenRecentMenu`, and `FileActions`
all receive the focused `dbManager` this way.

---

## 4. Cross-Window Coordination (Singletons)

### WindowManager

Tracks which file URLs are open in which windows. Used to prevent duplicates.

```
register  ← DatabaseManager.connect(to:)
unregister ← RootView.onDisappear
isOpen    ← FileActions, RootView.onOpenURL, OpenRecentMenu
bringToFront ← FileActions, RootView.onOpenURL, OpenRecentMenu
```

Each `RootView` generates a `UUID` and tags its `NSWindow.identifier` with it
(via `WindowIdentifierAccessor`, an `NSViewRepresentable`). `WindowManager`
maps `fileURL → uuidString`, and `bringToFront` finds the window by identifier.

### RecentFilesManager

Persists security-scoped bookmarks for the last 10 files.

```
add(url)     ← DatabaseManager.connect(to:)
recentURLs   ← OpenRecentMenu (menu display)
clear()      ← OpenRecentMenu "Clear Menu"
```

Shared via `@StateObject` in `SQLiteoApp` and injected as `@EnvironmentObject`
to `OpenRecentMenu`.

### DatabaseManager.pendingFileURL

A one-shot static variable used to pass a file URL from the opening window
to a newly created window's `RootView.onAppear`.

```
FileActions / OpenRecentMenu
  sets pendingFileURL → openWindow(id: "main")

New window's RootView.onAppear
  reads pendingFileURL → clears it → connects
```

---

## 5. DatabaseManager → View Data Flow

### Published Properties (read by views)

| Property | Read By |
|---|---|
| `rows`, `columns`, `columnTypes` | `DataTableView` — renders the grid |
| `totalRows`, `offset`, `limit` | `StatusBar` — pagination display & controls |
| `filters` | `FilterView` — bindings for column/operator/value |
| `isLoading` | `ContentView` — loading overlay, cancel button |
| `errorMessage` | `ContentView` — error bar overlay |
| `fileURL`, `fileSize`, `modificationDate` | ContentView sidebar — file metadata |
| `tableNames` | ContentView sidebar — table list, autocomplete |
| `dataUpdateCounter` | `DataTableView` — triggers `reloadData()` |
| `activeEdits`, `pendingChanges` | `DataTableView` — edit state highlighting |
| `highlightedRowID` | `DataTableView` — scroll & select after FK navigation |
| `foreignKeys` | `DataTableView` — FK button visibility per column |
| `tableDDL` | SchemaView tab |
| `sortColumn`, `sortAscending` | Set by `DataTableView` coordinator, used internally |

### Async Methods (called by views)

| Method | Called By |
|---|---|
| `connect(to:)` | RootView, FileActions |
| `selectTable(_:filter:)` | ContentView (on table selection change) |
| `runQuery(_:)` | ContentView (Run button, Cmd+Return) |
| `cancelQuery()` | ContentView, FilterView (Cancel during load) |
| `refreshDatabase()` | ContentView toolbar, SQLiteoApp (Cmd+R) |
| `applyFilter()` / `clearFilter()` | FilterView |
| `nextPage()` / `previousPage()` | StatusBar |
| `fetchRows(for:)` | DataTableView coordinator (after sort change) |
| `fetchSurroundingRows(for:value:)` | DataTableView coordinator (FK popover) |
| `navigateAndHighlight(...)` | DataTableView coordinator (FK navigation) |
| `fetchAllRowsForExport()` | ContentView (CSV/JSON export) |
| `columns(for:)` | ContentView (autocomplete) |
| `updateActiveEdit(rowID:column:value:)` | DataTableView (NSTextField delegate) |
| `applyEdits()` / `cancelEdits()` | EditControlBar (inline in DataTableView) |

---

## 6. SQLQueryStore → Editor Data Flow

```
ContentView
  selectedQuerySQL (computed Binding<String>)
    get → queryStore.selectedQuery?.sql ?? ""
    set → queryStore.updateSQL(id:, sql:)

  .onChange(of: queryStore.selectedQueryID)
    reloads editorSQL into local @State
```

The `SQLQueryStore`:
- Persists saved queries per-database (via `configure(for:)` based on `fileURL`)
- The editor `Binding` writes through to the store on every keystroke
- Autocomplete reads `queryStore.selectedQuery?.sql` to get current text

---

## 7. DataTableView (NSTableView → DatabaseManager)

The `DataTableRepresentable` (`NSViewRepresentable`) bridges AppKit's
`NSTableView` into SwiftUI.

### Update cycle (SwiftUI → AppKit)

```
dbManager.dataUpdateCounter += 1
  → DataTableRepresentable.updateNSView()
    → tableView.reloadData()
```

### Edit flow (AppKit → DatabaseManager)

```
NSTextFieldDelegate
  controlTextDidChange / controlTextDidEndEditing
    → dbManager.updateActiveEdit(rowID:, column:, value:)

EditControlBar "Apply"
  → dbManager.applyEdits()
    → (queues SQL UPDATE via GRDB, refreshes rows)

EditControlBar "Cancel"
  → dbManager.cancelEdits()
```

### Sort flow

```
NSTableView sortDescriptorsDidChange
  → sets dbManager.sortColumn / dbManager.sortAscending
  → await dbManager.fetchRows(for: tableName)
```

### FK popover flow

```
FK button click in cell
  → coordinator.fkButtonClicked(sender)
    → await dbManager.fetchSurroundingRows(for: fk, value: value)
    → creates NSPopover with FKPreviewPopover
    → onNavigate closure: await dbManager.navigateAndHighlight(...)
```

---

## 8. FilterView (SwiftUI Bindings → DatabaseManager)

All bindings read/write `dbManager.filters` directly:

```swift
// Column picker
Picker(selection: Binding(get: { dbManager.filters[i].column }, ...))

// "Apply" button
Task { await dbManager.applyFilter() }

// "Clear" button
Task { await dbManager.clearFilter() }
```

No intermediate state — changes to filter values are applied only when
the user presses "Apply".

---

## 9. FileActions (static methods → DatabaseManager + WindowManager)

All three entry points (`openFile`, `createNewFile`, `importCSV`) follow the
same pattern:

```
1. Show NSOpenPanel / NSSavePanel
2. User selects URL
3. Check WindowManager.shared.isOpen(fileURL:)
   ├── YES → WindowManager.shared.bringToFront(fileURL:) → return
   └── NO  → Check dbManager.fileURL == nil
              ├── YES → await dbManager.connect(to: url)
              └── NO  → DatabaseManager.pendingFileURL = url
                        openWindow(id: "main")
```

---

## 10. Window Lifecycle Summary

```
Window opens
  └─ RootView.onAppear
       ├─ If pendingFileURL: connect, clear pending
       └─ dbManager.windowIdentifier = windowID
  └─ WindowIdentifierAccessor sets NSWindow.identifier = windowID
  └─ dbManager.connect(to:) registers with WindowManager

Window is active
  └─ SQLiteoApp reads @FocusedValue(\.databaseManager)

Window closes
  └─ RootView.onDisappear
       └─ WindowManager.unregister(windowIdentifier: windowID)
       └─ dbManager deallocated (no explicit disconnect needed)

User re-opens same file
  └─ FileActions checks WindowManager.isOpen → YES
       └─ WindowManager.bringToFront → finds NSWindow by identifier
       └─ window.makeKeyAndOrderFront, NSApp.activate
```

---

## 11. Key Design Decisions

- **No `NotificationCenter`** — all view-to-manager communication is direct
  via method calls and `@Published` observation.
- **No `NSDocument`** — each window manages its own file lifecycle manually.
  This means no autosave, no version browser, no document conflict resolution.
- **Two-way Binding for filters** — FilterView binds directly to
  `dbManager.filters` rather than maintaining local copies.
- **Static `pendingFileURL`** — a pragmatic tradeoff. The static var means
  only one file can be "in transit" at a time; opening two files rapidly
  could lose the first. In practice, the user's sequential UI makes this
  race condition unlikely.
- **`dataUpdateCounter` as invalidation trigger** — because `NSTableView`
  lives outside SwiftUI's diffing, a monotonically increasing counter
  tells the `NSViewRepresentable` to reload.
