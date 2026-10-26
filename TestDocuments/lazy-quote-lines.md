# Lazy quote lines

A line right after a quote that doesn't start with `>` still belongs to the quote: Markdown calls it a lazy continuation line. A list item's next line can likewise skip its indentation, and a paragraph's next line can add some. Each case below comes as a pair, the same text written twice:

1. **With `>`** (or **Indented**, **Not indented**): the line starts the way the first one does.
2. **Lazy** (or **Indented**): the second line leaves out the `>` or indentation, or adds some.

Both should look the same. Put the cursor on this line first, so none of the lines below shows its Markdown.

## Inline code

> With `>`: a quote
> that has `code` (in brackets) here.

> Lazy: a quote
that has `code` (in brackets) here.

## Bold

> With `>`: a quote
> that has **bold** (in brackets) here.

> Lazy: a quote
that has **bold** (in brackets) here.

## Italic

> With `>`: a quote
> that has *italic* (in brackets) here.

> Lazy: a quote
that has *italic* (in brackets) here.

## Strikethrough

> With `>`: a quote
> that has ~~struck~~ (in brackets) here.

> Lazy: a quote
that has ~~struck~~ (in brackets) here.

## Link

> With `>`: a quote
> that has a [link](https://example.com) (in brackets) here.

> Lazy: a quote
that has a [link](https://example.com) (in brackets) here.

## Several on one line

> With `>`: a quote
> with `code`, **bold**, and *italic* (in brackets) here.

> Lazy: a quote
with `code`, **bold**, and *italic* (in brackets) here.

## Several lazy lines

> With `>`: a quote
> with `one` here,
> and `two` here.

> Lazy: a quote
with `one` here,
and `two` here.

## Nested quote

> > With `>`: a nested quote
> > that has `code` (in brackets) here.

> > Lazy: a nested quote
that has `code` (in brackets) here.

## Callout

> [!TIP]
> With `>`: a callout
> that has `code` (in brackets) here.

> [!TIP]
> Lazy: a callout
that has `code` (in brackets) here.

## List item

A list item's next line can skip its indentation the same way.

- Indented: a list item
  that has `code` (in brackets) here.

- Lazy: a list item
that has `code` (in brackets) here.

## Paragraph with an indented line

A paragraph's next line can also start with spaces, which Markdown ignores.

Not indented: a paragraph
that has `code` (in brackets) here.

Indented: a paragraph
   that has `code` (in brackets) here.
