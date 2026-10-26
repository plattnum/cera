# Callouts

A quote whose first line is a marker such as `[!NOTE]` is an alert, also called a callout: GitHub draws it with a colored bar, an icon, and a label, and hides the marker. To any renderer that doesn't know alerts, it is an ordinary quote whose first line reads `[!NOTE]`, so every file here is still plain, valid Markdown.

Open this file next to other Markdown editors and compare. Each section says what to look for. Put the cursor on this line first, so none of the lines below shows its Markdown.

## The five types

> [!NOTE]
> Useful information that users should know, even when skimming content.

> [!TIP]
> Helpful advice for doing things better or more easily.

> [!IMPORTANT]
> Key information users need to know to achieve their goal.

> [!WARNING]
> Urgent info that needs immediate user attention to avoid problems.

> [!CAUTION]
> Advises about risks or negative outcomes of certain actions.

## Case doesn't matter

GitHub accepts the type in any case. All three below should look like the note above.

> [!note]
> Lowercase type.

> [!Note]
> Capitalized type.

> [!nOtE]
> Mixed case type.

## Longer bodies

> [!NOTE]
> A first paragraph that is long enough to wrap onto a second line in a normal window, so you can see the bar run the full height of the text and the wrapped line start under the first one, not under the marker.
>
> A second paragraph in the same alert, after a blank quoted line.
>
> And a third.

> [!TIP]
> A line written on two source lines
that continues without a `>` (a lazy continuation line). It still belongs to the alert.

## Formatting and blocks inside

> [!IMPORTANT]
> Text with **bold**, *italic*, ~~strikethrough~~, `inline code`, and a [link](https://example.com).
>
> - A bullet
> - Another bullet
>   - A nested bullet
>
> 1. A numbered item
> 2. Another numbered item
>
> - [ ] An open task
> - [x] A finished task

> [!WARNING]
> A code block inside an alert:
>
> ```bash
> rm -rf ./build
> ```
>
> A table inside an alert:
>
> | Setting | Value |
> |---------|-------|
> | Mode    | Strict |
> | Retries | 3     |

> [!CAUTION]
> A quote nested inside an alert:
>
> > The nested quote keeps its own plain bar.

## Next to each other

Two alerts separated by a blank line are two alerts:

> [!NOTE]
> The first.

> [!TIP]
> The second.

With no blank line between them, they are one quote, so the second marker is just text inside the first alert:

> [!NOTE]
> The first.
> [!TIP]
> Not a second alert.

An alert right after a paragraph, with no blank line:
> [!NOTE]
> An alert that starts on the line after a paragraph.

## More types

Beyond GitHub's five, these types have their own icon and color. The names after "also" work too. On GitHub they stay plain quotes.

> [!INFO]
> Info.

> [!TODO]
> Todo.

> [!ABSTRACT]
> Abstract, also `[!SUMMARY]` and `[!TLDR]`.

> [!SUCCESS]
> Success, also `[!CHECK]` and `[!DONE]`.

> [!QUESTION]
> Question, also `[!HELP]` and `[!FAQ]`.

> [!FAILURE]
> Failure, also `[!FAIL]` and `[!MISSING]`.

> [!DANGER]
> Danger, also `[!ERROR]`.

> [!BUG]
> Bug.

> [!EXAMPLE]
> Example.

> [!QUOTE]
> Quote, also `[!CITE]`.

Other names, labeled as typed:

> [!HINT]
> A tip.

> [!ATTENTION]
> A warning.

> [!TLDR]
> An abstract.

`[!IMPORTANT]` and `[!CAUTION]` keep GitHub's meaning and colors: purple and red, not another name for tip and warning.

A type no editor knows gets the note look, with the type as its label:

> [!RECIPE]
> An unknown type.

## Titles

Text after the marker on the same line is the title, in place of the type's name. GitHub leaves these as quotes.

> [!TIP] Save before you quit
> The body.

A title and no body makes a one-line banner:

> [!WARNING] Not tested on Windows

The marker alone, with no body, shows just the label:

> [!NOTE]

## Fold signs

A `-` or `+` after the type folds or opens a callout in some editors. Cera hides the sign and always shows the callout open.

> [!FAQ]- Why is the sky blue?
> Shown, not folded.

> [!NOTE]+
> Open, as always.

## Markers that stay plain quotes

Each quote below stays a plain quote, with its marker shown as text.

The marker on the second line instead of the first:

> Some text first.
> [!NOTE]
> Then the marker.

A space inside the brackets, or no `!`:

> [! NOTE]
> A space after the `!`.

> [NOTE]
> No `!`.

An escaped marker. It shows as the text `[!NOTE]`:

> \[!NOTE]
> Escaped with a backslash.

## Alerts inside other blocks

GitHub only draws alerts at the top level of the document, never inside a list or another quote. Cera draws them anywhere a quote can be.

- A list item with an alert inside it:

  > [!NOTE]
  > Inside a list item.

> A quote with an alert inside it:
>
> > [!WARNING]
> > Inside a quote.

> [!NOTE]
> A callout with a callout inside it:
>
> > [!TIP]
> > The inner one gets its own box, inside the outer one.
>
> And a plain quote inside it:
>
> > The plain quote keeps its own bar.

## Markers that must stay text

Inside code, a marker is never an alert.

```markdown
> [!NOTE]
> This is code, not an alert.
```

Inline: `> [!NOTE]` stays code.

A marker that is not in a quote is a plain paragraph:

[!NOTE]
Not in a quote.

## Editing

- Click into an alert, or arrow into it, to see its `>` and `[!NOTE]` marker; move the cursor out and the marker hides again.
- Change `NOTE` to `WARNING` and the color and label should follow as you type.
- Delete the `!` and the alert should turn back into a plain quote.
