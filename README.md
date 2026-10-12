# NotePad

A native macOS text editor that looks and works like Windows 11 Notepad, built with Swift, AppKit and SwiftUI.

- Open any plain-text or Markdown file in tabs
- Unsaved text survives quit and crashes. Every tab is restored until you close it.
- Find and replace, Go to Line, live counts (lines, words, characters)
- Encodings (UTF-8, UTF-8 with BOM, UTF-16, Windows-1252) and line endings (LF, CRLF, CR)
- Formatting toolbar, Formatted view, and a Markdown preview
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

Push a version tag. The `Release` workflow tests the code, builds the app, and attaches the zip and checksum to a new GitHub release.

```bash
git tag v1.0.0
git push origin v1.0.0
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
