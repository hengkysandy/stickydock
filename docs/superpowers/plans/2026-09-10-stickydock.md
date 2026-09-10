# StickyDock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS app that docks sticky notes to the screen edge and mirrors them into an Apple Notes folder, so the same notes appear on the iPhone and on other Macs with no extra install.

**Architecture:** Apple Notes is the sync transport, driven through JXA. A local SQLite cache holds app state and makes the UI fast. A `SyncEngine` decides push/pull/conflict purely from content hashes and talks only to protocols, so every sync rule is unit-testable against a fake bridge. Colors live in a sidecar JSON in iCloud Drive because Notes has no custom metadata.

**Tech Stack:** Swift 6.3, SwiftUI + AppKit (`NSPanel`), GRDB (SQLite), Swift Testing, JXA via `osascript`, SPM with a hand-rolled `.app` bundler.

**Spec:** `docs/superpowers/specs/2026-09-10-stickydock-design.md`

## Global Constraints

- macOS 14+ deployment target. Built and run on macOS 26.6.2, Swift 6.3.3.
- Swift strict concurrency. No `@unchecked Sendable` without a comment saying why.
- Bundle id `com.hengkysandy.stickydock`. Never change it: TCC grants are keyed to it.
- Sign with `Apple Development: <your Apple ID> (<team>)`. Never ad-hoc.
- `LSUIElement = true`. No Dock icon.
- Not sandboxed. `NSAppleEventsUsageDescription` required in Info.plist.
- Address Apple Notes by `id`, never by `name`.
- Set the Notes `body` property only, never `name`.
- Write HTML to `body`, read text from `plaintext`. The `body` getter corrupts entities.
- Never concatenate note text into a JXA script. Pass JSON on stdin.
- Skip notes where `passwordProtected` or `shared` is true.
- No network code. No analytics.
- Personal project: GitHub owner is `hengkysandy`, never `hengky-nexa` or `arthanexa`.

---

### Task 1: Project scaffold that launches

**Files:**
- Create: `StickyDock/Package.swift`
- Create: `StickyDock/Sources/StickyDock/main.swift`
- Create: `StickyDock/Sources/StickyDock/AppDelegate.swift`
- Create: `StickyDock/Resources/Info.plist`
- Create: `StickyDock/scripts/build.sh`
- Create: `StickyDock/scripts/run.sh`
- Create: `StickyDock/.gitignore`

**Interfaces:**
- Consumes: nothing.
- Produces: a `StickyDock.app` bundle in `StickyDock/build/`, signed and launchable, showing a menu bar item. `scripts/build.sh` is the single build entry point for every later task.

- [ ] **Step 1:** Write `Package.swift` with an executable target `StickyDock`, a library target `StickyDockCore` (all logic, so tests can import it), and a test target `StickyDockCoreTests`. Add GRDB as the only dependency.
- [ ] **Step 2:** Write `Info.plist` with `CFBundleIdentifier=com.hengkysandy.stickydock`, `LSUIElement=true`, `NSAppleEventsUsageDescription`, `LSMinimumSystemVersion=14.0`.
- [ ] **Step 3:** Write `build.sh`: `swift build -c release`, assemble `build/StickyDock.app/Contents/{MacOS,Resources}`, copy the binary and Info.plist, then `codesign --force --options runtime --sign "Apple Development: <your Apple ID> (<team>)"`.
- [ ] **Step 4:** Write a minimal `AppDelegate` that creates an `NSStatusItem` with a title, and a Quit menu item.
- [ ] **Step 5:** Run `scripts/build.sh`. Expected: exit 0, `codesign -dv` reports the Apple Development identity.
- [ ] **Step 6:** Run `scripts/run.sh`. Expected: menu bar item appears, no Dock icon.
- [ ] **Step 7:** `git init`, commit.

---

### Task 2: Text and HTML conversion

**Files:**
- Create: `StickyDock/Sources/StickyDockCore/NoteHTML.swift`
- Test: `StickyDock/Tests/StickyDockCoreTests/NoteHTMLTests.swift`

**Interfaces:**
- Produces: `enum NoteHTML { static func toHTML(_ text: String) -> String; static func title(of text: String) -> String }`

- [ ] **Step 1: Write the failing tests.**

```swift
import Testing
@testable import StickyDockCore

@Test func plainLinesBecomeDivs() {
    #expect(NoteHTML.toHTML("one\ntwo") == "<div>one</div><div>two</div>")
}

@Test func blankLineBecomesBrDiv() {
    #expect(NoteHTML.toHTML("a\n\nb") == "<div>a</div><div><br></div><div>b</div>")
}

@Test func entitiesAreEscaped() {
    #expect(NoteHTML.toHTML("a & b < c > d") == "<div>a &amp; b &lt; c &gt; d</div>")
}

@Test func emptyTextIsOneEmptyDiv() {
    #expect(NoteHTML.toHTML("") == "<div><br></div>")
}

@Test func unicodeSurvives() {
    #expect(NoteHTML.toHTML("héllo 🎉") == "<div>héllo 🎉</div>")
}

@Test func titleIsFirstNonEmptyLineTrimmed() {
    #expect(NoteHTML.title(of: "\n  Shopping list  \nmilk") == "Shopping list")
}

@Test func titleOfEmptyTextIsUntitled() {
    #expect(NoteHTML.title(of: "   \n  ") == "Untitled")
}

@Test func titleIsTruncatedAtSixtyCharacters() {
    let long = String(repeating: "x", count: 100)
    #expect(NoteHTML.title(of: long).count == 60)
}
```

- [ ] **Step 2:** Run `swift test --filter NoteHTMLTests`. Expected: FAIL, no such type `NoteHTML`.
- [ ] **Step 3:** Implement `NoteHTML`. Escape `&` first, then `<` and `>`. Split on `\n` keeping empty subsequences.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit `test: text to HTML conversion` + `feat: NoteHTML`.

---

### Task 3: NoteStore, the local SQLite cache

**Files:**
- Create: `StickyDock/Sources/StickyDockCore/Note.swift`
- Create: `StickyDock/Sources/StickyDockCore/NoteStore.swift`
- Test: `StickyDock/Tests/StickyDockCoreTests/NoteStoreTests.swift`

**Interfaces:**
- Consumes: `NoteHTML.title(of:)`.
- Produces:
```swift
struct Note: Codable, Equatable, Identifiable, Sendable {
    var id: String            // local UUID string
    var notesId: String?      // Apple Notes x-coredata id
    var text: String
    var color: NoteColor
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var sortIndex: Int
    var syncedHash: String?   // hash as of last successful sync
    var title: String { NoteHTML.title(of: text) }
}
enum NoteColor: String, Codable, CaseIterable, Sendable {
    case yellow, pink, blue, green, purple, grey
}
protocol NoteStoring: Sendable {
    func allActive() throws -> [Note]
    func all() throws -> [Note]
    func find(id: String) throws -> Note?
    func find(notesId: String) throws -> Note?
    func upsert(_ note: Note) throws
    func delete(id: String) throws
    func archive(id: String, at: Date) throws
    func search(_ query: String) throws -> [Note]
}
final class NoteStore: NoteStoring { init(path: String) throws }
```

- [ ] **Step 1: Write the failing tests.** Each test builds a `NoteStore` on a fresh temp file path and deletes it afterwards.

```swift
@Test func upsertThenFindReturnsSameNote()
@Test func upsertTwiceUpdatesRatherThanDuplicates()
@Test func allActiveExcludesArchived()
@Test func allIncludesArchived()
@Test func findByNotesIdWorks()
@Test func findByNotesIdReturnsNilWhenUnset()
@Test func searchMatchesBodyCaseInsensitively()
@Test func searchMatchesArchivedNotesToo()
@Test func deleteRemovesTheRow()
@Test func allActiveIsOrderedBySortIndexThenUpdatedAt()
@Test func storeSurvivesReopeningTheSameFile()
```

- [ ] **Step 2:** Run `swift test --filter NoteStoreTests`. Expected: FAIL.
- [ ] **Step 3:** Implement with a GRDB `DatabaseQueue` and a `DatabaseMigrator` registering migration `v1` that creates the `note` table with an index on `notesId` and on `archivedAt`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit.

---

### Task 4: NotesBridge, the JXA bridge to Apple Notes

**Files:**
- Create: `StickyDock/Sources/StickyDockCore/NotesBridge.swift`
- Create: `StickyDock/Sources/StickyDockCore/Resources/notes_bridge.js`
- Test: `StickyDock/Tests/StickyDockCoreTests/NotesBridgeLiveTests.swift`

**Interfaces:**
- Produces:
```swift
struct RemoteNote: Codable, Equatable, Sendable {
    var id: String; var title: String; var text: String; var modifiedAt: Date
}
enum NotesBridgeError: Error, Equatable {
    case notAuthorised, notesNotRunning, scriptFailed(String), badResponse(String)
}
protocol NotesBridging: Sendable {
    func ensureFolder(account: String, folder: String) throws
    func list(account: String, folder: String) throws -> [RemoteNote]
    func create(account: String, folder: String, text: String) throws -> RemoteNote
    func update(id: String, text: String) throws -> RemoteNote
    func delete(id: String) throws
}
final class NotesBridge: NotesBridging { init(scriptURL: URL) }
```

- [ ] **Step 1:** Write `notes_bridge.js`. It reads one JSON object from `$.NSProcessInfo` arguments, switches on `op`, and prints one JSON object. It never interpolates text into AppleScript. It filters out notes where `passwordProtected()` or `shared()` is true. It reads `plaintext()`, never `body()`. It writes `body` only, never `name`.
- [ ] **Step 2:** Write `NotesBridge.swift`. It runs `osascript -l JavaScript <script> <base64-json>`, decodes the JSON reply, and maps exit code 1 with `-1743` in stderr to `.notAuthorised`.
- [ ] **Step 3: Write the live integration test**, guarded by `STICKYDOCK_LIVE_NOTES=1` so a normal `swift test` never touches the real Notes.app. It creates folder `StickyDockTest`, runs create → list → update → delete, asserts the text roundtrips including `&`, `<`, `>` and a blank line, and removes what it made.
- [ ] **Step 4:** Run `STICKYDOCK_LIVE_NOTES=1 swift test --filter NotesBridgeLive`. Expected: PASS against the real app.
- [ ] **Step 5:** Run plain `swift test`. Expected: the live test is skipped.
- [ ] **Step 6:** Commit.

---

### Task 5: SidecarStore, colors in iCloud Drive

**Files:**
- Create: `StickyDock/Sources/StickyDockCore/SidecarStore.swift`
- Test: `StickyDock/Tests/StickyDockCoreTests/SidecarStoreTests.swift`

**Interfaces:**
- Produces:
```swift
struct SidecarEntry: Codable, Equatable, Sendable {
    var color: NoteColor; var sortIndex: Int; var updatedAt: Date
}
struct Sidecar: Codable, Equatable, Sendable {
    var version: Int; var entries: [String: SidecarEntry]   // keyed by notesId
}
protocol SidecarStoring: Sendable {
    func load() -> Sidecar
    func save(_ sidecar: Sidecar)
    var isAvailable: Bool { get }
}
final class SidecarStore: SidecarStoring {
    init(directory: URL)
    static func iCloudDirectory() -> URL?
    static func merge(_ local: Sidecar, _ remote: Sidecar) -> Sidecar
}
```

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func loadOfMissingFileReturnsEmptySidecar()
@Test func loadOfCorruptJSONReturnsEmptySidecarAndDoesNotThrow()
@Test func saveThenLoadRoundTrips()
@Test func mergeKeepsTheEntryWithTheNewerUpdatedAt()
@Test func mergeKeepsEntriesPresentOnOnlyOneSide()
@Test func isAvailableIsFalseWhenTheDirectoryCannotBeWritten()
```

- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement. `iCloudDirectory()` returns `~/Library/Mobile Documents/com~apple~CloudDocs/StickyDock`, creating it if needed, and `nil` if that fails. Every failure path is swallowed and reported through `isAvailable`, because a lost color is not worth crashing over.
- [ ] **Step 4:** Run. Expected: PASS.
- [ ] **Step 5:** Commit.

---

### Task 6: SyncEngine, the decision table

**Files:**
- Create: `StickyDock/Sources/StickyDockCore/SyncEngine.swift`
- Create: `StickyDock/Sources/StickyDockCore/ContentHash.swift`
- Test: `StickyDock/Tests/StickyDockCoreTests/SyncEngineTests.swift`
- Test: `StickyDock/Tests/StickyDockCoreTests/FakeNotesBridge.swift`

**Interfaces:**
- Consumes: `NoteStoring`, `NotesBridging`, `SidecarStoring`, `Note`, `RemoteNote`.
- Produces:
```swift
enum SyncAction: Equatable, Sendable {
    case none(noteId: String)
    case push(noteId: String)
    case pull(notesId: String)
    case create(noteId: String)         // local note not yet in Notes
    case adopt(notesId: String)         // remote note we have never seen
    case conflict(noteId: String, remoteText: String)
    case archiveLocal(noteId: String)   // vanished from the Notes folder
}
enum ContentHash { static func of(_ text: String) -> String }  // SHA-256 hex
struct SyncReport: Equatable, Sendable {
    var pushed: Int; var pulled: Int; var created: Int
    var adopted: Int; var conflicts: Int; var archived: Int
}
final class SyncEngine: Sendable {
    init(store: NoteStoring, bridge: NotesBridging, sidecar: SidecarStoring,
         account: String, folder: String)
    static func plan(local: [Note], remote: [RemoteNote]) -> [SyncAction]
    func runOnce() throws -> SyncReport
}
```

`plan` is `static` and pure. That is the point: every row of the spec's decision table is one assertion with no I/O.

- [ ] **Step 1: Write `FakeNotesBridge`,** an in-memory `NotesBridging` with a settable note list and a call log.
- [ ] **Step 2: Write the failing tests, one per row of the spec's table.**

```swift
@Test func unchangedOnBothSidesDoesNothing()
@Test func localChangedOnlyPushes()
@Test func remoteChangedOnlyPulls()
@Test func bothChangedIsAConflict()
@Test func localNoteWithoutNotesIdIsCreated()
@Test func unknownRemoteNoteIsAdopted()
@Test func noteMissingFromRemoteIsArchivedNotDeleted()
@Test func conflictKeepsBothTexts()
@Test func pushThenPollDoesNotLoop()   // the loop-breaking guarantee
@Test func archivedLocalNoteIsNotPushed()
@Test func emptyOnBothSidesProducesNoActions()
```

- [ ] **Step 3:** Run. Expected: FAIL.
- [ ] **Step 4:** Implement `ContentHash.of` with CryptoKit `SHA256`, then `plan`, then `runOnce` which applies each action and merges the sidecar.
- [ ] **Step 5:** Run. Expected: PASS.
- [ ] **Step 6:** Commit.

---

### Task 7: The dock panel, dormant and fanned

**Files:**
- Create: `StickyDock/Sources/StickyDock/DockPanel.swift`
- Create: `StickyDock/Sources/StickyDock/DockContentView.swift`
- Create: `StickyDock/Sources/StickyDock/NoteCardView.swift`
- Create: `StickyDock/Sources/StickyDock/AppState.swift`

**Interfaces:**
- Consumes: `Note`, `NoteColor`, `NoteStoring`.
- Produces: `final class DockPanel: NSPanel`, `@MainActor final class AppState: ObservableObject`.

- [ ] **Step 1:** `DockPanel` as an `NSPanel` with `styleMask [.nonactivatingPanel, .borderless]`, `isFloatingPanel = true`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, `hasShadow = true`, `backgroundColor = .clear`, `isOpaque = false`.
- [ ] **Step 2:** Position it on the right edge of `NSScreen.main.visibleFrame`, 12pt wide dormant, vertically centred, height driven by note count.
- [ ] **Step 3:** Add an `NSTrackingArea` with `[.mouseEnteredAndExited, .activeAlways, .inVisibleRect]` on the content view. Deliberately not a global monitor: that would need Accessibility permission.
- [ ] **Step 4:** On `mouseEntered`, animate the frame to 320pt wide. On `mouseExited`, animate back to 12pt after a 250ms grace period so a small overshoot does not collapse it.
- [ ] **Step 5:** `DockContentView` renders dots when collapsed and a fanned stack of `NoteCardView` when expanded, driven by `AppState.isExpanded`.
- [ ] **Step 6:** Build and run. Expected: a stripe of coloured dots on the right edge that fans open on hover and closes on exit. Verify by hand.
- [ ] **Step 7:** Commit.

---

### Task 8: The editor and colour picker

**Files:**
- Create: `StickyDock/Sources/StickyDock/NoteEditorView.swift`
- Modify: `StickyDock/Sources/StickyDock/DockContentView.swift`
- Modify: `StickyDock/Sources/StickyDock/AppState.swift`

**Interfaces:**
- Produces: `struct NoteEditorView: View`, and on `AppState`: `func newNote()`, `func update(_ note: Note, text: String)`, `func setColor(_ note: Note, _ color: NoteColor)`, `func archive(_ note: Note)`, `func delete(_ note: Note)`.

- [ ] **Step 1:** Clicking a card sets `AppState.selectedNoteId` and the panel widens to 360pt.
- [ ] **Step 2:** `NoteEditorView` holds a `TextEditor` bound to the note text, debounced 400ms before it writes to the store, so typing does not thrash SQLite.
- [ ] **Step 3:** A row of six colour swatches, plus archive and delete buttons. Delete asks for confirmation.
- [ ] **Step 4:** Escape closes the editor back to the fanned state.
- [ ] **Step 5:** Build, run, edit a note by hand, confirm the text persists across a restart.
- [ ] **Step 6:** Commit.

---

### Task 9: Wiring, the poll loop, the hotkey and the menu

**Files:**
- Create: `StickyDock/Sources/StickyDock/SyncCoordinator.swift`
- Create: `StickyDock/Sources/StickyDock/HotKey.swift`
- Create: `StickyDock/Sources/StickyDock/Preferences.swift`
- Modify: `StickyDock/Sources/StickyDock/AppDelegate.swift`

**Interfaces:**
- Produces: `@MainActor final class SyncCoordinator`, `final class HotKey`, `struct Preferences`.

- [ ] **Step 1:** `HotKey` wraps Carbon `RegisterEventHotKey`. Chosen over `NSEvent.addGlobalMonitorForEvents` precisely because Carbon needs no Accessibility permission. Default `⌃⌥N` creates a note and opens the editor.
- [ ] **Step 2:** `Preferences` in `UserDefaults`: account name (default `iCloud`), folder name (default `StickyDock`), screen edge, poll interval, hotkey enabled.
- [ ] **Step 3:** `SyncCoordinator` runs `SyncEngine.runOnce()` on a background task, every 15s while the panel is expanded and every 60s otherwise, plus once 2s after any local edit settles.
- [ ] **Step 4:** On `.notAuthorised`, show a one-time alert explaining the Automation prompt and how to fix it in System Settings, then stop retrying until the next launch.
- [ ] **Step 5:** Menu bar menu: New Note, Open All Notes, Sync Now, last sync status line, Preferences, Quit.
- [ ] **Step 6:** Build, run, create a note, confirm within 60s it appears in Apple Notes.
- [ ] **Step 7:** Commit.

---

### Task 10: The All Notes window

**Files:**
- Create: `StickyDock/Sources/StickyDock/AllNotesWindow.swift`
- Create: `StickyDock/Sources/StickyDock/AllNotesView.swift`

**Interfaces:**
- Consumes: `NoteStoring.search`, `AppState`.

- [ ] **Step 1:** A regular resizable `NSWindow` with a search field and a list.
- [ ] **Step 2:** Live search over title and body, including archived notes, shown with a muted style and an Unarchive button.
- [ ] **Step 3:** Selecting a row opens that note in the dock editor.
- [ ] **Step 4:** Build, run, search by hand.
- [ ] **Step 5:** Commit.

---

### Task 11: End-to-end verification in the real app

**Files:**
- Modify: `NOTES.md`
- Create: `StickyDock/README.md`

- [ ] **Step 1:** Run the full `swift test` suite. Record the count.
- [ ] **Step 2:** Run the live Notes suite with `STICKYDOCK_LIVE_NOTES=1`.
- [ ] **Step 3:** Drive the built app by hand: create a note, watch it appear in Notes.app, edit it in Notes.app, watch the change come back into StickyDock.
- [ ] **Step 4:** Force a conflict on purpose. Edit the same note in both places between polls. Assert both texts survive and a conflict copy exists.
- [ ] **Step 5:** Write `README.md`: what it is, how to build, the Automation prompt, how to point it at a different folder.
- [ ] **Step 6:** Adversarial pass. Name three plausible failure modes and say whether tests cover them.
- [ ] **Step 7:** Update `NOTES.md`, commit, and create the private repo under `hengkysandy`.
