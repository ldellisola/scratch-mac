; Highlights for HTML, from https://github.com/tree-sitter/tree-sitter-html v0.23.2 (queries/highlights.scm).
; MIT License, Copyright (c) 2014 Max Brunsfeld. https://github.com/tree-sitter/tree-sitter-html/blob/v0.23.2/LICENSE
; Changed for Scratch: `(quoted_attribute_value)` is a string too, so that the quotes are coloured with the value.
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.

(tag_name) @tag
(erroneous_end_tag_name) @tag.error
(doctype) @constant
(attribute_name) @attribute
(quoted_attribute_value) @string
(attribute_value) @string
(comment) @comment

[
  "<"
  ">"
  "</"
  "/>"
] @punctuation.bracket
