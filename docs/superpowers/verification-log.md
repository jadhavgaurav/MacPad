# NotePad Verification Log

Checked by running the release-candidate app (`Scripts/bundle.sh`) and driving it through the UI on macOS 27. Each row lists what was done and the result. Unit tests are listed separately.

## Verified in the running app

| Area | What was checked | Result |
|---|---|---|
| Find | Query count, Match case, Whole word, No results, Next and Previous wrap-around | Pass |
| Replace | Replace (current match) and Replace All | Pass |
| Go to Line | Valid line moves caret; out-of-range shows message | Pass |
| Formatting | Bold (Cmd+B), Italic (Cmd+I), Heading 1 (Cmd+Option+1), bulleted list (Cmd+Shift+8), Link (Cmd+K) | Pass (after fix, see below) |
| Formatting | Heading and list replace each other on one line | Pass (fixed) |
| Formatted view | Bold and italic inside list items styled | Pass (fixed) |
| Formatted view | "Style Markdown in all text files" styles Markdown in a .txt file | Pass |
| Preview | Toggle on, rendered output, scroll sync with editor | Pass |
| Zoom | Cmd+= to 110%, Cmd+- back to 100%, Cmd+0 reset | Pass |
| Word wrap | Long line wraps by default; Option+Command+W turns wrap off | Pass |
| Settings | Font picker, size stepper (14 pt), Style Markdown toggle | Pass |
| Encoding | Latin-1 file detected as Windows-1252 | Pass |
| Encoding | Reopen with UTF-8 on a Latin-1 file shows "isn't valid UTF-8" | Pass |
| Encoding | Save with UTF-8 with BOM writes EF BB BF before the text | Pass |
| Line endings | CRLF file shows CRLF; unicode file shows LF | Pass |
| Counts | Unicode text (emoji, accents, CJK) gives correct words and characters | Pass |
| Tabs | Right-click menu present; Close to the Right disabled on last tab | Pass |
| Tabs | Copy Path copies the full file path | Pass |
| Tabs | Drag to reorder | Pass |
| Files | Opening files from the command line and `open -a` | Pass |
| Earlier round | Unsaved prompt (Cancel, Don't Save), disk reload and conflict banner, quit and relaunch with unsaved text, force quit, corrupt session file, 2 MB file, Save As, light and dark mode, narrow and full-screen windows, Reduce Transparency, pointer cursors, scroll bar | Pass |

## Not verified or known issues

| Area | Status |
|---|---|
| Close Others and Close to the Right with unsaved tabs | Not run |
| Reveal in Finder | Not run |
| Dragging a file onto the Dock icon | Not run (`open -a` path verified instead) |
| Typing speed in very large files | Not measured |
| VoiceOver speech output | Needs a person to listen (labels checked in the accessibility tree) |
| Cmd+Q | Not run through automation (quit used an Apple event) |
| Known issue: `open -a` while the window is full screen | The window stayed on a black full-screen Space and could not be exited from the View menu. Relaunching the app fixed it. Not yet fixed. |

## Unit tests

- NotePadCoreTests: 119 tests in 11 suites, passing.
- MarkdownRenderingTests: 22 tests in 2 suites, passing.
- The Swift Testing macro plugin sometimes fails on the first run after a change and passes on a retry.
