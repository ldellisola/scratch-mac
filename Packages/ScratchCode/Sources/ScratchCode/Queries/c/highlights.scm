; Highlights for C, from https://github.com/tree-sitter/tree-sitter-c v0.24.2 (queries/highlights.scm).
; MIT License, Copyright (c) 2014 Max Brunsfeld. https://github.com/tree-sitter/tree-sitter-c/blob/v0.24.2/LICENSE
; Changed for Scratch: the preprocessor directives are `@preproc` and `@include` (they were `@keyword`), a character literal is
;   a `@string` (it was a `@number`) and NULL is a `@constant.builtin`.
; Scratch maps the capture names to its eight colours in CaptureMapping.swift.

(identifier) @variable

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

"break" @keyword
"case" @keyword
"const" @keyword
"continue" @keyword
"default" @keyword
"do" @keyword
"else" @keyword
"enum" @keyword
"extern" @keyword
"for" @keyword
"if" @keyword
"inline" @keyword
"return" @keyword
"sizeof" @keyword
"static" @keyword
"struct" @keyword
"switch" @keyword
"typedef" @keyword
"union" @keyword
"volatile" @keyword
"while" @keyword

"#define" @preproc
"#elif" @preproc
"#else" @preproc
"#endif" @preproc
"#if" @preproc
"#ifdef" @preproc
"#ifndef" @preproc
"#include" @include
(preproc_directive) @preproc

"--" @operator
"-" @operator
"-=" @operator
"->" @operator
"=" @operator
"!=" @operator
"*" @operator
"&" @operator
"&&" @operator
"+" @operator
"++" @operator
"+=" @operator
"<" @operator
"==" @operator
">" @operator
"||" @operator

"." @delimiter
";" @delimiter

(string_literal) @string
(system_lib_string) @string

(null) @constant.builtin
(number_literal) @number
(char_literal) @string

(field_identifier) @property
(statement_identifier) @label
(type_identifier) @type
(primitive_type) @type
(sized_type_specifier) @type

(call_expression
  function: (identifier) @function)
(call_expression
  function: (field_expression
    field: (field_identifier) @function))
(function_declarator
  declarator: (identifier) @function)
(preproc_function_def
  name: (identifier) @function.special)

(comment) @comment
