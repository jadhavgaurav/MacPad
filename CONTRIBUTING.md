# Contributing to MacPad

Thanks for helping. Before you start:

1. Open an issue first for anything bigger than a small fix, so we can agree on the approach.
2. Build and test on macOS 14 or later: `swift build` and `swift test`.
3. Keep the code consistent with the existing style. Strict lint must pass:
   `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint lint --strict` (set `TOOLCHAIN_DIR` to your Xcode or Command Line Tools path).
4. Add or update unit tests in `Tests/` for logic changes. Logic belongs in `NotePadCore` so it can be tested without the UI.
5. Commit messages use a short prefix: `feat:`, `fix:`, `docs:`, `style:`, `build:`.

Pull requests should describe what changed and how you tested it.
