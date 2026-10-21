# GrammarPowerShell

The PowerShell grammar for tree-sitter, vendored: unchanged copies of `src/parser.c`, `src/scanner.c`,
`src/tree_sitter/*.h` and `LICENSE` from https://github.com/airbus-cert/tree-sitter-powershell at tag `v0.26.5` (commit
`d398441825243b00e317e87e1829b9d6a3e54ce0`), MIT licence. `include/tree_sitter_powershell.h` is the grammar's
`bindings/swift/TreeSitterPowershell/powershell.h`.

It is vendored and not a package dependency because the grammar's own `Package.swift` adds `src/scanner.c` only when
`FileManager.default.fileExists(atPath: "src/scanner.c")`, a relative path, and SwiftPM evaluates a dependency's manifest in
the working directory of whoever builds, so the scanner is left out and linking fails with undefined
`tree_sitter_powershell_external_scanner_*` symbols (the same fault as GrammarPython's). No earlier tag has a
`Package.swift` at all. See docs/decisions/0007-tree-sitter.md.
