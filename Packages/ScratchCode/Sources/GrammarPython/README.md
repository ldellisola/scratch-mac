# GrammarPython

The Python grammar for tree-sitter, vendored: unchanged copies of `src/parser.c`, `src/scanner.c`,
`src/tree_sitter/*.h` and `LICENSE` from https://github.com/tree-sitter/tree-sitter-python at tag `v0.25.0` (commit
`293fdc02038ee2bf0e2e206711b69c90ac0d413f`), MIT licence. `include/tree_sitter_python.h` is the grammar's
`bindings/swift/TreeSitterPython/python.h`.

It is vendored and not a package dependency because the grammar's own `Package.swift` adds `src/scanner.c` only when
`FileManager.default.fileExists(atPath: "src/scanner.c")`, a relative path, and SwiftPM evaluates a dependency's manifest in
the working directory of whoever builds, so the scanner is left out and linking fails with undefined
`tree_sitter_python_external_scanner_*` symbols. See docs/decisions/0007-tree-sitter.md.
