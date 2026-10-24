# Test documents

Files for checking how Cera renders Markdown. Open any of them in Cera.

- `features.md`: every feature Cera renders, in one short document.
- `adjacent-blocks.md`: each kind of block on the line right after another block, with no blank line between
  them, where list markers, checkboxes, images, tables, code panels, quote bars, and rules must still line up.
- `front-matter.md`: YAML front matter at the top of a file, and things to try with it.
- `code-languages.md`: a realistic example in each language syntax highlighting covers, for checking every color.
- `mermaid.md`: every kind of Mermaid diagram Cera draws, nested diagrams, and blocks that stay code.
- `markdown-syntax-guide.md`: John Gruber's Markdown syntax guide as a test page, from
  [mxstbr/markdown-test-file](https://github.com/mxstbr/markdown-test-file) (MIT License).
- `large-1MB.md`, `large-10MB.md`: large documents for checking speed. They aren't
  stored in the repository; create them with `scripts/make-large-docs.sh`.
