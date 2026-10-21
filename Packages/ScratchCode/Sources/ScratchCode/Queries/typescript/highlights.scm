; Highlights for TypeScript, from https://github.com/tree-sitter/tree-sitter-typescript v0.23.2 (queries/highlights.scm).
; MIT License, Copyright (c) 2017 Max Brunsfeld. https://github.com/tree-sitter/tree-sitter-typescript/blob/v0.23.2/LICENSE
; Changed for Scratch: the `; inherits: javascript` line below: the grammar's query is the TypeScript addition to JavaScript's.
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.
; inherits: javascript

; Types

(type_identifier) @type
(predefined_type) @type.builtin

((identifier) @type
 (#match? @type "^[A-Z]"))

(type_arguments
  "<" @punctuation.bracket
  ">" @punctuation.bracket)

; Variables

(required_parameter (identifier) @variable.parameter)
(optional_parameter (identifier) @variable.parameter)

; Keywords

[ "abstract"
  "declare"
  "enum"
  "export"
  "implements"
  "interface"
  "keyof"
  "namespace"
  "private"
  "protected"
  "public"
  "type"
  "readonly"
  "override"
  "satisfies"
] @keyword
