; Highlights for C++, from https://github.com/tree-sitter/tree-sitter-cpp v0.23.4 (queries/highlights.scm).
; MIT License, Copyright (c) 2014 Max Brunsfeld. https://github.com/tree-sitter/tree-sitter-cpp/blob/v0.23.4/LICENSE
; Changed for Scratch: the `; inherits: c` line below: the grammar's query is the C++ addition to C's.
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.
; inherits: c

; Functions

(call_expression
  function: (qualified_identifier
    name: (identifier) @function))

(template_function
  name: (identifier) @function)

(template_method
  name: (field_identifier) @function)

(template_function
  name: (identifier) @function)

(function_declarator
  declarator: (qualified_identifier
    name: (identifier) @function))

(function_declarator
  declarator: (field_identifier) @function)

; Types

((namespace_identifier) @type
 (#match? @type "^[A-Z]"))

(auto) @type

; Constants

(this) @variable.builtin
(null "nullptr" @constant)

; Keywords

[
 "catch"
 "class"
 "co_await"
 "co_return"
 "co_yield"
 "constexpr"
 "constinit"
 "consteval"
 "delete"
 "explicit"
 "final"
 "friend"
 "mutable"
 "namespace"
 "noexcept"
 "new"
 "override"
 "private"
 "protected"
 "public"
 "template"
 "throw"
 "try"
 "typename"
 "using"
 "concept"
 "requires"
 "virtual"
] @keyword

; Strings

(raw_string_literal) @string
