# NotePad for macOS: Design

Date: 2026-10-12

## Goal

A native macOS clone of Windows 11 Notepad. It opens any plain-text file (.txt, .md, .log, source files, and so on), supports multiple tabs, and never loses text: every open tab, saved or unsaved, is restored after quit or crash until the user closes that tab.

## Decisions

- **Stack:** Swift + AppKit. The macOS text system (NSTextView, TextKit 2) provides undo, IME, spell check and accessibility. Rust and Go were considered and rejected for the UI because neither has a mature native macOS GUI.
- **Shell:** SwiftUI app lifecycle, with an AppKit `NSTextView` wrapped for the editor. SwiftUI `TextEditor` is too limited for line/column tracking, find and zoom.
- **Persistence:** per-tab files in Application Support (see Session Store). SQLite and NSDocument autosave were rejected: SQLite is too heavy for a few tabs of text, and NSDocument fights the "unsaved tabs persist forever" requirement.
- **Platform target:** macOS 14 or later (TextKit 2). Liquid Glass chrome on macOS 26 and later, with a material-based fallback on 14 and 15.

## v1 Scope

Core:
- Tabs (new, close, reorder, switch with Cmd+1 to 9).
- Open and save plain-text files, Save As, drag a file onto the window or Dock icon.
- Full session restore of all tabs, including never-saved tabs.

Included features:
- Find, Replace, Go to line (match case, wrap-around, replace all).
- Status bar: Ln/Col, character count, zoom %, line ending (CRLF, LF, CR), encoding (UTF-8, UTF-8 BOM, UTF-16 LE/BE, Latin-1/Windows-1252).
- View: word wrap toggle, font picker, zoom in/out/reset (Cmd +, Cmd -, Cmd 0).
- Markdown preview for `.md` tabs, toggled per tab.
- Formatting toolbar (heading, list, bold, italic, link) and Formatted view, matching Windows 11 Notepad. See "Formatting toolbar and Formatted view".
- Live Lines, Words, Chars and "No spaces" counts in the status bar.

Out of scope for v1: syntax highlighting, plugins, split view, printing, cloud sync.

## Architecture

Each module has one purpose and a narrow interface.

| Module | Responsibility | Depends on |
|---|---|---|
| `TextDocument` | Model for one tab: id, text, file URL, encoding, line ending, dirty flag, selection, scroll offset, zoom | none |
| `SessionStore` | Persist and restore tabs. Owns debounce, atomic writes, corrupt-file quarantine | `TextDocument` |
| `FileService` | Read and write files, detect encoding and line endings, throw specific errors | `TextDocument` |
| `EditorView` | NSTextView wrapper: word wrap, font, zoom, selection and scroll reporting | `TextDocument` |
| `FindController` | Find, replace, go to line against the text view | `EditorView` |
| `StatusBar` | Shows Ln/Col, counts, zoom, encoding, line ending | `TextDocument` |
| `MarkdownPreview` | Rendered pane for `.md` tabs | `TextDocument` |
| `AppState` | Ordered tab list, active tab, wires modules together | all of the above |

### Data flow

1. Typing updates `TextDocument` and fires a debounced `SessionStore.save(tab)` (about 300 ms after the last keystroke).
2. On launch, `SessionStore.restore()` rebuilds all tabs before the first window is shown.
3. Save writes the buffer to the file URL through `FileService` and marks the tab clean. The session entry is kept.
4. Closing a tab is the only action that deletes its session file.
5. Quit flushes any pending debounced saves synchronously before exit.

## Session Store

Location: `~/Library/Application Support/NotePad/session/`

- `manifest.json`: schema version, ordered list of tab ids, active tab id, window frame.
- `<uuid>.json` per tab: text, file path (nil if never saved), encoding, line ending, cursor, scroll offset, zoom, dirty flag, last-known disk modification date.

Rules:
- All writes are atomic (write to a temp file in the same directory, then rename).
- A tab file that fails to decode is moved to `session/quarantine/` and the remaining tabs still restore. The user sees a one-line notice.
- Orphan tab files (not in the manifest) are recovered as extra tabs rather than deleted.
- `manifest.json` carries a `schemaVersion`. Unknown future versions are opened read-only without overwriting.

## Error Handling

- `FileService` throws typed errors: `fileNotFound`, `permissionDenied`, `undecodable(encodingsTried:)`, `writeFailed(underlying:)`. The UI shows a specific message for each; nothing is swallowed.
- Opening a file that is not valid in the detected encoding offers "Reopen with encoding" instead of failing.
- If a saved file changed on disk while the app was closed, the tab keeps the unsaved buffer and shows a "changed on disk" bar with Keep mine, Reload, and Compare-by-saving-as options.
- If the file was deleted or moved, the tab stays open as an unsaved document.
- Disk-full or permission errors during session save surface a non-blocking warning and retry on the next edit.
- Large files: files over 50 MB open with a confirmation and with Markdown preview disabled.

## Testing

- **Unit tests (XCTest):**
  - `SessionStore`: round-trip save and restore, atomic write (simulated crash mid-write leaves previous version), corrupt file quarantine, orphan recovery, schema version handling, debounce coalescing.
  - `FileService`: encoding detection (UTF-8, BOM variants, UTF-16, Latin-1), line-ending detection and preservation on save, typed errors.
  - `FindController`: find, replace, replace all, wrap-around, go to line bounds.
  - `TextDocument`: dirty tracking, Ln/Col calculation with CRLF and multi-byte characters.
- **UI tests (XCUITest):** open file, type, quit without saving, relaunch, text is still there; close tab deletes its session file; zoom and word wrap persist per tab.
- **Manual checks:** IME input (Japanese or Chinese), VoiceOver, force-quit during typing.
- Tests are written first for `SessionStore` and `FileService`, since data loss is the failure that matters most.

## Build and Layout

- **Swift Package Manager, not an Xcode project.** The machine has only the Command Line Tools installed (no full Xcode), so `Package.swift` defines every target. `Scripts/bundle.sh` builds the executable and assembles a signed `NotePad.app` with an icon generated by `Scripts/make-icon.swift`. An Xcode project can be added later for App Store signing and XCUITest; nothing here blocks that.
- Targets:
  - `NotePadCore`: pure logic (models, file I/O, session store, find, formatting, stats). No UI imports.
  - `MarkdownRendering`: Markdown to HTML for the preview, and Markdown syntax spans for the Formatted view. Depends on `swift-markdown`.
  - `NotePad`: the app (AppKit editor, SwiftUI chrome, glass modifiers).
  - `NotePadCoreTests`, `MarkdownRenderingTests`: unit tests, Swift Testing framework.
- **`@Local` instead of `@State`.** The macOS 27 SDK declares `@State` as a macro, and its compiler plugin ships only with full Xcode, so a Command Line Tools build fails. `Sources/NotePad/Local.swift` provides an equivalent wrapper. When Xcode is installed it can be replaced with `@State` in one search-and-replace.
- Directories: `Sources/`, `Tests/`, `Scripts/`, `Resources/` (Info.plist), `docs/`.
- Pre-completion checks: `swift build`, `swift test`, `swiftlint lint --strict` (run with `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools`, because SwiftLint needs that variable to find SourceKit on this machine), and `Scripts/bundle.sh` to confirm the app bundle builds.
- Known toolchain issue: `swift test` sometimes fails once with "plugin for module TestingMacros not found" right after files are added. A rerun passes. The plan treats a rerun as the fix and does not paper over real failures.

## UI and Visual Design

Design read: a native macOS utility for everyday writers and developers, calm and quiet, built on Apple's Human Interface Guidelines. The goal is an app that looks like Apple shipped it, and is clearly nicer to use than Windows Notepad. Dials: low variance (predictable, consistent), low motion (system-standard only), low-to-medium density.

### Liquid Glass

- **Real system material, not an imitation.** On macOS 26 and later the chrome uses Apple's Liquid Glass through AppKit and SwiftUI (`NSGlassEffectView` / `glassEffect`). On macOS 14 and 15 it falls back to `NSVisualEffectView` materials, so the app still looks native on older systems.
- **Glass for chrome only.** The tab strip, toolbar buttons, find bar and status bar are floating glass capsules over the document. The editing surface itself stays opaque for legibility. Text scrolls underneath the glass bars, which blur it, instead of stopping at a hard edge.
- Glass elements are grouped in a `GlassEffectContainer` so neighboring capsules blend and morph correctly, and there are never more than two stacked glass layers.
- Respects Reduce Transparency (solid fills) and Increase Contrast. Text on glass is always checked for AA contrast in light and dark mode.
- A standalone web approximation for design review lives at `docs/mockups/notepad-glass.html`. It is a preview only and is not shipped.

### Principles

1. **Quiet chrome, loud content.** The text is the product. Toolbar, tabs and status bar stay low-contrast and never compete with the document.
2. **Use the system, do not imitate it.** Real system semantic colors, SF Pro for UI, SF Symbols for icons, system materials for bars. No hand-drawn icons, no custom palette.
3. **One accent.** The accent is the user's macOS accent color (`controlAccentColor`), used only for selection, focus rings and the active-state highlight. Nothing else is colored.
4. **One shape rule.** Tabs and the find bar use a 8 pt corner radius; everything else is system-drawn. No mixed radii.
5. **4 pt spacing grid.** All padding and gaps are multiples of 4 pt.
6. **Every state is designed.** Empty, loading, error, dirty, disabled, focused, and full-screen are all specified below, not left to defaults.

### Window and tab bar

- Single window, `fullSizeContentView` with a transparent title bar, so the tab strip sits in the title bar area as in Safari or Notepad 11. The standard traffic lights and window drag area are preserved.
- Tab strip, 32 pt tall: tabs share the width up to a 200 pt maximum and 96 pt minimum, then scroll with fade-out edges. The active tab uses the text-background color with a subtle 1 px separator; inactive tabs are flat and secondary-label colored.
- Dirty (unsaved) state: a small filled circle in place of the close button. On hover it becomes the close "x". This is semantic state, not decoration.
- Plus button for a new tab at the end of the strip, SF Symbol `plus`, regular weight.
- Drag to reorder with live displacement of neighbors. Middle-click or Cmd+W closes. Right-click menu: Close, Close Others, Close to the Right, Reveal in Finder, Copy Path.
- The tab bar is the highest-risk custom component, so it is prototyped first and reviewed visually before the rest of the UI is built.

### Editor

- Default font SF Mono 13 pt, line height 1.4, user-selectable in Settings. Text container inset 16 pt horizontally and 12 pt at the top. No visible line-number gutter in v1 (Ln/Col lives in the status bar), no gutter border, no alternating row colors.
- Colors: `textBackgroundColor` and `textColor`, selection from the system. Light, Dark and the Increase Contrast setting all work with no custom logic. Pure black and pure white are never hard-coded.
- Caret, selection, spell check underline, and Writing Tools behave exactly as in other macOS apps because the system text view is used.
- Word wrap on by default for .txt and .md, off for source files (by extension), with a per-tab override in the View menu.
- Zoom is smooth and persists per tab; Cmd+0 resets to 100%.

### Status bar

- A floating Liquid Glass capsule at the bottom center, 28 pt tall, 11 pt system font in `secondaryLabelColor`, tabular numerals so values do not jitter as they change.
- Live counts, updated on every keystroke and selection change: **Ln/Col**, **Lines**, **Words**, **Chars** (with spaces), and **No spaces** (characters excluding all whitespace). Zoom %, line ending and encoding sit at the right. Groups are separated by a hairline, not dots.
- When text is selected, the four counts switch to the selection ("Selected Words 12") and revert when the selection is cleared, as Windows Notepad does.
- Zoom, line ending and encoding are buttons: hover shows a subtle rounded background, click opens a native menu or popover to change them (for example Reopen with Encoding).
- Counting is done by a `TextStats` unit in `NotePadCore`. Words are whitespace-delimited runs, counted by Unicode scalars and grapheme clusters, so emoji and accented characters each count as one character. For small documents it recomputes on each edit. For large files (over 1 MB) it updates incrementally from the edited range and falls back to a debounced background recount, so typing never stalls. Counts are covered by unit tests, including CRLF, empty text, emoji, and CJK.

### Find and replace

- An inline bar anchored to the top of the editor (Safari and Xcode style), not a modal dialog. Slides in over 150 ms. Fields for Find and Replace, a live "3 of 17" match counter, Match Case and Whole Word toggles, previous and next buttons, Replace and Replace All.
- Matches are highlighted in the text with the system find-indicator color; the current match is emphasized. No-match state turns the field border to the system red and shows "No results".
- Go to Line is a small popover (Cmd+L) with a single field, validating the line range inline.

### Formatting toolbar and Formatted view

Windows 11 Notepad has a formatting toolbar and a Formatted mode, so v1 matches it.

- **Toolbar** (a Liquid Glass capsule above the editor, after the tab strip): Heading menu (H1 to H6, Normal Text), List menu (bulleted, numbered), Bold, Italic, Link, then the view controls: Formatted toggle (the "Aa" button), Markdown preview toggle, and Find.
- **Shortcuts:** Cmd+B bold, Cmd+I italic, Cmd+K link, Cmd+Option+1 to 6 heading levels, Cmd+Option+0 normal text, Cmd+Shift+8 bulleted list, Cmd+Shift+7 numbered list.
- **Formatting is plain Markdown in the file.** Each command edits the text (`**bold**`, `# Heading`, `- item`, `[text](url)`). Nothing is stored in a rich-text format, so files stay plain text and open correctly in any editor. `MarkdownFormatter` is a pure function in `NotePadCore` and is fully unit tested, including toggling off.
- **Formatted view** styles the Markdown syntax in place: headings get larger type, bold and italic are applied, code gets a background, links are colored and clickable, and markers (`**`, `#`) are dimmed but stay visible. The text is never changed by styling. Off means raw text.
- **Defaults:** Formatted view is on for `.md` tabs and off for everything else. A setting turns it on for all text files, and the toolbar toggles it per tab.
- **Preview pane is kept** alongside the Formatted view, as a separate split pane for `.md` files. It renders the full document (see Markdown preview).
- Styling skips documents over 1 MB to keep typing responsive, and runs 80 ms after the last keystroke.

### Markdown preview

- A toolbar toggle splits the tab into editor and preview with a draggable divider. Scroll position is synced proportionally.
- Rendering: `swift-markdown` parses, a `WKWebView` renders with a bundled stylesheet that uses the system font stack, the same text colors as the editor, a 680 pt reading width, SF Mono code blocks, and proper dark mode.
- The preview is read-only, never loads remote content by default, and links open in the default browser.

### Settings, menus, and the app icon

- Settings uses the native Settings scene with a General tab (default font, size, wrap, restore behavior) and an Editor tab. No custom-styled preferences window.
- The full macOS menu bar is implemented: File, Edit, View, Window, Help, with standard shortcuts and the standard Services and Writing Tools entries.
- The app gets a proper icon in the macOS style (a clean notepad glyph on the standard rounded-square template), made as a deliverable in the plan, not left as the default.

### Motion

- Only system-standard motion: tab insert and remove (150 ms ease), find bar slide (150 ms), and the preview split. No decorative animation. All of it is skipped when Reduce Motion is on.

### Accessibility

- Full keyboard operation, VoiceOver labels on every control (tab titles announce "unsaved" state), contrast that passes WCAG AA in light and dark, and respect for Reduce Transparency, Increase Contrast, and larger text in the UI chrome.

### Visual QA gate

The UI is not done until it has been checked, with screenshots, in: light mode, dark mode, Increase Contrast, a narrow and a wide window, full screen, 1 tab and 20 tabs, a dirty tab, empty state, find bar open with and without matches, and Markdown preview open. A "does this look broken or generic?" review against this section is part of the plan's definition of done.

## Open Questions

None at this point.
