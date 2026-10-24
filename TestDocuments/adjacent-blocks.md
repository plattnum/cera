Blocks With No Blank Line Between Them
======================================

Each block below starts on the line right after another block. Cera puts the usual gap above it, and everything drawn for the block (a list marker, a checkbox, an image, a table's grid, a code panel, a quote bar, a rule) must sit below that gap, lined up with the block's own text. Compare each section with the last one, where blank lines separate the same blocks.

Put the cursor on this line first, so none of the lines below shows its Markdown.

## Lists and checkboxes
- [x] A bullet task
1. [ ] A numbered task right after it
2. [x] Another numbered task

A paragraph, and on the very next line a list:
- [ ] A task right after a paragraph
- A plain bullet

## Tasks inside a quote
> - [ ] An open task inside a quote: a box, not a bullet
> - [x] A finished task inside a quote

## Image right after a heading
![Cera icon|120](../Design/icons/AppIcon-1024.png)

## Table right after a heading
| A | B |
|---|---|
| 1 | 2 |

## Table right after a paragraph
The paragraph stays a paragraph, with its **formatting**, and the table keeps its own header:
| A | B |
|---|---|
| 1 | 2 |

## Table right after a list item's text
- A list item, then a table:
  | A | B |
  |---|---|
  | 1 | 2 |

## Wide table right after a heading
| Column one | Column two | Column three | Column four | Column five | Column six | Column seven | Column eight |
|---|---|---|---|---|---|---|---|
| a long cell value here | another long cell value | more text in this cell | and more text here | still going on | almost there now | nearly done | done |

## Code right after a paragraph
A paragraph, then a fence on the next line:
```swift
let a = 1
```

## Quote right after a paragraph
A paragraph, then a quote on the next line:
> A quote

## Rule right after a paragraph
A paragraph, then a rule on the next line:
***
After the rule.

## The same blocks with blank lines, for comparison

- [x] A bullet task

1. [ ] A numbered task

![Cera icon|120](../Design/icons/AppIcon-1024.png)

| A | B |
|---|---|
| 1 | 2 |

```swift
let a = 1
```

> A quote

***

The end.
