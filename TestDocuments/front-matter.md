---
title: Front Matter
description: YAML between --- lines, at the very start of the file, as Jekyll, Obsidian and docs sites write it.
tags: [cera, test]
date: 2026-10-24
draft: false
note: |
  A block value, with a ``` line that is not a code fence,
  and a # that is not a heading.
---
# Front Matter

The muted lines above are front matter: metadata for other tools. Cera shows them as source, in the code font, and leaves them out of the document. They aren't a rule or a heading, and the outline (⌃⌘S) doesn't list them.

The heading above sits right after the closing `---`, with no blank line, and still gets its gap.

Only the start of the file counts. This `---` below is a rule:

---

## Things to try

- Delete the closing `---` at the top: the block becomes Markdown again (a rule and a heading). Undo brings it back.
- Change the first line to `+++` and the closing line to `+++`: TOML front matter, as Hugo writes it, is front matter too.
- Close it with `...` instead of `---`, as YAML allows.
