; Highlights for YAML, from https://github.com/tree-sitter-grammars/tree-sitter-yaml v0.7.0 (queries/highlights.scm).
; MIT License, Copyright (c) 2024 tree-sitter-grammars contributors, Copyright (c) 2019-2021 Ika. https://github.com/tree-sitter-grammars/tree-sitter-yaml/blob/v0.7.0/LICENSE
; Changed for Scratch: the keys of a mapping are `@type` (they were `@property`, which has no colour, so a key came out as the
;   string it also is).
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.

(boolean_scalar) @boolean

(null_scalar) @constant.builtin

[
  (double_quote_scalar)
  (single_quote_scalar)
  (block_scalar)
  (string_scalar)
] @string

[
  (integer_scalar)
  (float_scalar)
] @number

(comment) @comment

[
  (anchor_name)
  (alias_name)
] @label

(tag) @type

[
  (yaml_directive)
  (tag_directive)
  (reserved_directive)
] @attribute

(block_mapping_pair
  key: (flow_node
    [
      (double_quote_scalar)
      (single_quote_scalar)
    ] @type))

(block_mapping_pair
  key: (flow_node
    (plain_scalar
      (string_scalar) @type)))

(flow_mapping
  (_
    key: (flow_node
      [
        (double_quote_scalar)
        (single_quote_scalar)
      ] @type)))

(flow_mapping
  (_
    key: (flow_node
      (plain_scalar
        (string_scalar) @type))))

[
  ","
  "-"
  ":"
  ">"
  "?"
  "|"
] @punctuation.delimiter

[
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

[
  "*"
  "&"
  "---"
  "..."
] @punctuation.special
