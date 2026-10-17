# Cera

**Notepad for Markdown on the Mac.** Double-click a `.md` file, read it beautifully rendered, fix a line, save, close.

Cera is a quick WYSIWYG Markdown viewer and editor for macOS. Markdown renders as you type: headings, bold, italic, code, links, lists, and checkboxes look like a finished document, and the syntax markers appear only on the line you are editing. Files stay plain `.md` text.

Pick a look from the **Themes** menu: Midnight (dark), Plain, Broadsheet, Airy, Ivory, and Grotesk. Each theme sets its own fonts, colors, column width, heading style, and spacing. Code blocks are syntax-highlighted with [tree-sitter](https://tree-sitter.github.io/tree-sitter/), using each language's real grammar: Bash, C, C++, C#, CSS, Diff, Go, HTML, Java, JavaScript (and JSX), JSON, Kotlin, Markdown, Python, Ruby, Rust, SQL, Swift, TOML, TypeScript (and TSX), and YAML.

Written in Swift with SwiftUI for the window and AppKit's `NSTextView` for editing. Requires macOS 15 or later.

## What Cera is, and isn't

Cera is for **one file at a time**: the README in a repository, meeting notes someone sent you, a quick draft, a one-off document. It opens instantly, stays out of the way, and works on the file where it lives.

It is **not** a second brain. It does not replace Obsidian, Bear, Logseq, or other note-taking systems and their excellent features. There are no vaults, no folder or project sidebar, no backlinks, tags, or sync. That's deliberate: like Notepad, it opens a file, and that's the whole model. If you want a knowledge base, use one of those tools. If you just want to open a Markdown file and have it look right, use Cera.

## How it was made

To be upfront: Cera is mostly vibe coded. I wanted a quick and dirty Markdown viewer and editor for my Mac, and built it largely by directing an AI coding assistant rather than writing every line by hand. It has tests and I use it daily, but it hasn't had the scrutiny of a carefully engineered app. Expect rough edges, and keep backups of anything important.

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

The first build downloads the dependencies, Apple's
[swift-markdown](https://github.com/swiftlang/swift-markdown) and
[SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter) with the
[tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime (syntax highlighting), and compiles the
language grammars in `Grammars/`. It takes a couple of minutes.

### Syntax highlighting grammars

The tree-sitter grammars are copied into the repository, pinned to exact versions, by
`scripts/update-grammars.sh`: each grammar's generated C parser goes in `Grammars/Sources/`, built by
`Grammars/Package.swift`, and its highlight queries and license in `Sources/Cera/Resources/Queries/`.
`Grammars/grammars.lock` records the commit each came from. To add or update a grammar, edit the list at
the top of the script and run it, then add the language to `Sources/Cera/CodeLanguages.swift`.
`Sources/Cera/Resources/Queries/cera/` holds Cera's own small corrections to the upstream queries; the
script leaves it alone.

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
`Cera.app` to Applications. Releases are signed with a Developer ID and notarized by
Apple, so Cera opens like any other downloaded app.

**From source:**

```sh
./scripts/bundle.sh
cp -R build/Cera.app /Applications/
```

Then open Cera from Spotlight, Launchpad, or Finder, and use **Open With ▸ Cera** on any
`.md` file. To update, re-run `./scripts/bundle.sh`, then
`rm -rf /Applications/Cera.app && cp -R build/Cera.app /Applications/`.

### The `cera` terminal command

`cera notes.md` opens a file in Cera from the terminal (`cera a.md b.md` opens each in its
own window); a file that doesn't exist yet is created empty. `cera photo.png` opens an image
on its own (PNG, JPEG, GIF, HEIC, WebP, TIFF, or BMP), shown through a throwaway Markdown file
in `$TMPDIR`, so it's a quick image viewer from the terminal. Homebrew installs the command for you. For a source install, link it onto
your PATH once:

```sh
ln -sf /Applications/Cera.app/Contents/Resources/cera /usr/local/bin/cera   # or ~/.local/bin/cera
```

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

To publish a release, set the version in `Resources/Info.plist`, then tag it and push the tag:

```sh
git tag v0.3.0
git push origin v0.3.0
```

The workflow then signs Cera with the Developer ID, has Apple notarize it, creates a GitHub
Release with `Cera.zip` attached, and points the
[Homebrew cask](https://github.com/plattnum/homebrew-cera) at it. It stops if the tag
doesn't match the version in `Info.plist`. It uses these repository secrets:

- `DEVELOPER_ID_P12`: the Developer ID Application certificate and key, exported from
  Keychain Access as a `.p12` and base64-encoded
- `DEVELOPER_ID_P12_PASSWORD`: the password the `.p12` was exported with
- `NOTARY_APPLE_ID` and `NOTARY_PASSWORD`: an Apple ID on the team and an app-specific
  password for it
- `HOMEBREW_TAP_DEPLOY_KEY`: the private half of a deploy key with write access to
  `plattnum/homebrew-cera`

To make a signed, notarized build on your own Mac instead, save notary credentials once
with `xcrun notarytool store-credentials cera-notary --apple-id <you> --team-id <team>`,
then run `./scripts/bundle.sh --release`.

Builds from pushes to `main` are signed ad hoc, so macOS blocks a *downloaded* copy of one.
To open it anyway, remove the download flag:

```sh
xattr -dr com.apple.quarantine Cera.app
```

## Features

- Live rendering, parsed with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (CommonMark plus GitHub tables, task lists, and strikethrough): headings (`#` and underlined), bold, italic, strikethrough, inline code, fenced and indented code blocks, links, autolinks, nested quotes, nested bullet and numbered lists, task checkboxes, horizontal rules, tables (with column alignment), and images.
- Images on their own line are drawn in place, scaled to fit. Local paths are resolved relative to the document; web images load in the background.
- Size an image with Obsidian's pipe syntax: `![photo|300](photo.png)` shows it 300 points wide, keeping its shape, and `![photo|300x200](photo.png)` fits it inside that box. A size can enlarge a small image but never goes past the column width. Right-click an image's line for Image Size ▸ Small (300), Medium (500), Large (700), or Original Size, which writes the size into the Markdown for you.
- Add images by dragging files onto the page, pasting (⌘V, including screenshots), or Format ▸ Image… (⌃⌘I). An image already in the document's folder is linked by relative path; one from anywhere else is copied into an `assets/` folder next to the document. Untitled documents link files by absolute path, and pasted screenshots need the document saved first.
- Links open with ⌘-click (or right-click ▸ Open Link). A plain click edits the link text.
- Hover over a code block and a copy button appears in its corner; click it to copy just the code, without the fences (or the quote and list markers of a nested block). Right-click a code block for Copy Code.
- View ▸ Show Outline (⌃⌘S) opens a sidebar listing the document's headings. Click one to jump to it; the section you're reading stays highlighted as you scroll, and the list updates as you type or when the file changes on disk. New windows open with the outline shown or hidden as you last left it.
- Follows changes made to the open file on disk, such as an agent editing it: the window shows the new text within a moment, keeping the caret and the text in view in place. If the window has unsaved edits, a banner asks first: Keep Mine saves your version over the file, Load from Disk discards your edits. Saving over a changed file still brings up the system's "changed by another application" alert.
- Return continues lists and quotes; Return on an empty item ends the list.
- Code blocks are highlighted with tree-sitter, using each language's real grammar (see the list at the top), in every theme's colors: keywords, types, function names, strings, numbers, comments, constants, HTML tags, JSON and YAML keys, and added and removed lines in a diff. Code inside quotes and lists is highlighted too. Languages are recognized by their usual names and aliases after the fence (`py`, `js`, `ts`, `sh`, `rs`, `cs`, `c#`, `yml`…). A few other languages (PHP, Scala, Dart, and more) get simple keyword colors.
- Each code block shows its language in small text in its top-right corner; hovering swaps it for the copy button.
- Type ```` ``` ```` at the start of a line and a list of languages appears; type to narrow it (`py` finds Python), then Return or Tab to choose. Return also opens the block with its closing fence. Return straight away, without choosing, makes a plain block; Escape closes the list.
- Inside a fenced code block, typing works like a code editor: Return keeps the line's indentation (and never adds list bullets), Tab and Shift-Tab (or ⌘] and ⌘[) indent and outdent the selected lines, and Return after an opening fence such as ```` ```swift ```` adds the closing fence. The indent matches the block's own (tabs, or its smallest indent), or the language's usual one: a tab for Go; two spaces for JavaScript, TypeScript, Ruby, HTML, CSS, JSON, Markdown, and YAML; four otherwise. Code blocks inside quotes and lists keep their `>` markers and indentation.
- Select text and a floating format bar appears: bold, italic, strikethrough, code, link, heading, quote, lists, and clear formatting.
- Format menu: Bold (⌘B), Italic (⌘I), Strikethrough (⇧⌘X), Inline Code (⌘E), Link (⌘K), Clear Formatting (⌘\); Heading ▸ Paragraph (⌘0), Heading 1–6 (⌘1–⌘6), larger/smaller (⌘= / ⌘-); List ▸ Bulleted (⌥⌘U), Numbered (⌥⌘O), Task (⌥⌘X), Indent/Outdent (⌘] / ⌘[, or Tab / Shift-Tab in a list); Quote (⌥⌘Q); Insert ▸ Image… (⌃⌘I), Table (⌥⌘T), Code Block (⌥⌘C), Horizontal Rule (⌥⌘-). Each command applies to every selected line and toggles off when applied again.
- Hard-wrapped paragraphs keep their line breaks, like Typora. View ▸ Flow Hard-Wrapped Paragraphs joins them into full paragraphs instead (the paragraph you're editing still shows its real line breaks).
- Built for large files: typing only restyles the blocks around the edit, and a big file shows its first screen right away while the rest is styled in the background. On a 10 MB document a keystroke costs about 10 ms.
- Standard Mac document handling: each file opens in its own window, and changes save automatically. File ▸ New Tab (⌘T) opens a new document as a tab of the front window; Window ▸ Merge All Windows gathers open windows into tabs. To have every document open as a tab, set System Settings ▸ Desktop & Dock ▸ "Prefer tabs when opening documents" to Always. Click the window title to name a new document and choose where it's saved, or to rename, move, tag, or lock a saved one. File ▸ Open Recent, Duplicate, Rename, Move To, and Revert To (including earlier versions) work as in TextEdit; hold Option in the File menu for Save As.
- Spell checking is off by default; turn it on with Edit ▸ Check Spelling While Typing. Autocorrect is always off.

## Layout

- `Sources/Cera/CeraApp.swift`: app entry point and menu commands
- `Sources/Cera/ContentView.swift`: window contents and theme
- `Sources/Cera/MarkdownDocument.swift`: the Markdown file type, reading, and saving
- `Sources/Cera/MarkdownEditor.swift`: bridge between SwiftUI and the text view
- `Sources/Cera/MarkdownTextView.swift`: editing behavior (Return, formatting)
- `Sources/Cera/MarkdownStyler.swift`: parses the document and styles each element, a region at a time
- `Sources/Cera/LiveStyler.swift`: keeps styling current while editing, restyling only what changed
- `Sources/Cera/FormatCommands.swift`, `FormatBar.swift`, `InlineMarkup.swift`: heading, list, quote, insert, and clear-formatting commands, and the floating format bar
- `Sources/Cera/SourceMap.swift`: maps parser positions to text offsets
- `Sources/Cera/ImageStore.swift`: loads and caches images
- `Sources/Cera/ImageImporter.swift`: decides image paths and copies images into `assets/`
- `Sources/Cera/ImageSize.swift`: reads and rewrites an image's `|size`
- `Sources/Cera/DiskSync.swift`: watches the open file and reloads it when it changes on disk
- `Sources/Cera/Outline.swift`: the outline sidebar, and keeping the reading position when the text is laid out again
- `Sources/Cera/LinkResolver.swift`: turns link destinations into openable URLs
- `Sources/Cera/MarkdownLayoutManager.swift`: draws bullets, checkboxes, code panels, quote bars, and rules
- `Sources/Cera/Theme.swift`: fonts, colors, and layout for each theme
- `Sources/Cera/SyntaxHighlighter.swift`: tree-sitter syntax highlighting, and which theme color each kind of code gets
- `Sources/Cera/CodeLanguages.swift`: the highlighted languages, their names and aliases, grammars, and queries
- `Sources/Cera/CodeHighlighter.swift`: simple keyword colors for languages without a grammar
- `Sources/Cera/CodeEditing.swift`: Return, Tab, and closing fences inside code blocks
- `Sources/Cera/CodeLanguagePicker.swift`: the language list after ```` ``` ````
- `Grammars/`: the tree-sitter grammars, copied in by `scripts/update-grammars.sh`
- `Sources/Cera/Resources/Queries/`: each grammar's highlight queries and license
- `Sources/Cera/CodeCopy.swift`: the copy button on code blocks, and reading a block's code without its fences
- `Sources/Cera/FontRegistry.swift`: loads the bundled theme fonts
- `Sources/Cera/Resources/Fonts/`: PT Serif, Merriweather, Lato, Vollkorn, Open Sans (SIL Open Font License) and TeX Gyre Adventor (GUST Font License), with their license files
- `Tests/CeraTests/`: tests that run against a real text view

The app bundle carries the license notices of the libraries built into it in `Contents/Resources/Licenses/`,
and each grammar's license next to its queries.

## Known limitations

- No export (HTML, PDF), no source-only mode yet.
- A table row shows its Markdown source while the cursor is on it; table cells don't wrap.
- An image inside a line of text shows its alt text instead of the picture.
- Raw HTML is shown as dimmed source, not rendered.

## License

MIT. See [LICENSE](LICENSE). The bundled fonts keep their own licenses, included next to them in `Sources/Cera/Resources/Fonts/`.
