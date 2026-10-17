# Mermaid diagrams

Each ```` ```mermaid ```` block below should show as a diagram. Click into one, or arrow into it, to see and edit its code; move the cursor away and the diagram comes back. Switch themes to see the colors follow.

## Flowchart

```mermaid
flowchart TD
    A[Open a file] --> B{Is it Markdown?}
    B -->|Yes| C[Render it live]
    B -->|No| D[Show as plain text]
    C --> E((Done))
    D --> E
```

## Flowchart with groups, left to right

```mermaid
flowchart LR
    subgraph Disk
        F[(notes.md)] --> W[Watcher]
    end
    subgraph Editor
        T[Typing] --> S[Styler]
    end
    W --> S
    S --> V[What you see]
```

## Sequence diagram

```mermaid
sequenceDiagram
    participant U as You
    participant C as Cera
    participant A as Agent
    U->>C: Open notes.md
    A->>C: Edits the file on disk
    C-->>U: Shows the new text
    alt You have unsaved edits
        C->>U: Keep Mine or Load from Disk?
    else No edits
        C->>C: Reload quietly
    end
    Note over U,C: The cursor stays where it was
```

## Class diagram

```mermaid
classDiagram
    class MarkdownDocument {
        +String text
        +read(url)
        +write(url)
    }
    class OutlineModel {
        +items
        +jump(to)
    }
    OutlineModel --> MarkdownDocument : reads
```

## State diagram

```mermaid
stateDiagram-v2
    [*] --> Clean
    Clean --> Edited : type
    Edited --> Clean : save
    Edited --> Conflict : file changed on disk
    Conflict --> Clean : Load from Disk
    Conflict --> Clean : Keep Mine
```

## Entity relationship diagram

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : "is in"
    CUSTOMER {
        string name
        string email
    }
```

## Gantt chart

```mermaid
gantt
    title Cera 1.0
    dateFormat YYYY-MM-DD
    section Features
    Outline        :done,    a1, 2026-10-10, 5d
    Mermaid        :active,  a2, 2026-10-17, 7d
    section App Store
    Sandbox work   :         a3, after a2, 10d
```

## Pie chart

```mermaid
pie title Where the time goes
    "Writing" : 55
    "Editing" : 30
    "Fiddling with themes" : 15
```

## Mindmap

```mermaid
mindmap
  root((Cera))
    Editing
      Live rendering
      Format bar
    Reading
      Outline
      Themes
    Files
      Disk sync
      Tabs
```

## User journey

```mermaid
journey
    title Writing a README
    section Draft
      Open Cera: 5: Me
      Write the headings: 4: Me
    section Review
      Agent edits it: 3: Agent, Me
```

## Timeline

```mermaid
timeline
    title Cera releases
    0.3 : Signed and notarized
    0.4 : Outline sidebar : New Tab
    0.5 : Copy button : Mermaid diagrams
```

## A wide diagram

It shrinks to fit the column. Make the window narrower and it shrinks with it.

```mermaid
flowchart LR
    A[Write the first draft] --> B[Ask an agent to review it] --> C[Read the suggestions] --> D[Make the changes] --> E[Publish it]
```

## Nested in a quote and a list

> A diagram inside a quote:
>
> ```mermaid
> flowchart LR
>     Q[Quoted] --> R[Still drawn]
> ```

- A diagram inside a list item:

  ```mermaid
  flowchart LR
      L[Listed] --> M[Indented with the item]
  ```

## Other fence styles

Tildes, and the language name in capitals, work too:

~~~Mermaid
flowchart LR
    T[Tilde fence] --> U[Drawn]
~~~

## Blocks that stay code

A diagram with a syntax error stays a code block, so nothing is lost:

```mermaid
flowchart TD
    A[Unclosed bracket --> B
```

So does a type of diagram Cera doesn't know:

```mermaid
notADiagram
    this stays code
```

Mermaid's own colors (`classDef` and `style`) are ignored; the diagram uses the theme's colors:

```mermaid
flowchart LR
    A[Styled]:::hot --> B[Also styled]
    classDef hot fill:#f96,stroke:#333
    style B fill:#bbf
```

And a block that isn't Mermaid is just code:

```swift
let diagram = "not a diagram"
```
