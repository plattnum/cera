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
ls -lh large-*.md
