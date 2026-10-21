# 0007: tree-sitter, and the packages it comes in

Status: accepted, 2026-10-21. Spec §8.1 names tree-sitter as the highlighting engine and as the one significant
third-party dependency. This record fixes the packages, their versions and how they are used, and is the checklist for
adding a language. The wrapper, the package layout and the vendoring are [builder] calls inside §8.1.

## Decision

`Packages/ScratchCode` is a Swift package with no AppKit that builds and tests on Linux and macOS. It wraps tree-sitter
and gives the app `CodeLanguage`, `Highlighter` (text and a language in, UTF-16 token ranges out) and, in a later task of
Plan 4, `CodeDetector`. `ScratchCore` does not depend on it.

### The wrapper: `tree-sitter/swift-tree-sitter`

Plan 4 asked for this package (formerly ChimeHQ/SwiftTreeSitter) if its products build and pass the tests on both the
Linux job and the macOS job, and for a thin wrapper over the C API if they do not. It builds and passes on both (the
`linux` job's and the `macos` job's "ScratchCore and ScratchCode tests", and the hosted `HighlighterInAppTests` in the
app), so the thin wrapper was not written. What it gives: `Parser`, `Query` (which is `Sendable`, so one compiled query is shared by every
thread), the `#eq?`, `#not-eq?`, `#match?`, `#not-match?` predicates, and UTF-16 offsets for nodes. What `ScratchCode`
does not use: `SwiftTreeSitterLayer`, and `LanguageConfiguration`, which finds a grammar's queries through a
`<Name>_<Name>.bundle` folder next to the executable. SwiftPM calls that folder `.resources` on Linux, so the lookup
cannot work in the Linux tests (see "Queries" below).

Measured on Linux x86_64, a Release build, 500 lines of ordinary code, best of five: Swift 10 ms for the tokens (3.6 ms
of it the parse) and 3.6 ms for the error rate, Python 14 ms and 3.1 ms. The first use of a language compiles its query:
240 ms for Swift (the longest), 12 ms for Python. Both are far below the paste budget (§7: 50 ms), but the first Swift
paste after a launch would pay the 240 ms, so the app should compile the queries of the languages it expects on its
highlight queue before they are needed.

### Packages

Every package is pinned with `exact:`, the tree-sitter runtime included, which swift-tree-sitter would otherwise let
float within 0.25.x. The Xcode project is generated and never committed, so a `Package.resolved` next to it would not
survive: exact versions in `Packages/ScratchCode/Package.swift` are what keeps the app, CI and `swift test` on the same
code. `Packages/ScratchCode/Package.resolved` records the revisions.

| Package | URL | Version | Licence | Used as |
|---|---|---|---|---|
| swift-tree-sitter | https://github.com/tree-sitter/swift-tree-sitter | 0.25.0 | MIT | dependency (`SwiftTreeSitter`) |
| tree-sitter (the C runtime) | https://github.com/tree-sitter/tree-sitter | 0.25.10 | MIT | dependency (`TreeSitter`) |
| tree-sitter-swift (grammar) | https://github.com/alex-pinkus/tree-sitter-swift | 0.7.4-with-generated-files | MIT | dependency (`TreeSitterSwift`) |
| tree-sitter-python (grammar) | https://github.com/tree-sitter/tree-sitter-python | v0.25.0 | MIT | vendored (`Sources/GrammarPython`) |

tree-sitter-swift's repository has its generated `src/parser.c` (23 MB) on the `-with-generated-files` tags only, so the
dependency is pinned to one of those.

### Grammars whose own `Package.swift` cannot be a dependency are vendored

tree-sitter-python's `Package.swift` (the template `tree-sitter init` writes for every grammar with an external scanner)
adds `src/scanner.c` to the target only when `FileManager.default.fileExists(atPath: "src/scanner.c")`. That is a path
relative to the working directory, and SwiftPM evaluates a dependency's manifest in the working directory of whoever
builds, not in the dependency's folder. The check is false, the scanner is left out and linking fails with undefined
`tree_sitter_python_external_scanner_*` symbols (reproduced with a manifest that prints its working directory). So the
Python grammar's generated `parser.c`, `scanner.c`, `tree_sitter/*.h` and `LICENSE` are vendored, unchanged, into the
C target `Packages/ScratchCode/Sources/GrammarPython`, with a `README.md` that names the repository, the tag and the commit.
The target is compiled with `-w` (`cSettings: [.unsafeFlags(["-w"])]`, allowed because the package is a local one):
Xcode's build of the generated C reports `-Wshorten-64-to-32`, and the app builds with no warnings.
A grammar whose manifest lists its sources outright (tree-sitter-swift's does) stays a dependency, because vendoring a
23 MB parser would bloat the repository for nothing. Another grammar with the same template is vendored the same way.

### Queries

Each language's `highlights.scm` is copied to `Sources/ScratchCode/Queries/<language>/highlights.scm`, with its licence
and source in a header comment, and is a resource of the `ScratchCode` target (`.copy("Queries")`) that `Grammar.makeQuery`
reads through `Bundle.module`. `Bundle.module` is the one accessor that works on Linux, under `swift test` on macOS and
inside the app (where Xcode puts `ScratchCode_ScratchCode.bundle` in `Scratch.app/Contents/Resources`). The grammars' own
resource bundles have no accessor for a C target, and their layout differs on each platform. Copying also lets Scratch
change a query:

- Swift's `highlights.scm` is copied unchanged.
- Python's has one change: a decorator is an attribute, not a function. `(decorator) @function` is replaced by patterns
  for the parts of a decorator (the `@`, the name, a dotted name, the name of a call), placed last so that they win
  over the call patterns above them.

`scripts/check-release-zip.sh` fails a release zip that lacks `Queries/swift/highlights.scm`, and
`HighlighterInAppTests.testTheAppCarriesTheQueriesBundle` checks the same in the hosted app.

### How highlighting resolves overlaps

- A capture whose name has no kind (`@variable`, `@punctuation.bracket`, `@spell`) is dropped before anything else, so it
  never competes. `CaptureMapping` maps capture names to the eight kinds by prefix (Plan 4, "Colours"). `@character.special`
  (a `_` wildcard) is the one exception to the `character` prefix: it is not text in quotes.
- Of overlapping captures the innermost (narrowest) wins, and of equal width the later pattern in the query. The outer
  one is cut around the inner one. Touching tokens of one kind become one token (a Swift string is one token, not
  three).
- A parse that takes more than two seconds is given up and the text stays uncoloured, so that one text cannot stop the
  app's highlight queue.
- A text of more than 5,000 lines or 300,000 UTF-16 units is not coloured (`tokens` returns nil). `errorRate` judges such
  a text by its first lines within the cap.
- `errorRate` is the number of UTF-16 units under the outermost ERROR nodes, plus one for each MISSING node, over the
  length of the text, at most 1. Prose parsed as Python or Swift gives 1.0 (the parser makes one ERROR node of it), valid
  code gives 0.

## Adding a language

1. Find the grammar's repository and a tag that has a generated `src/parser.c`. Read its `Package.swift`: if its sources
   are listed outright, add it to `Package.swift` as a dependency with `exact:` and put its product in the `ScratchCode`
   target's dependencies. If it tests for `scanner.c` with `fileExists`, or has no generated sources, vendor it: copy
   `src/parser.c`, `src/scanner.c` (when there is one), `src/tree_sitter/*.h`, `LICENSE` and its `bindings/swift/*.h` into
   `Sources/Grammar<Language>/{src,include}`, add the C target to `Package.swift`, and write the folder's `README.md`
   (repository, tag, commit, why).
2. Copy the grammar's `queries/highlights.scm` to `Sources/ScratchCode/Queries/<language>/highlights.scm` with the licence
   header. A query that starts a line with `; inherits: <parent>` lists the parent's folder first in
   `Grammar.queryFolders` instead.
3. Add the language's `case` in `Grammar.grammar(for:)` (`Grammars.swift`), and map any capture names the query uses that
   `CaptureMapping` does not know.
4. Add corpus samples under `Tests/ScratchCodeTests` and a highlighter test.
5. Add the package, its URL, its exact version and its licence to the table above, and the app size to the table below.

## App size

`scripts/check-release-zip.sh` prints these (`release-zip.log` of the `macos` job). "Before" is the 0.3.0 release, whose
app differs from this one only in the bold rule (ADR 0006): its zip and executable are exact, and its app folder was
measured with `du -sk` on Linux, so it is comparable with the CI's number to a few per cent only. The executable grows by
the grammars and the runtime although nothing in the app calls `Highlighter` yet.

| | Zip | `Scratch.app` | Executable | Grammars |
|---|---|---|---|---|
| Before: 0.3.0 | 377,087 bytes | 1,260 KB | 1,202,288 bytes | none |
| After Plan 4, task 2 (commit 24ca9e3) | 1,052,484 bytes | 6,472 KB | 6,500,080 bytes | Swift, Python |

The Swift grammar is the big one. Object code of a Release build with `swift build -c release` on Linux x86_64, before
stripping: tree-sitter-swift 4.5 MB, the Python grammar 0.6 MB, the runtime 1.0 MB, swift-tree-sitter 1.8 MB and
ScratchCode itself 0.4 MB. Task 3 adds a row for all seventeen languages.
