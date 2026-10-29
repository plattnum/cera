# Changelog

What's new in each version of Cera. A release's notes on GitHub are its section here.

## 0.6.11 (2026-10-29)

- **Copy the file's name or path.** The status bar now shows the open file's name at the left; click it for Copy
  Name, Copy Path, and Reveal in Finder, to grab the name or the full path again without leaving the document.
  The same three are at the bottom of the File menu: Copy Name (⌃⇧⌘C) and Copy Path (⌥⇧⌘C, Finder's key for
  copying a pathname). An unsaved document reads Untitled, with the items disabled.

## 0.6.10 (2026-10-26)

- **Callouts.** A quote that starts with `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, or `[!CAUTION]`, the
  alert syntax common in GitHub READMEs, is drawn as a shaded box in the type's color with an icon and label,
  and the marker is hidden until you edit the line. As in common Markdown editors, more types work too (info,
  todo, abstract, success, question, failure, danger, bug, example, quote, and their other names), as does a
  title after the marker (`> [!TIP] Save first`). Callouts work inside lists, quotes, and other callouts, and
  code blocks and tables stay inside the box. Folding signs (`[!NOTE]-`) are accepted, but callouts always show
  open.
- **Fixed: tables inside quotes.** The quote's `>` was read as an extra column, which shifted every cell.
- **Fixed: markup on lines without their `>` or indentation.** A quote line that continues without `>`, or a list
  item line without its indentation, hid its bold, code, or link markers in the wrong place, showing some and
  hiding letters instead. Clear Formatting removed the wrong characters on those lines too.

## 0.6.9 (2026-10-25)

- **Lock Editing.** View ▸ Lock Editing (⌥⌘L), or the lock at the right of the title bar, makes a window a
  viewer: every line stays rendered, even the cursor's, and a plain click opens a link. Typing, pasting, image
  drops, and the Format menu do nothing, and a note says how to unlock. Text can still be selected, copied, and
  searched, and task boxes still tick. It's per window and off in new windows. A file you can't write to opens
  locked, and `cera -r notes.md` opens a file locked from the terminal.

## 0.6.8 (2026-10-25)

- **Paste rich text as Markdown.** Copy from a web page, Google Docs, Slack, or an email and paste: headings,
  bold, italic, strikethrough, code and code blocks, links, images, lists (nested, numbered, and checklists),
  quotes, and tables come in as Markdown instead of plain text. Colors and fonts are dropped, and characters
  like `*` and `#` in the copied text stay text. A copy from a code editor or Terminal, and anything pasted
  into code, still pastes as plain text, and Paste and Match Style (⇧⌘V) always does.
- **Status bar.** A quiet bar under the text shows the line and column of the cursor (`Ln 12, Col 5`) and the
  word count; with a selection, the selected characters and `9 of 1,234 words`. Words are the ones you read:
  front matter, link addresses, and Markdown symbols aren't counted. View ▸ Hide Status Bar hides it.

## 0.6.7 (2026-10-25)

- **Zoom.** View ▸ Zoom In (⌘=), Zoom Out (⌘−), and Actual Size (⌘0) make the document larger or smaller, as in
  a browser: text, spacing, checkboxes, tables, and images together. The level is the same in every window and
  is remembered.
- **Heading shortcuts moved.** To match common Markdown editors, ⌘=, ⌘−, and ⌘0 are now zoom. Format ▸ Heading ▸
  Paragraph is ⌃⌘0, Make Heading Larger ⌃⌘=, and Make Heading Smaller ⌃⌘−. Heading 1–6 stay on ⌘1–⌘6.
- **Fixed: inline code in headings.** Code in a heading was drawn at the body text size, small next to the
  heading. It now grows with the heading, and keeps its own letter spacing and letters in themes whose headings
  are spaced tighter or set in capitals.

## 0.6.6 (2026-10-25)

- **Paste a URL over selected text to make a link.** Select some text and paste a web link or `mailto:` address,
  and the text becomes `[text](url)`, as in Obsidian. It applies only when the clipboard is one link; anything
  else pastes as before, and so does a link pasted into code, an existing link, or front matter.
- **Paste and Match Style (⇧⌘V)**, new in the Edit menu, pastes the clipboard as plain text, so a link can
  still be pasted over a selection as it is.

## 0.6.5 (2026-10-24)

- **Front matter.** Metadata at the top of a file, YAML between `---` lines (Jekyll, Obsidian, docs sites) or
  TOML between `+++` lines (Hugo), used to show as a horizontal rule and a huge heading, and its first lines
  were listed in the outline. It now shows as muted source in the code font, still editable, and the document
  below it renders as usual. A `---` anywhere else, or with no closing line, is Markdown as before.

## 0.6.4 (2026-10-24)

- **Fixed: blocks right after another block.** When an image, table, code block, quote, or rule starts on the
  line right after another block, with no blank line between them, its picture, grid, panel, bar, or rule was
  drawn up in the gap above it: a table's border could cut through the heading above. They now sit below the
  gap, where they do after a blank line.
- **Fixed: a table right after a paragraph.** A table on the line after a paragraph took the paragraph as its
  header row, hid its real header, and showed the `|---|` line as a row. Now the paragraph stays a paragraph, with its
  formatting, and the table has its own header. The same goes for a table right after a list item's text.

## 0.6.3 (2026-10-24)

- **Click a checkbox to tick it.** Click a task's box to check or uncheck it, as in Obsidian; the pointer becomes
  a hand over a box, and ⌘Z undoes it. Format ▸ List ▸ Toggle Checked (⌘L, Obsidian's shortcut) does the same
  for the lines you're on, and turns a line that isn't a task into one.
- **Fixed: list markers drawn above their text.** A list right after another block, with no blank line between
  them, drew its first box, number, or bullet a line above its text. It now sits beside it.
- **Fixed: tasks inside quotes.** `> - [ ] task` showed a bullet instead of a checkbox.

## 0.6.2 (2026-10-21)

- **Links to headings work.** ⌘-click a `#section` link, such as an entry in a README's table of contents, and
  Cera jumps to that heading. Headings get the same anchors as on GitHub (`## Getting Started!` is
  `#getting-started`), and `#top` goes to the start of the document.
- **Linked Markdown files open in Cera.** ⌘-click a link to another `.md` file and it opens in Cera, not in
  whatever app macOS uses for Markdown; `guide.md#setup` opens it at that heading.

## 0.6.1 (2026-10-19)

- **Wide tables scroll sideways.** A table too wide for the column used to be cut off at the right edge. Now it
  has its own horizontal scroll bar, so every column can be read. Scrolling up and down over the table still
  scrolls the page, and clicking a cell edits its row as before.
- **Markdown source view.** View ▸ Show Markdown Source (⌘/) shows the file as plain Markdown, with every marker
  visible, in the code font, and the syntax colored. Press ⌘/ again to go back to the rendered view. Only the
  view changes: the text, undo, and the cursor stay as they are. Each window keeps its own view, and new windows
  start as the last one was left.
