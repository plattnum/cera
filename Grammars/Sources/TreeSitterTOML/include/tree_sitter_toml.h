#ifndef TREE_SITTER_TOML_H
#define TREE_SITTER_TOML_H

typedef struct TSLanguage TSLanguage;

/// The toml grammar, from tree-sitter-grammars/tree-sitter-toml.
const TSLanguage *tree_sitter_toml(void);

#endif
