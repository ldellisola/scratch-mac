; Highlights for JSON, from https://github.com/tree-sitter/tree-sitter-json v0.24.8 (queries/highlights.scm).
; MIT License, Copyright (c) 2014 Max Brunsfeld. https://github.com/tree-sitter/tree-sitter-json/blob/v0.24.8/LICENSE
; Copied unchanged.
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.

(pair
  key: (_) @string.special.key)

(string) @string

(number) @number

[
  (null)
  (true)
  (false)
] @constant.builtin

(escape_sequence) @escape

(comment) @comment
