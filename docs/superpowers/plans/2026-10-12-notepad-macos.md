# NotePad for macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS text editor that opens plain-text and Markdown files in tabs, never loses unsaved text across quit or crash, and looks and feels like Apple shipped it, with Liquid Glass chrome and the Windows 11 Notepad feature set.

**Architecture:** A Swift Package with three targets. `NotePadCore` holds pure logic (file I/O, session persistence, find, formatting, counts) and is tested without UI. `MarkdownRendering` turns Markdown into HTML for the preview and into style spans for the Formatted view. `NotePad` is the AppKit editor (`NSTextView`, one per tab) inside SwiftUI chrome with glass modifiers. Session state is one JSON file per tab plus a manifest, written atomically through a debounced coordinator.

**Tech Stack:** Swift 6.4 toolchain (Swift 5 language mode), AppKit, SwiftUI, TextKit 2, WebKit (preview), `swift-markdown`, Swift Testing, SwiftLint. macOS 14 minimum; Liquid Glass on macOS 26 and later.

**Spec:** [docs/superpowers/specs/2026-10-12-notepad-macos-design.md](../specs/2026-10-12-notepad-macos-design.md)

---

## Current state

The project folder already contains the package, built and verified. Tasks 1 to 5 are complete with passing tests. Tasks 6 to 8 compile and the app bundle builds. Tasks 9 to 11 are open.

| Check | Result |
|---|---|
| `swift test`, NotePadCoreTests | 109 tests in 10 suites pass |
| `swift test`, MarkdownRenderingTests | 21 tests in 2 suites pass |
| `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint lint --strict` | clean |
| `swift build` and `Scripts/bundle.sh debug` | builds, signed `NotePad.app` produced |
| App launched and inspected (macOS 27) | tabs, toolbar, status bar, Markdown preview split, Formatted view styling confirmed visually |
| Verified in app since | Unsaved-changes prompt (Cancel, Don't Save), external-change reload and banner, quit and relaunch with unsaved text, force quit, corrupt session file quarantine, 2 MB file, Go to Line, Replace All, Save As, light mode, narrow window, line-number gutter alignment, pointing-hand cursor on controls (code applied; screenshots do not show the pointer, so confirm by hovering) |
| Not yet verified | Full screen (shortcut did not engage), Reduce Transparency, VoiceOver speech output, dark mode after the latest changes |

Run from the project root (`/Users/a12345/Desktop/AI/Github Projects/NotePad`). Set `TOOLCHAIN_DIR` for every SwiftLint run.

---

## File Structure

```
Package.swift
.swiftlint.yml
Resources/Info.plist                      bundle metadata, document types
Scripts/bundle.sh                         build, assemble, sign NotePad.app
Scripts/make-icon.swift                   draws the app icon at all sizes
Sources/NotePadCore/
  LineEnding.swift                        detect and convert CRLF, LF, CR
  TextEncoding.swift                      BOM and encoding detection
  FileService.swift                       read and write with typed errors
  TextStats.swift                         lines, words, characters, no-space count
  LineLocator.swift                       line and column math, go to line
  MinimalEdit.swift                       smallest change between two strings
  FindEngine.swift                        find, replace, match navigation
  MarkdownFormatter.swift                 toggle bold, italic, headings, lists, links
  TabSnapshot.swift                       persisted form of one tab
  TextDocument.swift                      model for one tab (@Observable)
  SessionStore.swift                      atomic session directory, restore, quarantine
  SessionCoordinator.swift                debounced saves, flush on quit
Sources/MarkdownRendering/
  MarkdownHTML.swift                      Markdown to safe HTML for the preview
  MarkdownStyler.swift                    Markdown to style spans for the Formatted view
Sources/NotePad/
  NotePadApp.swift                        @main, scenes
  AppDelegate.swift                       launch, open files, quit flush
  AppState.swift                          tabs, files, disk checks, commands (@Observable)
  EditorController.swift                  one NSTextView per tab, styling, find highlights
  EditorHost.swift                        embeds the controller's scroll view in SwiftUI
  StatsModel.swift                        live counts, background recount for big files
  FindModel.swift                         find and replace state
  Settings.swift, SettingsView.swift      editor preferences
  Glass.swift                             Liquid Glass modifiers with fallback
  Local.swift                             @Local wrapper (see Task 6)
  Dialogs.swift                           save, close, encoding prompts
  ContentView.swift                       window layout and overlays
  TabBarView.swift                        glass tab strip with drag, close, context menu
  ToolbarView.swift                       heading, list, bold, italic, link, view controls
  StatusBarView.swift                     counts, position, zoom, line ending, encoding
  FindBarView.swift                       inline find and replace bar
  Banners.swift                           disk-change bar, transient notices
  MarkdownPreviewView.swift               WKWebView preview with scroll sync
  NotePadCommands.swift                   menu bar and shortcuts
Tests/NotePadCoreTests/                   one file per core unit
Tests/MarkdownRenderingTests/             renderer and styler tests
```

Files change together when they share one responsibility. `AppState` is the one large file. Task 11 splits its disk-change logic into core so it can be tested.

---

## Task 1: Encoding and line endings

**Status:** Complete.

**Files:**
- Create: `Sources/NotePadCore/LineEnding.swift`, `Sources/NotePadCore/TextEncoding.swift`, `Sources/NotePadCore/FileService.swift`
- Test: `Tests/NotePadCoreTests/LineEndingTests.swift`, `Tests/NotePadCoreTests/FileServiceTests.swift`

Behavior the tests pin down:
- `LineEnding.detect` returns the first ending found; lone CR counts; no break means LF.
- The editor buffer is always LF. `normalizedToLF` on read, `applying(to:)` on write, so saves keep the file's own line endings.
- `TextEncoding.detect` checks BOMs (UTF-8, UTF-16 LE/BE), then UTF-8 validity, then falls back to Windows-1252.
- `FileService.write` is atomic and writes the BOM for BOM encodings. Characters the target encoding can't hold throw `writeFailed`.
- Missing files throw `fileNotFound`. A forced encoding overrides detection.

- [ ] **Step 1: Run the tests**

Run: `swift test --filter NotePadCoreTests`
Expected: all Line ending and File service tests pass.

- [ ] **Step 2: Commit**

```bash
git add Sources/NotePadCore/LineEnding.swift Sources/NotePadCore/TextEncoding.swift Sources/NotePadCore/FileService.swift Tests/NotePadCoreTests/LineEndingTests.swift Tests/NotePadCoreTests/FileServiceTests.swift
git commit -m "feat: add encoding, line ending and file service"
```

---

## Task 2: Counts, positions, find and minimal edits

**Status:** Complete.

**Files:**
- Create: `Sources/NotePadCore/TextStats.swift`, `LineLocator.swift`, `MinimalEdit.swift`, `FindEngine.swift`
- Test: `TextStatsTests.swift`, `FindEngineTests.swift` (includes `LineLocatorTests`), `MinimalEditTests.swift`

Behavior:
- `TextStats`: lines (empty is 0, trailing newline adds a line), words are whitespace-delimited runs, characters are grapheme clusters (emoji with skin tone is one), no-space count excludes all whitespace.
- `LineLocator`: 1-based line and column in UTF-16 locations; columns count characters, so an emoji is one column; out-of-range locations clamp.
- `MinimalEdit`: the single replaced range between two strings. Used so NSTextView undo and selection survive a formatting command. Never splits a surrogate pair.
- `FindEngine`: case-insensitive by default, whole-word option, non-overlapping matches, replace-all in reverse order, wrap-around next and previous.

- [ ] **Step 1: Run the tests**

Run: `swift test --filter NotePadCoreTests`
Expected: all pass.

- [ ] **Step 2: Commit**

```bash
git add Sources/NotePadCore/TextStats.swift Sources/NotePadCore/LineLocator.swift Sources/NotePadCore/MinimalEdit.swift Sources/NotePadCore/FindEngine.swift Tests/NotePadCoreTests
git commit -m "feat: add text stats, line locator, minimal edit and find engine"
```

---

## Task 3: Document model and session persistence

**Status:** Complete.

**Files:**
- Create: `Sources/NotePadCore/TabSnapshot.swift`, `TextDocument.swift`, `SessionStore.swift`, `SessionCoordinator.swift`
- Test: `TextDocumentTests.swift`, `SessionStoreTests.swift`, `SessionCoordinatorTests.swift`

Behavior that matters most, because losing text is the failure to avoid:
- Every tab, saved or not, is written to `Application Support/NotePad/session/<uuid>.json`. `NOTEPAD_SESSION_DIR` overrides the folder for tests and QA.
- Writes are atomic. A corrupt tab file moves to `session/quarantine/` and the rest restore.
- Orphan tab files (not in the manifest) come back as tabs. Nothing is deleted by restore.
- A manifest with a newer `schemaVersion` restores read-only and is never overwritten.
- `SessionCoordinator` debounces each tab (300 ms), `flush()` writes everything pending, `remove()` cancels a pending write and deletes only that tab's file.

- [ ] **Step 1: Run the tests**

Run: `swift test --filter NotePadCoreTests`
Expected: all pass, including the corrupt-file, orphan and read-only cases.

- [ ] **Step 2: Commit**

```bash
git add Sources/NotePadCore/TabSnapshot.swift Sources/NotePadCore/TextDocument.swift Sources/NotePadCore/SessionStore.swift Sources/NotePadCore/SessionCoordinator.swift Tests/NotePadCoreTests
git commit -m "feat: add document model and crash-safe session store"
```

---

## Task 4: Markdown formatting commands

**Status:** Complete.

**Files:**
- Create: `Sources/NotePadCore/MarkdownFormatter.swift`
- Test: `Tests/NotePadCoreTests/MarkdownFormatterTests.swift`

Behavior: each command toggles. Bold and italic wrap the selection, unwrap when already wrapped, and cope with an empty caret. Headings add, change or remove the prefix on every touched line. Lists add or remove prefixes and skip blank lines. Links wrap the selection with `https://` as a placeholder and select it, or put the caret after a real URL. Selections are clamped, and everything works in UTF-16.

- [ ] **Step 1: Run the tests**

Run: `swift test --filter MarkdownFormatterTests`
Expected: all pass.

- [ ] **Step 2: Commit**

```bash
git add Sources/NotePadCore/MarkdownFormatter.swift Tests/NotePadCoreTests/MarkdownFormatterTests.swift
git commit -m "feat: add markdown formatting commands"
```

---

## Task 5: Markdown rendering and styling

**Status:** Complete.

**Files:**
- Create: `Sources/MarkdownRendering/MarkdownHTML.swift`, `Sources/MarkdownRendering/MarkdownStyler.swift`
- Test: `Tests/MarkdownRenderingTests/MarkdownHTMLTests.swift`, `Tests/MarkdownRenderingTests/MarkdownStylerTests.swift`
- Modify: `Package.swift` (depends on `swift-markdown`)

Behavior:
- `MarkdownHTML` escapes raw HTML, drops links with unsafe schemes (`javascript:` and similar), never emits remote images, and renders headings, lists, code, quotes and tables.
- `MarkdownStyler` returns UTF-16 spans (headings, strong, emphasis, code, links, list markers, quotes) plus `.marker` spans for the syntax characters. Documents over 1 MB return no spans.
- The Formatted view styles the text without changing it.

- [ ] **Step 1: Run the tests**

Run: `swift test --filter MarkdownRenderingTests`
Expected: all 21 pass.

- [ ] **Step 2: Commit**

```bash
git add Sources/MarkdownRendering Tests/MarkdownRenderingTests Package.swift
git commit -m "feat: add markdown preview rendering and formatted view styling"
```

---

## Task 6: App shell, editor and state

**Status:** Compiles. Behavior verified by launch and screenshot only. Unit tests are added in Task 11.

**Files:**
- Create: `Sources/NotePad/Local.swift`, `Settings.swift`, `Glass.swift`, `Dialogs.swift`, `StatsModel.swift`, `AppState.swift`, `EditorController.swift`, `EditorHost.swift`, `FindModel.swift`

Notes for the implementer:
- `Local.swift` is a stand-in for `@State`. The macOS 27 SDK's `@State` macro needs a compiler plugin that Command Line Tools lacks. Use `@Local` in views. Revisit when Xcode is installed.
- `EditorController` owns one `PlainTextView` (NSTextView, paste as plain text only) per tab, so undo, selection and scroll survive tab switches. Find highlights are rendering attributes on the TextKit 2 layout manager, not text attributes, so they never reach the saved file.
- `EditorController.apply(settings:zoom:wrap:formatted:)` first applies state, then restyles only when something changed. Restyling is debounced at 80 ms.
- `AppState` is the only place that performs file, session and disk operations. Views call its methods and never touch files.
- `StatsModel` counts on the main thread up to 1 MB and in a background task above that, with a 150 ms debounce.

- [ ] **Step 1: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 2: Commit**

```bash
git add Sources/NotePad/Local.swift Sources/NotePad/Settings.swift Sources/NotePad/Glass.swift Sources/NotePad/Dialogs.swift Sources/NotePad/StatsModel.swift Sources/NotePad/AppState.swift Sources/NotePad/EditorController.swift Sources/NotePad/EditorHost.swift Sources/NotePad/FindModel.swift
git commit -m "feat: add app state, editor controller and find model"
```

---

## Task 7: SwiftUI chrome

**Status:** Compiles. Tab strip, toolbar, status bar, preview split and window overlays confirmed on screen. Find bar and banners not yet confirmed.

**Files:**
- Create: `Sources/NotePad/TabBarView.swift`, `ToolbarView.swift`, `StatusBarView.swift`, `FindBarView.swift`, `Banners.swift`, `MarkdownPreviewView.swift`, `ContentView.swift`, `SettingsView.swift`, `AppDelegate.swift`, `NotePadApp.swift`, `NotePadCommands.swift`

Behavior:
- Tab strip: glass capsule, tabs 96 to 200 pt wide, active tab tinted with the accent color, unsaved tabs show a dot that becomes a close button on hover, drag to reorder, right-click menu (Close, Close Others, Close to the Right, Reveal in Finder, Copy Path).
- Toolbar: Heading menu, List menu, Bold, Italic, Link, Formatted toggle, Preview toggle, Find. Shortcuts are in `NotePadCommands`.
- Status bar: Ln and Col (opens Go to Line on click), Lines, Words, Chars, No spaces, selection counts when text is selected, zoom, line ending and encoding menus.
- `AppDelegate.applicationShouldTerminate` awaits `flushSession()` before replying, so quitting never loses text.
- `PlainTextView` and `MarkdownPreviewView` disable script in the preview and open links in the browser.

- [ ] **Step 1: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 2: Commit**

```bash
git add Sources/NotePad/TabBarView.swift Sources/NotePad/ToolbarView.swift Sources/NotePad/StatusBarView.swift Sources/NotePad/FindBarView.swift Sources/NotePad/Banners.swift Sources/NotePad/MarkdownPreviewView.swift Sources/NotePad/ContentView.swift Sources/NotePad/SettingsView.swift Sources/NotePad/AppDelegate.swift Sources/NotePad/NotePadApp.swift Sources/NotePad/NotePadCommands.swift
git commit -m "feat: add glass chrome, tab bar, toolbar, status bar and find bar"
```

---

## Task 8: App icon and bundle

**Status:** Complete. `Scripts/bundle.sh debug` produces a signed bundle.

**Files:**
- Create: `Scripts/make-icon.swift`, `Scripts/bundle.sh`, `Resources/Info.plist`

- [ ] **Step 1: Build the bundle**

Run: `Scripts/bundle.sh release`
Expected: `Built .../build/NotePad.app`, and `plutil -lint build/NotePad.app/Contents/Info.plist` reports OK.

- [ ] **Step 2: Commit**

```bash
git add Scripts Resources
git commit -m "build: add app icon generator and bundle script"
```

---

## Task 9: Make the three remaining behaviors work (find, save and close, disk changes)

**Files:**
- Modify: `Sources/NotePad/AppState.swift`, `Sources/NotePad/FindBarView.swift`

- [ ] **Step 1: Find bar visual check**

Launch with sample files, press Cmd+F, type a query, and confirm: the counter reads "2 of 4", matches are highlighted, the current match is stronger, "No results" shows in red for a miss, and Escape closes the bar and returns focus to the editor. Fix any layout problem found.

- [ ] **Step 2: Save and close flow**

Confirm: Cmd+S on an untitled tab opens Save As; closing a dirty tab shows "Do you want to save changes to X?"; Cancel keeps the tab; Don't Save removes the tab and its session file; closing the last tab leaves one empty Untitled tab.

- [ ] **Step 3: External change**

Edit a file outside NotePad with a dirty tab open, and confirm the "changed on disk" bar offers Keep Mine and Reload. Edit it again with a clean tab and confirm it reloads silently. Delete a file and confirm the "moved or deleted" bar offers Save As.

- [ ] **Step 4: Commit fixes**

```bash
git add Sources/NotePad
git commit -m "fix: correct find bar, save and close, and disk change flows"
```

---

## Task 10: Quit and crash safety, end to end

**Files:**
- No source changes expected. If a check fails, fix the cause and add a regression test.

- [ ] **Step 1: Quit with unsaved text**

Type into an untitled tab and a saved tab without saving. Quit with Cmd+Q. Relaunch with the same `NOTEPAD_SESSION_DIR`. Expected: both tabs restored with their text, the unsaved dot still shown, and the active tab selected.

- [ ] **Step 2: Force quit**

Type, wait 1 second, then `kill -9` the process. Relaunch. Expected: text typed before the 300 ms debounce expired is restored, and the session is not corrupted.

- [ ] **Step 3: Corrupt session file**

Corrupt one tab's JSON in the session folder and relaunch. Expected: the bad file moves to `quarantine/`, the other tabs restore, and a notice appears.

- [ ] **Step 4: Large file**

Open a file over 1 MB. Expected: typing stays responsive, Formatted view shows no spans, and counts update after a short pause.

---

## Task 11: Visual QA gate and testability fixes

**Files:**
- Create: `Sources/NotePadCore/DiskChangeDetector.swift`, `Tests/NotePadCoreTests/DiskChangeDetectorTests.swift`
- Modify: `Sources/NotePad/AppState.swift` (call the detector instead of inline logic)

- [ ] **Step 1: Move the disk-change decision into core**

Create `DiskChangeDetector` with one pure function: given the last known modification date, the current one (or nil when missing), and whether the tab is dirty, return `.unchanged`, `.reload`, `.conflict`, or `.missing`. Use a 0.5 s tolerance. Write the tests first, then call it from `AppState.checkDisk`.

- [ ] **Step 2: Screenshot matrix**

Capture each state below with `app_screenshot` and check it against the spec's visual rules (no broken layout, no generic look, contrast readable). Record any problems and fix them.
- Light and dark mode (`NOTEPAD_APPEARANCE=light` and `dark`)
- Narrow window (about 760 pt) and wide window
- Full screen
- One tab and 20 tabs (tab strip scrolls with fade edges)
- Dirty tab
- Empty document
- Find bar with and without matches
- Markdown preview open
- Increase Contrast and Reduce Transparency (System Settings, Accessibility)

- [ ] **Step 3: Accessibility**

Check with VoiceOver on: tab labels announce "unsaved" state, toolbar buttons have labels, the editor is announced as "Editor", the status bar is a labelled group, and the find bar counter is read on change.

- [ ] **Step 4: Full verification**

Run each command and confirm the output:
```bash
swift build
swift test
TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint lint --strict
Scripts/bundle.sh release
```
Expected: every command succeeds. Report the actual counts from the test output.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: extract disk change decision and complete visual QA fixes"
```

---

## Open items the plan does not yet cover

- **Preferences window styling and font list.** The font picker lists fixed-pitch families. It has not been checked against a machine with many installed fonts.
- **Writing Tools and spell check.** Automatic substitutions are off, but Writing Tools and spell check depend on the system and have not been tested.
- **App Store and notarization.** Not in v1. The bundle is ad-hoc signed for local use.
- **Xcode project.** Add once full Xcode is installed, for XCUITest and signing. Then replace `@Local` with `@State`.

## Plan self-review

- Spec coverage: session store (Task 3), error handling (Tasks 1, 3, 9, 11), status bar counts (Task 2, 6, 7), find and replace (Tasks 2, 9), Markdown preview (Tasks 5, 7), formatting toolbar and Formatted view (Tasks 4, 5, 7), Liquid Glass with fallback (Task 7), icon (Task 8), testing and visual QA gate (Tasks 10, 11). Gaps are listed under open items.
- Placeholders: none in the code steps. Each command shows its expected output.
- Type consistency: `TextDocument`, `TabSnapshot`, `SessionStore`, `SessionCoordinator`, `FindEngine`, `MarkdownFormatter` and `MarkdownCommand` names match across tasks and the source files.

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-12-notepad-macos.md`. Two execution options:

1. **Subagent-driven (recommended):** a fresh subagent per task, with review between tasks.
2. **Inline execution:** run tasks in this session with checkpoints.

Before any task commits, the project needs `git init`, since the folder is not a repository yet.
