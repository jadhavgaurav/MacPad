# NotePad

A native macOS text editor that looks and works like Windows 11 Notepad, built with Swift, AppKit and SwiftUI.

- Open any plain-text or Markdown file in tabs
- Unsaved text survives quit and crashes. Every tab is restored until you close it.
- Find and replace, Go to Line, live counts (lines, words, characters)
- Encodings (UTF-8, UTF-8 with BOM, UTF-16, Windows-1252) and line endings (LF, CRLF, CR)
- Formatting toolbar, Formatted view, and a Markdown preview
- Liquid Glass chrome on macOS 26 and later, with a system-material fallback on macOS 14 and 15

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or the Command Line Tools)

## Build and run

```bash
swift build
Scripts/bundle.sh release     # builds build/NotePad.app
open build/NotePad.app
```

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
