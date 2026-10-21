# 0007: tree-sitter, and the packages it comes in

Status: accepted, 2026-10-21. Spec §8.1 names tree-sitter as the highlighting engine and as the one significant
third-party dependency. This record fixes the packages, their versions and how they are used, and is the checklist for
adding a language. The wrapper, the package layout and the vendoring are [builder] calls inside §8.1.

## Decision

`Packages/ScratchCode` is a Swift package with no AppKit that builds and tests on Linux and macOS. It wraps tree-sitter
and gives the app `CodeLanguage`, `Highlighter` (text and a language in, UTF-16 token ranges out) and, in a later task of
Plan 4, `CodeDetector`. It has a grammar for each of the 17 languages of `CodeLanguage` (Plan 4, tasks 2 and 3).
`ScratchCore` does not depend on it.

### The wrapper: `tree-sitter/swift-tree-sitter`

Plan 4 asked for this package (formerly ChimeHQ/SwiftTreeSitter) if its products build and pass the tests on both the
Linux job and the macOS job, and for a thin wrapper over the C API if they do not. It builds and passes on both (the
`linux` job's and the `macos` job's "ScratchCore and ScratchCode tests", and the hosted `HighlighterInAppTests` in the
app), so the thin wrapper was not written. What it gives: `Parser`, `Query` (which is `Sendable`, so one compiled query is shared by every
thread), the `#eq?`, `#not-eq?`, `#match?`, `#not-match?` predicates, and UTF-16 offsets for nodes. What `ScratchCode`
does not use: `SwiftTreeSitterLayer`, and `LanguageConfiguration`, which finds a grammar's queries through a
`<Name>_<Name>.bundle` folder next to the executable. SwiftPM calls that folder `.resources` on Linux, so the lookup
cannot work in the Linux tests (see "Queries" below).

Measured on Linux x86_64, a Release build, 500 lines of ordinary code, best of five (task 3 measured all 17 languages
with its samples repeated to 500 lines). Tokens take 5 to 15 ms (Swift 10, Python 14, JavaScript 15, TypeScript 15,
SQL 11, Rust 11, Java 7, Go 5, JSON 5, CSS 6, C 9, C++ 7, C# 8, Bash 9, HTML 10, YAML 6, PowerShell 8) and the error rate
2 to 4 ms. The first use of a language compiles its query, with a first parse of 40 characters: Swift 270 ms (the
longest), C# 58, SQL 57, C++ 43 (its own query and C's), TypeScript 34 (and JavaScript's), Rust 27, Python 14,
JavaScript 13, Bash 10, Java 8, YAML 8, C 5, PowerShell 4, Go 3, CSS 1, HTML and JSON under 1. All are far below the
paste budget (§7: 50 ms) once the query exists, but the first Swift paste after a launch would pay the 270 ms, so the app
should compile the queries of the languages it expects on its highlight queue before they are needed.

### Packages

Every package is pinned with `exact:` (tree-sitter-sql, which has no release with generated sources, with `revision:`),
the tree-sitter runtime included, which swift-tree-sitter would otherwise let float within 0.25.x. The Xcode project is generated and never committed, so a `Package.resolved` next to it would not
survive: exact versions in `Packages/ScratchCode/Package.swift` are what keeps the app, CI and `swift test` on the same
code. `Packages/ScratchCode/Package.resolved` records the revisions.

| Package | URL | Version | Licence | Used as |
|---|---|---|---|---|
| swift-tree-sitter | https://github.com/tree-sitter/swift-tree-sitter | 0.25.0 | MIT | dependency (`SwiftTreeSitter`) |
| tree-sitter (the C runtime) | https://github.com/tree-sitter/tree-sitter | 0.25.10 | MIT | dependency (`TreeSitter`) |
| tree-sitter-swift (grammar) | https://github.com/alex-pinkus/tree-sitter-swift | 0.7.4-with-generated-files | MIT | dependency (`TreeSitterSwift`) |
| tree-sitter-python (grammar) | https://github.com/tree-sitter/tree-sitter-python | v0.25.0 | MIT | vendored (`Sources/GrammarPython`) |
| tree-sitter-javascript (grammar) | https://github.com/tree-sitter/tree-sitter-javascript | 0.23.1 | MIT | dependency (`TreeSitterJavaScript`) |
| tree-sitter-typescript (grammar) | https://github.com/tree-sitter/tree-sitter-typescript | 0.23.2 | MIT | dependency (`TreeSitterTypeScript`; the package also builds its TSX grammar, which nothing links) |
| tree-sitter-json (grammar) | https://github.com/tree-sitter/tree-sitter-json | 0.24.8 | MIT | dependency (`TreeSitterJSON`) |
| tree-sitter-bash (grammar) | https://github.com/tree-sitter/tree-sitter-bash | 0.25.1 | MIT | dependency (`TreeSitterBash`) |
| tree-sitter-sql (grammar) | https://github.com/DerekStride/tree-sitter-sql | commit e038788e5d4daba82dea35676bf49a216629e141 of `gh-pages` | MIT | dependency (`TreeSitterSql`), pinned with `revision:` |
| tree-sitter-yaml (grammar) | https://github.com/tree-sitter-grammars/tree-sitter-yaml | 0.7.0 | MIT | dependency (`TreeSitterYAML`) |
| tree-sitter-html (grammar) | https://github.com/tree-sitter/tree-sitter-html | 0.23.2 | MIT | dependency (`TreeSitterHTML`) |
| tree-sitter-css (grammar) | https://github.com/tree-sitter/tree-sitter-css | 0.23.2 | MIT | dependency (`TreeSitterCSS`) |
| tree-sitter-c-sharp (grammar) | https://github.com/tree-sitter/tree-sitter-c-sharp | 0.23.5 | MIT | dependency (`TreeSitterCSharp`) |
| tree-sitter-go (grammar) | https://github.com/tree-sitter/tree-sitter-go | 0.25.0 | MIT | dependency (`TreeSitterGo`) |
| tree-sitter-rust (grammar) | https://github.com/tree-sitter/tree-sitter-rust | 0.24.2 | MIT | dependency (`TreeSitterRust`) |
| tree-sitter-c (grammar) | https://github.com/tree-sitter/tree-sitter-c | 0.24.2 | MIT | dependency (`TreeSitterC`) |
| tree-sitter-cpp (grammar) | https://github.com/tree-sitter/tree-sitter-cpp | 0.23.4 | MIT | dependency (`TreeSitterCPP`) |
| tree-sitter-java (grammar) | https://github.com/tree-sitter/tree-sitter-java | 0.23.5 | MIT | dependency (`TreeSitterJava`) |
| tree-sitter-powershell (grammar) | https://github.com/airbus-cert/tree-sitter-powershell | v0.26.5 | MIT | vendored (`Sources/GrammarPowerShell`) |

Seventeen languages, so seventeen grammars: Swift, Python, JavaScript (which also parses JSX), TypeScript (the
TypeScript grammar, not TSX: `<T>x` is a type assertion in one and JSX in the other, and notes hold plain TypeScript far
more often), JSON, Bash (the grammar of `bash`, `sh`, `zsh` and `shell`), SQL, YAML, HTML, CSS, C#, Go, Rust, C, C++, Java
and PowerShell.

tree-sitter-swift's repository has its generated `src/parser.c` (23 MB) on the `-with-generated-files` tags only, so the
dependency is pinned to one of those.

tree-sitter-sql is the one grammar whose tags have no generated sources at all (its `.gitignore` lists `src/parser.c`,
43 MB). The generated files are on the `gh-pages` branch, which has one commit for each build of `main`, with the whole
grammar next to them and a `Package.swift` that lists its sources outright. The dependency is pinned to the build of
`987a64a` (the `main` of 2026-10-17, 76 commits after the last release, 0.3.11) with `revision:`, which a local package is
allowed to use. If that commit ever disappears (the branch is append-only so far, with 129 deploys since February 2026),
the build fails at resolution, and the generated files of the same commit are then vendored like the other grammars
below.

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

The template is in the newest tags of JavaScript (0.25.0), YAML (0.7.1, 0.7.2), CSS (0.25.0), Go (0.25.0) and
PowerShell (every tag with a `Package.swift`). The earlier tags of the first three list their sources outright, so
JavaScript is pinned to 0.23.1, YAML to 0.7.0 and CSS to 0.23.2 as dependencies, and their queries come from those same
tags (a query must match the grammar's node names). Go's 0.25.0 has the template but no scanner, so the missing scanner
costs nothing and it stays a dependency. PowerShell has a scanner, and no tag has a manifest that lists it, so it is
vendored: `Sources/GrammarPowerShell`, `v0.26.5`, 4.7 MB of generated C, compiled with `-w` like GrammarPython.

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
- The queries of the other 15 languages come from the same tag as the grammar (the SQL one from the pinned commit). Each
  file starts with the source, the licence and what Scratch changed, so a copy can be compared with its original:
  - Unchanged: JavaScript, JSON, Bash, CSS, C#, Go and PowerShell.
  - JavaScript is two folders, `javascript` and `javascript-jsx` (the grammar's `highlights-jsx.scm`, which inherits
    `javascript`). The JavaScript language uses the second, and TypeScript inherits only the first, because the
    TypeScript grammar has no JSX nodes and a query with a node name its grammar lacks does not compile.
  - TypeScript's and C++'s grammar queries hold only what the language adds to JavaScript's and C's, and expect the
    editor to put the parent's under them. Their copies have a `; inherits: javascript` and a `; inherits: c` line,
    which the highlighter honours (`QueryInheritance`, below).
  - C: the preprocessor directives are `@preproc` and `#include` is `@include`, which `CaptureMapping` maps to the
    preprocessor kind in C and C++ (the grammar's query had `@keyword`, so `#include` came out as a keyword). A character
    literal is a `@string` (it was a `@number`) and `NULL` a `@constant.builtin`.
  - Rust: numbers are `@number`, where the grammar's query had `@constant.builtin`, which Scratch colours as a keyword.
  - Java: `super` is a `@keyword`, where the query had `@function.builtin`.
  - HTML: `(quoted_attribute_value)` is a `@string` as well, so that the quotes of `class="a"` are coloured with the value
    (the grammar's query colours only the text between them).
  - YAML: the keys of a mapping are `@type`. The grammar's query had `@property` for them, which has no colour, so
    the key came out as the string it also is, and every word of a file was red.
  - SQL: the number patterns are regular expressions (they were Lua patterns, `%d`, that never match here, so every number
    was a string), `@storageclass`, `@type.qualifier` and `@attribute` keywords (`ASC`, `UNIQUE`, `CASCADE`) are
    `@keyword`, and `NULL` is `@boolean`, so that it is a keyword and not a type.

### Query inheritance

A `highlights.scm` whose leading comment lines include `; inherits: a,b` (the convention of nvim-treesitter) is joined
to the queries of the folders `a` and `b` (which may inherit in turn), parents first, each folder once
(`QueryInheritance`, which reads the folders through `Grammar.queryText`). A child's patterns are later in the query than
its parents', so they win when captures overlap (below). `Grammar.queryFolders` lists a language's own folder only:
`typescript` gives `javascript`, `typescript`, `cpp` gives `c`, `cpp`, and `javascript-jsx` gives `javascript`,
`javascript-jsx`. A `; inherits:` line that is not in the leading comments is an ordinary comment.

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
2. Copy the grammar's `queries/highlights.scm` (from the same tag as the grammar) to
   `Sources/ScratchCode/Queries/<language>/highlights.scm` with a header that names the source and the licence and lists
   what was changed. A query that holds only an addition to another language's gets a `; inherits: <parent>` line.
   A capture name that `CaptureMapping` has no kind for (`@property`, `@variable`) is dropped before overlaps are
   resolved, so it cannot make a word the text colour where a wider capture colours it (YAML's keys): give such a
   pattern a kind in the copy, or leave the word to the wider capture.
3. Add the language's `case` in `Grammar.grammar(for:)` (`Grammars.swift`), and map any capture names the query uses that
   `CaptureMapping` does not know. `swift test` compiles every language's query against its grammar, so a node name that
   the grammar lacks fails `QueryInheritanceTests`.
4. Add `Tests/ScratchCodeTests/Samples/<fence name>.txt` (15 to 40 lines of ordinary code that parses cleanly), its kinds
   in `expectedKinds` of `HighlighterTests`, and a test of what is special about the language.
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
