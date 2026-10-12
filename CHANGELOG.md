# Changelog

All notable changes to NotePad are listed here. Each release on GitHub also lists the commits since the previous release.

## 1.3.0

### Added

- Tear-off tabs. Drag a tab well below the tab strip to open it in a new window under the cursor. The tab's context menu and File > Move Tab to New Window do the same without dragging.
- Each window keeps its own tabs and active tab. Menus, the toolbar and the status bar act on the focused window.
- Torn-off windows reopen with their tabs after a restart. Closing a torn-off window returns its tabs to the main window, so no unsaved text is lost.
- Drag a tab sideways to reorder it.

## 1.2.0

### Added

- Version history. NotePad keeps a copy of a file each time you save it. File > Version History lists the saved copies with a preview, and Restore puts one back into the tab as an undoable edit, so the file changes only when you save. Up to 50 copies or 20 MB are kept per file, the oldest go first, and files over 2 MB are not copied.

## 1.1.0

### Added

- Multiple cursors as in VS Code. Option-click adds or removes a caret, Command-Option-Up and Down add one above or below, Command-D adds the next match, and Shift-Option-drag selects a column. Typing, Backspace, Delete, Return, Tab, the arrow keys, paste, copy and cut work at every caret. A normal click or Escape returns to one caret.
- Option-Up and Option-Down now move the current line, as in VS Code.
- Regular-expression find and replace with capture groups.
- Find highlights every match in the Markdown preview, and the find bar stays open when you switch tabs.
- The preview scrolls with the editor, and clicking a heading in the preview moves the editor to it.
- Line commands: duplicate, move up or down, join, sort and remove duplicate lines.
- Snippets and templates, with date, time and cursor placeholders, plus Save Selection as Snippet.
- Export Markdown as HTML or PDF with the preview's styling.
- Share from the File menu, and an Open Selection in NotePad service for other apps.
- Focus Mode, reading time in the footer, and selection counts.
- Read-only files open with a banner and a Save As button.
- Recover Set-Aside Tabs for tabs that could not be read at launch, one prompt when closing several unsaved tabs, and a Dock badge with the number of unsaved tabs.

### Fixed

- The preview no longer shows a second scroll bar next to the editor's.

## 1.0.0

- First public version: tabs, session restore for unsaved text, find and replace, Go to Line, live counts, encodings and line endings, formatting toolbar, Formatted view, Markdown preview, line numbers, zoom (including Command + scroll), Liquid Glass chrome with a fallback, and VoiceOver labels.
