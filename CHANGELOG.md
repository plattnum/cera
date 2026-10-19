# Changelog

What's new in each version of Cera. A release's notes on GitHub are its section here.

## 0.6.1 (2026-10-19)

- **Wide tables scroll sideways.** A table too wide for the column used to be cut off at the right edge. Now it
  has its own horizontal scroll bar, so every column can be read. Scrolling up and down over the table still
  scrolls the page, and clicking a cell edits its row as before.
- **Markdown source view.** View ▸ Show Markdown Source (⌘/) shows the file as plain Markdown, with every marker
  visible, in the code font, and the syntax colored. Press ⌘/ again to go back to the rendered view. Only the
  view changes: the text, undo, and the cursor stay as they are. Each window keeps its own view, and new windows
  start as the last one was left.
