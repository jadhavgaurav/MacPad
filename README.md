# NotePad

A native macOS text editor that looks and works like Windows 11 Notepad, built with Swift, AppKit and SwiftUI.

- Open any plain-text or Markdown file in tabs
- Unsaved text survives quit and crashes. Every tab is restored until you close it, and tabs that could not be read are kept aside for recovery.
- Find and replace with regular expressions and capture groups, Go to Line, live counts, selection counts and reading time
- Multiple cursors as in VS Code: Option-click, Command-Option-Up or Down, Command-D for the next match, and Shift-Option-drag for a column
- Line commands: duplicate, move up or down, join, sort and remove duplicate lines
- Snippets and templates with date, time and cursor placeholders
- Formatting toolbar, Formatted view, and a Markdown preview that scrolls with the editor, highlights find matches and jumps to a heading when you click it
- Export Markdown as HTML or PDF, share a tab, and open selected text from any app with the Open Selection in NotePad service
- Tabs can be dragged out of the tab strip into their own window, and dragged back in with the context menu
- Version history: a copy of the file is kept each time you save, and any copy can be previewed and restored
- Focus Mode, read-only files with a banner and Save As, and a Dock badge for unsaved tabs
- Encodings (UTF-8, UTF-8 with BOM, UTF-16, Windows-1252) and line endings (LF, CRLF, CR)
- Liquid Glass chrome on macOS 26 and later, with a system-material fallback on macOS 14 and 15

## Install

1. Go to the [Releases page](https://github.com/jadhavgaurav/NotePad/releases) and download the latest `NotePad-<version>-macos.dmg`.
2. Open the DMG and drag **NotePad** onto the **Applications** shortcut.
3. Open NotePad from Applications. macOS will say it could not verify NotePad, so click **Done** (not Move to Trash).
4. Allow it once:
   - Open **System Settings → Privacy & Security**, scroll down to the message about NotePad, click **Open Anyway**, then enter your password.
   - Or run this in Terminal, then open NotePad again:

     ```bash
     xattr -dr com.apple.quarantine /Applications/NotePad.app
     ```

You only need to do this once. Each release also has a `.sha256` checksum file. To check a download:

```bash
shasum -a 256 -c NotePad-<version>-macos.dmg.sha256
```

NotePad is not yet signed with an Apple Developer ID or notarized by Apple. That is why macOS shows this warning.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or the Command Line Tools)

## Build and run

```bash
swift build
Scripts/bundle.sh release     # builds build/NotePad.app
open build/NotePad.app
```

## Publish a release

Push a version tag. The `Release` workflow tests the code, builds the app, and attaches the DMG, the zip and their checksums to a new GitHub release.

```bash
git tag v1.1.0
git push origin v1.1.0
```

You can also run the workflow by hand from the Actions tab to produce a build without publishing a release.

## Test

```bash
swift test
```

## Project layout

- `Sources/NotePadCore`: file I/O, session store, find, formatting and counts (no UI)
- `Sources/MarkdownRendering`: Markdown preview and styling
- `Sources/NotePad`: the AppKit editor and SwiftUI interface
- `Tests/`: unit tests
- `docs/superpowers/`: design spec, implementation plan and verification log

## License

MIT. See [LICENSE](LICENSE).
