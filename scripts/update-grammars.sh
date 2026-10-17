#!/usr/bin/env bash
# Copies the tree-sitter grammars Cera highlights with into the repository:
#   Grammars/Sources/TreeSitter<Name>/   each grammar's generated C parser (and scanner), built by Grammars/Package.swift
#   Sources/Cera/Resources/Queries/<name>/   its highlight queries and license
# Grammars are pinned below. To add or update one, edit the list and run this script.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# name | target | GitHub repository | tag or commit | parser folder | query files (comma-separated)
GRAMMARS=(
  "bash|TreeSitterBash|tree-sitter/tree-sitter-bash|v0.25.1|src|queries/highlights.scm"
  "c|TreeSitterC|tree-sitter/tree-sitter-c|v0.24.2|src|queries/highlights.scm"
  "cpp|TreeSitterCPP|tree-sitter/tree-sitter-cpp|v0.23.4|src|queries/highlights.scm"
  "c_sharp|TreeSitterCSharp|tree-sitter/tree-sitter-c-sharp|v0.23.5|src|queries/highlights.scm"
  "css|TreeSitterCSS|tree-sitter/tree-sitter-css|v0.25.0|src|queries/highlights.scm"
  "diff|TreeSitterDiff|tree-sitter-grammars/tree-sitter-diff|v0.2.0|src|queries/highlights.scm"
  "go|TreeSitterGo|tree-sitter/tree-sitter-go|v0.25.0|src|queries/highlights.scm"
  "html|TreeSitterHTML|tree-sitter/tree-sitter-html|v0.23.2|src|queries/highlights.scm"
  "java|TreeSitterJava|tree-sitter/tree-sitter-java|v0.23.5|src|queries/highlights.scm"
  "javascript|TreeSitterJavaScript|tree-sitter/tree-sitter-javascript|v0.25.0|src|queries/highlights.scm,queries/highlights-jsx.scm"
  "json|TreeSitterJSON|tree-sitter/tree-sitter-json|v0.24.8|src|queries/highlights.scm"
  "kotlin|TreeSitterKotlin|fwcd/tree-sitter-kotlin|0.3.8|src|queries/highlights.scm"
  "markdown|TreeSitterMarkdown|tree-sitter-grammars/tree-sitter-markdown|v0.5.3|tree-sitter-markdown/src|tree-sitter-markdown/queries/highlights.scm"
  "markdown_inline|TreeSitterMarkdownInline|tree-sitter-grammars/tree-sitter-markdown|v0.5.3|tree-sitter-markdown-inline/src|tree-sitter-markdown-inline/queries/highlights.scm"
  "python|TreeSitterPython|tree-sitter/tree-sitter-python|v0.25.0|src|queries/highlights.scm"
  "ruby|TreeSitterRuby|tree-sitter/tree-sitter-ruby|v0.23.1|src|queries/highlights.scm"
  "rust|TreeSitterRust|tree-sitter/tree-sitter-rust|v0.24.2|src|queries/highlights.scm"
  "sql|TreeSitterSQL|DerekStride/tree-sitter-sql|39fdb006403747241244326e8af3b3e96b85381c|src|queries/highlights.scm"
  "swift|TreeSitterSwift|alex-pinkus/tree-sitter-swift|0.7.4-with-generated-files|src|queries/highlights.scm"
  "toml|TreeSitterTOML|tree-sitter-grammars/tree-sitter-toml|v0.7.0|src|queries/highlights.scm"
  "tsx|TreeSitterTSX|tree-sitter/tree-sitter-typescript|v0.23.2|tsx/src|queries/highlights.scm"
  "typescript|TreeSitterTypeScript|tree-sitter/tree-sitter-typescript|v0.23.2|typescript/src|queries/highlights.scm"
  "yaml|TreeSitterYAML|tree-sitter-grammars/tree-sitter-yaml|v0.7.2|src|queries/highlights.scm"
)

# Fetches a repository at a tag or commit, once per repository and ref.
fetch() {
  local repo=$1 ref=$2 dest="$WORK/${1//\//_}@$2"
  if [[ ! -d $dest ]]; then
    git init -q "$dest"
    git -C "$dest" remote add origin "https://github.com/$repo.git"
    git -C "$dest" fetch -q --depth 1 origin "$ref" 2>/dev/null \
      || git -C "$dest" fetch -q --depth 1 origin "refs/tags/$ref"
    git -C "$dest" checkout -q FETCH_HEAD
  fi
  echo "$dest"
}

# Queries/cera holds Cera's own corrections to the queries; it is kept.
rm -rf Grammars/Sources
find Sources/Cera/Resources/Queries -mindepth 1 -maxdepth 1 -type d ! -name cera -exec rm -rf {} + 2>/dev/null || true
mkdir -p Grammars/Sources Sources/Cera/Resources/Queries
LOCK="Grammars/grammars.lock"
echo "# name  repository  ref  commit (written by scripts/update-grammars.sh)" > "$LOCK"
TARGETS=()

for entry in "${GRAMMARS[@]}"; do
  IFS='|' read -r name target repo ref parser queries <<< "$entry"
  echo "• $name ($repo @ $ref)"
  src=$(fetch "$repo" "$ref")
  echo "$name  $repo  $ref  $(git -C "$src" rev-parse HEAD)" >> "$LOCK"

  out="Grammars/Sources/$target"
  mkdir -p "$out/src/tree_sitter" "$out/include"
  cp "$src/$parser/parser.c" "$out/src/"
  [[ -f $src/$parser/scanner.c ]] && cp "$src/$parser/scanner.c" "$out/src/"
  cp "$src/$parser"/tree_sitter/*.h "$out/src/tree_sitter/"
  # Everything else a scanner might include from its folder, such as HTML's tag.h and YAML's schema
  # tables (YAML picks one with a macro). Only parser.c and scanner.c are compiled; copies of the
  # parser for older tree-sitter versions (Swift's parser_abi13.c) aren't needed.
  find "$src/$parser" -maxdepth 1 \( -name '*.c' -o -name '*.h' \) ! -name 'parser*.c' ! -name scanner.c -exec cp {} "$out/src/" \;
  # A scanner shared between grammars of one repository (TypeScript and TSX) lives outside the
  # parser folder; copy it in and point the include at the copy.
  if [[ -f $out/src/scanner.c ]] && grep -q '#include "\.\./\.\./common/' "$out/src/scanner.c"; then
    for header in $(grep -o '\.\./\.\./common/[A-Za-z_.]*' "$out/src/scanner.c" | sort -u); do
      cp "$src/$parser/$header" "$out/src/common_$(basename "$header")"
    done
    sed -i '' -E 's#"\.\./\.\./common/([A-Za-z_.]+)"#"common_\1"#' "$out/src/scanner.c"
  fi
  guard="TREE_SITTER_$(echo "$name" | tr '[:lower:]' '[:upper:]')_H"
  cat > "$out/include/tree_sitter_$name.h" <<EOF
#ifndef $guard
#define $guard

typedef struct TSLanguage TSLanguage;

/// The $name grammar, from $repo.
const TSLanguage *tree_sitter_$name(void);

#endif
EOF

  dest="Sources/Cera/Resources/Queries/$name"
  mkdir -p "$dest"
  IFS=',' read -ra files <<< "$queries"
  for file in "${files[@]}"; do cp "$src/$file" "$dest/$(basename "$file")"; done
  cp "$src/LICENSE" "$dest/LICENSE" 2>/dev/null || cp "$src"/LICENSE* "$dest/LICENSE"
  if [[ -f $out/src/scanner.c ]]; then TARGETS+=("$target|scanner"); else TARGETS+=("$target|"); fi
done

# The package that builds them: one C target per grammar, all in one library.
{
  echo "// swift-tools-version:5.9"
  echo "// Written by scripts/update-grammars.sh; edit the list there, not this file."
  echo "import PackageDescription"
  echo
  echo "/// Each grammar, and whether it has an external scanner. Only these files are compiled:"
  echo "/// a scanner may include other C files from its folder."
  echo "let grammars: [(name: String, hasScanner: Bool)] = ["
  for entry in "${TARGETS[@]}"; do
    IFS='|' read -r target scanner <<< "$entry"
    echo "    (\"$target\", $([[ -n $scanner ]] && echo true || echo false)),"
  done
  echo "]"
  echo
  echo "let package = Package("
  echo "    name: \"Grammars\","
  echo "    products: [.library(name: \"Grammars\", targets: grammars.map(\\.name))],"
  echo "    targets: grammars.map { grammar in"
  echo "        .target(name: grammar.name, path: \"Sources/\\(grammar.name)\","
  echo "                sources: grammar.hasScanner ? [\"src/parser.c\", \"src/scanner.c\"] : [\"src/parser.c\"],"
  echo "                cSettings: [.headerSearchPath(\"src\"), .unsafeFlags([\"-w\"])])"
  echo "    },"
  echo "    cLanguageStandard: .c11"
  echo ")"
} > Grammars/Package.swift

echo "Done: ${#TARGETS[@]} grammars. Pinned commits are in $LOCK."
