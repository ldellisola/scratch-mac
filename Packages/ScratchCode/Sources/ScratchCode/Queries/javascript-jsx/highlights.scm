; Highlights for JSX (JavaScript), from https://github.com/tree-sitter/tree-sitter-javascript v0.23.1 (queries/highlights-jsx.scm).
; MIT License, Copyright (c) 2014 Max Brunsfeld. https://github.com/tree-sitter/tree-sitter-javascript/blob/v0.23.1/LICENSE
; Changed for Scratch: the `; inherits: javascript` line below: this file is the JSX addition to JavaScript's query.
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.
; inherits: javascript

(jsx_opening_element (identifier) @tag (#match? @tag "^[a-z][^.]*$"))
(jsx_closing_element (identifier) @tag (#match? @tag "^[a-z][^.]*$"))
(jsx_self_closing_element (identifier) @tag (#match? @tag "^[a-z][^.]*$"))

(jsx_attribute (property_identifier) @attribute)
(jsx_opening_element (["<" ">"]) @punctuation.bracket)
(jsx_closing_element (["</" ">"]) @punctuation.bracket)
(jsx_self_closing_element (["<" "/>"]) @punctuation.bracket)
