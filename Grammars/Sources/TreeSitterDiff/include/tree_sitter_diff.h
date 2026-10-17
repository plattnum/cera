#ifndef TREE_SITTER_DIFF_H
#define TREE_SITTER_DIFF_H

typedef struct TSLanguage TSLanguage;

/// The diff grammar, from tree-sitter-grammars/tree-sitter-diff.
const TSLanguage *tree_sitter_diff(void);

#endif
