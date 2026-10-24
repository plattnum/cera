# Changelog

What's new in each version of Cera. A release's notes on GitHub are its section here.

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
