; Cera's corrections, applied after the grammar's own patterns.
; The grammar matches numbers with Lua patterns (%d), which only Neovim understands.
((literal) @number
  (#match? @number "^[-+]?[0-9]+$"))
((literal) @number
  (#match? @number "^[-+]?[0-9]*\\.[0-9]+$"))
