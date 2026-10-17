#!/usr/bin/env bash
# Builds large Markdown documents for speed testing by repeating the syntax guide.
set -euo pipefail
cd "$(dirname "$0")/../TestDocuments"
build() { # build <copies> <output file>
    : > "$2"
    for _ in $(seq "$1"); do cat markdown-syntax-guide.md >> "$2"; printf '\n\n' >> "$2"; done
}
build 100 large-1MB.md
build 1000 large-10MB.md

# A code-heavy document: the every-language sample repeated, then 500-line blocks and one
# 5,000-line block, with a paragraph before each.
code_block() { # code_block <language> <lines>
    printf '```%s\n' "$1"
    for i in $(seq "$2"); do printf 'def step_%d(value, limit=10):\n    return value * %d if value < limit else None  # %d\n' "$i" "$i" "$i"; done
    printf '```\n\n'
}
{
    for _ in $(seq 360); do cat code-languages.md; printf '\n\n'; done
    for n in 1 2 3 4 5; do printf 'A paragraph before big block %d.\n\n' "$n"; code_block python 250; done
    printf 'A paragraph before the giant block.\n\n'
    code_block python 2500
    printf 'The end.\n'
} > large-code.md
ls -lh large-*.md
