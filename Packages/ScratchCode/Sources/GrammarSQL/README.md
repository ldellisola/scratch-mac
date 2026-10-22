# GrammarSQL

The SQL grammar for tree-sitter, vendored: unchanged copies of `src/parser.c` (41 MB), `src/scanner.c`,
`src/tree_sitter/*.h` and `LICENSE` from https://github.com/DerekStride/tree-sitter-sql, from the `gh-pages` branch at commit
`e038788e5d4daba82dea35676bf49a216629e141` ("deploy: 987a64a7b105e267b39725a81ad2db628dc3178c", the build of the `main` of
2026-10-17, 76 commits after the last release, 0.3.11), MIT licence. `include/tree_sitter_sql.h` is the grammar's
`bindings/swift/TreeSitterSql/sql.h`.

It is vendored and not a package dependency because the grammar's releases (its tags) have no generated sources: its
`.gitignore` lists `src/parser.c`, and the generated files exist only on the `gh-pages` branch, one commit for each build of
`main`. A dependency can reach them only with a `revision:` pin on such a commit, which is not a version
(`Package.swift` pins every other package with `exact:`) and which breaks the build, at resolution, if that commit ever
goes. Vendoring them means the build never depends on that branch (and never fetches its 150 MB of history).

`queries/highlights.scm` of the same commit is `Sources/ScratchCode/Queries/sql/highlights.scm`, with Scratch's changes
listed in its header. See docs/decisions/0007-tree-sitter.md.
