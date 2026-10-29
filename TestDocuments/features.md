---
title: Cera Feature Tour
tags: [markdown, test]
---
Cera Feature Tour
=================

Every Markdown feature Cera renders, in one place. Move the cursor onto a line to see its Markdown; move away and it renders again. The status bar at the bottom shows the file's name (click it to copy the name or path), the line, column, and word count, and the selection's.

The muted lines at the very top are front matter, metadata for tools like Jekyll, Hugo and Obsidian. Cera shows it as source and leaves it out of the document.

## Text

Plain text with **bold**, *italic*, ***bold italic***, ~~strikethrough~~, and `inline code`.
A line ending in two spaces  
makes a line break, and \*escaped\* characters stay literal.

## Headings

# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6

Underlined heading
------------------

### A heading with `inline code`

Inline code in a heading grows with the heading, like `this` in body text, and keeps its own letter spacing and letters.

## Links

- Inline: [Cera on the web](https://example.com "A title")
- Reference: [the CommonMark spec][spec]
- Autolink: <https://commonmark.org>
- Bare address: https://github.com
- Relative file: [the syntax guide](markdown-syntax-guide.md)

⌘-click a link to open it. To make one, select some text and paste a URL over it: the text becomes `[text](url)`. Paste and Match Style (⇧⌘V) pastes the URL as it is. Copy from a web page, Google Docs, or Slack and paste: headings, emphasis, links, lists, code, quotes, and tables come in as Markdown; ⇧⌘V pastes the plain text.

[spec]: https://spec.commonmark.org

## Lists

- Bullets
- With nesting
  - Second level
    - Third level
- Back to the top

3. Numbered lists
4. Can start at any number
5. And keep counting

## Checkboxes

Click a box to check or uncheck it; ⌘Z undoes it. ⌘L (Format ▸ List ▸ Toggle Checked) does the same for the line you are on.

- [ ] An open task
- [x] A finished task
- [X] Finished with a capital X
- [x] A task with **formatting** and a [link](https://example.com)
  - [x] A nested task
  - [x] A nested finished task
1. [ ] A numbered task
2. [x] A numbered finished task

> - [ ] A task inside a quote

## Quotes

> A quote with **formatting**.
>
> > And a nested quote inside it.
>
> - Even a list

## Callouts

A quote that starts with `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` is a callout. `callouts.md` has every type.

> [!TIP]
> A callout with **formatting**.

> [!WARNING] A callout with its own title
> And a body.

## Code

```swift
// A fenced block with a language gets syntax colors.
let greeting = "Hello, Cera"
print(greeting, 42)
```

```bash
# Shell comments are highlighted too
echo "done" && exit 0
```

    An indented code block,
    four spaces in.

## Table

| Feature  | Status | Notes            |
|:---------|:------:|-----------------:|
| Tables   | **yes**| right-aligned    |
| Images   | yes    | `local` and web  |
| Tasks    | yes    | checkboxes       |

## Images

An image on its own line is drawn in place:

![Cera icon](../Design/icons/AppIcon-1024.png)

An image inside a sentence shows its alt text: ![inline picture](../Design/icons/AppIcon-1024.png).

---

## HTML

<div align="center">Raw HTML shows as dimmed source.</div>

## A hard-wrapped paragraph

This paragraph is hard-wrapped, the way many plain-text files are written,
with a line break every seventy characters or so. Cera keeps these line
breaks, like Typora; turn on View ▸ Flow Hard-Wrapped Paragraphs to join them.
