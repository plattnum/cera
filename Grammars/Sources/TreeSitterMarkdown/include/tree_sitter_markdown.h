#ifndef TREE_SITTER_MARKDOWN_H
#define TREE_SITTER_MARKDOWN_H

typedef struct TSLanguage TSLanguage;

/// The markdown grammar, from tree-sitter-grammars/tree-sitter-markdown.
const TSLanguage *tree_sitter_markdown(void);

#endif
