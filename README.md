# Cera

**Notepad for Markdown on the Mac.** Double-click a `.md` file, read it beautifully rendered, fix a line, save, close.

Cera is a quick WYSIWYG Markdown viewer and editor for macOS. Markdown renders as you type: headings, bold, italic, code, links, lists, and checkboxes look like a finished document, and the syntax markers appear only on the line you are editing. Files stay plain `.md` text.

Pick a look from the **Themes** menu: Midnight (dark), Plain, Broadsheet, Airy, Ivory, and Grotesk. Each theme sets its own fonts, colors, column width, heading style, and spacing. Code blocks are syntax-highlighted for common languages (shell, Python, JavaScript/TypeScript, Swift, Rust, Go, C-family, YAML/TOML).

Written in Swift with SwiftUI for the window and AppKit's `NSTextView` for editing. Requires macOS 15 or later.

## What Cera is, and isn't

Cera is for **one file at a time**: the README in a repository, meeting notes someone sent you, a quick draft, a one-off document. It opens instantly, stays out of the way, and works on the file where it lives.

It is **not** a second brain. It does not replace Obsidian, Bear, Logseq, or other note-taking systems and their excellent features. There are no vaults, no folder or project sidebar, no backlinks, tags, or sync. That's deliberate: like Notepad, it opens a file, and that's the whole model. If you want a knowledge base, use one of those tools. If you just want to open a Markdown file and have it look right, use Cera.

## Requirements

- macOS 15 or later.
- Xcode 16 or later (or its Command Line Tools), for Swift 5.9+ and the macOS SDK.
  Check with `swift --version`.

## Build and run

```sh
git clone git@github.com:plattnum/cera.git
cd cera
./scripts/bundle.sh           # builds build/Cera.app (release build, ad-hoc signed)
open build/Cera.app
```

The first build downloads the one dependency, Apple's
[swift-markdown](https://github.com/swiftlang/swift-markdown), and takes a minute.

To develop in Xcode, open the package: `open -a Xcode Package.swift`, choose the **Cera**
scheme with **My Mac**, and press ⌘R. (Xcode runs the bare executable; use
`scripts/bundle.sh` for a full app with its icon and Finder integration.)

## Install

**Homebrew:**

```sh
brew install --cask plattnum/cera/cera
```

**Download:** get `Cera.zip` from the
[latest release](https://github.com/plattnum/cera/releases/latest), unzip it, and move
`Cera.app` to Applications. See [Opening a downloaded build](#opening-a-downloaded-build)
for the first launch.

**From source:**

```sh
./scripts/bundle.sh
cp -R build/Cera.app /Applications/
```

Then open Cera from Spotlight, Launchpad, or Finder, and use **Open With ▸ Cera** on any
`.md` file. Re-run both commands to update.

## Tests

```sh
swift test                                                       # unit tests
CERA_STRESS_SEEDS=30 swift test --filter testStressIncrementalEdits # random-edit stress test
./scripts/make-large-docs.sh                                     # creates 1 MB and 10 MB test files
CERA_PERF_FILE=TestDocuments/markdown-syntax-guide.md swift test -c release --filter PerformanceTests
CERA_RENDER_DIR=/tmp swift test --filter RenderPreviewTests       # renders each theme to window-<theme>.png
```

`TestDocuments/` holds Markdown files for checking rendering by eye.

## Builds on GitHub

Every push to `main` runs `.github/workflows/build.yml` on a GitHub-hosted Mac: it runs the
tests, builds the app, and attaches `Cera.zip` to the run (Actions tab ▸ the run ▸
Artifacts).

To publish a release, tag a version and push the tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The workflow then creates a GitHub Release with `Cera.zip` attached.

### Opening a downloaded build

Builds are signed ad hoc, not with an Apple Developer ID, so macOS blocks a *downloaded*
copy the first time it is opened. After unzipping, either right-click **Cera.app ▸ Open**
and confirm, or allow it under **System Settings ▸ Privacy & Security ▸ Open Anyway**.
Removing the download flag also works:

```sh
xattr -dr com.apple.quarantine /Applications/Cera.app
```

Builds made on your own Mac are not affected.

## Features

- Live rendering, parsed with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (CommonMark plus GitHub tables, task lists, and strikethrough): headings (`#` and underlined), bold, italic, strikethrough, inline code, fenced and indented code blocks, links, autolinks, nested quotes, nested bullet and numbered lists, task checkboxes, horizontal rules, tables (with column alignment), and images.
- Images on their own line are drawn in place, scaled to fit. Local paths are resolved relative to the document; web images load in the background.
- Add images by dragging files onto the page, pasting (⌘V, including screenshots), or Format ▸ Image… (⌃⌘I). An image already in the document's folder is linked by relative path; one from anywhere else is copied into an `assets/` folder next to the document. Untitled documents link files by absolute path, and pasted screenshots need the document saved first.
- Links open with ⌘-click (or right-click ▸ Open Link). A plain click edits the link text.
- Return continues lists and quotes; Return on an empty item ends the list.
- Select text and a floating format bar appears: bold, italic, strikethrough, code, link, heading, quote, lists, and clear formatting.
- Format menu: Bold (⌘B), Italic (⌘I), Strikethrough (⇧⌘X), Inline Code (⌘E), Link (⌘K), Clear Formatting (⌘\); Heading ▸ Paragraph (⌘0), Heading 1–6 (⌘1–⌘6), larger/smaller (⌘= / ⌘-); List ▸ Bulleted (⌥⌘U), Numbered (⌥⌘O), Task (⌥⌘X), Indent/Outdent (⌘] / ⌘[, or Tab / Shift-Tab in a list); Quote (⌥⌘Q); Insert ▸ Image… (⌃⌘I), Table (⌥⌘T), Code Block (⌥⌘C), Horizontal Rule (⌥⌘-). Each command applies to every selected line and toggles off when applied again.
- File ▸ Open Recent remembers the last 10 files.
- Hard-wrapped paragraphs keep their line breaks, like Typora. View ▸ Flow Hard-Wrapped Paragraphs joins them into full paragraphs instead (the paragraph you're editing still shows its real line breaks).
- Built for large files: typing only restyles the blocks around the edit, and a big file shows its first screen right away while the rest is styled in the background. On a 10 MB document a keystroke costs about 10 ms.
- New, Open, Save, and Save As. New and Open ask before discarding unsaved changes.
- Spell checking is off by default; turn it on with Edit ▸ Check Spelling While Typing. Autocorrect is always off.

## Layout

- `Sources/Cera/CeraApp.swift`: app entry point and menu commands
- `Sources/Cera/ContentView.swift`: window contents, theme, and title bar
- `Sources/Cera/DocumentModel.swift`: document text, file I/O, and unsaved-change handling
- `Sources/Cera/MarkdownEditor.swift`: bridge between SwiftUI and the text view
- `Sources/Cera/MarkdownTextView.swift`: editing behavior (Return, formatting)
- `Sources/Cera/MarkdownStyler.swift`: parses the document and styles each element, a region at a time
- `Sources/Cera/LiveStyler.swift`: keeps styling current while editing, restyling only what changed
- `Sources/Cera/FormatCommands.swift`, `FormatBar.swift`: heading, list, quote, and insert commands, and the floating format bar
- `Sources/Cera/RecentDocuments.swift`: File ▸ Open Recent
- `Sources/Cera/SourceMap.swift`: maps parser positions to text offsets
- `Sources/Cera/ImageStore.swift`: loads and caches images
- `Sources/Cera/ImageImporter.swift`: decides image paths and copies images into `assets/`
- `Sources/Cera/LinkResolver.swift`: turns link destinations into openable URLs
- `Sources/Cera/MarkdownLayoutManager.swift`: draws bullets, checkboxes, code panels, quote bars, and rules
- `Sources/Cera/Theme.swift`: fonts, colors, and layout for each theme
- `Sources/Cera/CodeHighlighter.swift`: syntax colors inside fenced code blocks
- `Sources/Cera/FontRegistry.swift`: loads the bundled theme fonts
- `Sources/Cera/Resources/Fonts/`: PT Serif, Merriweather, Lato, Vollkorn, Open Sans (SIL Open Font License) and TeX Gyre Adventor (GUST Font License), with their license files
- `Tests/CeraTests/`: tests that run against a real text view

## Known limitations

- There is no autosave. Save with ⌘S.
- Closing a window with unsaved changes does not prompt.
- No export (HTML, PDF), no outline view, no source-only mode yet.
- A table row shows its Markdown source while the cursor is on it; table cells don't wrap.
- An image inside a line of text shows its alt text instead of the picture.
- Raw HTML is shown as dimmed source, not rendered.
