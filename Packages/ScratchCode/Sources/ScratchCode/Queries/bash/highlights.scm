; Highlights for Bash, from https://github.com/tree-sitter/tree-sitter-bash v0.25.1 (queries/highlights.scm).
; MIT License, Copyright (c) 2017 Max Brunsfeld. https://github.com/tree-sitter/tree-sitter-bash/blob/v0.25.1/LICENSE
; Copied unchanged.
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.

[
  (string)
  (raw_string)
  (heredoc_body)
  (heredoc_start)
] @string

(command_name) @function

(variable_name) @property

[
  "case"
  "do"
  "done"
  "elif"
  "else"
  "esac"
  "export"
  "fi"
  "for"
  "function"
  "if"
  "in"
  "select"
  "then"
  "unset"
  "until"
  "while"
] @keyword

(comment) @comment

(function_definition name: (word) @function)

(file_descriptor) @number

[
  (command_substitution)
  (process_substitution)
  (expansion)
]@embedded

[
  "$"
  "&&"
  ">"
  ">>"
  "<"
  "|"
] @operator

(
  (command (_) @constant)
  (#match? @constant "^-")
)
