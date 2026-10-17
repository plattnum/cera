#ifndef TREE_SITTER_YAML_H
#define TREE_SITTER_YAML_H

typedef struct TSLanguage TSLanguage;

/// The yaml grammar, from tree-sitter-grammars/tree-sitter-yaml.
const TSLanguage *tree_sitter_yaml(void);

#endif
