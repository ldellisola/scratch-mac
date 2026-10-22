import Foundation
import GrammarPowerShell
import GrammarPython
import GrammarSQL
import SwiftTreeSitter
import Synchronization
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterCSharp
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTypeScript
import TreeSitterYAML

/// What the highlighter needs of one language: its tree-sitter grammar and its highlight queries.
///
/// This is the one place a language is wired in (docs/decisions/0007-tree-sitter.md, "Adding a language"). Every
/// `CodeLanguage` has a grammar. `grammar(for:)` is optional so that a language added to the enum before its grammar
/// is wired in leaves its text uncoloured instead of crashing.
struct Grammar: Sendable {
    /// The language's parser.
    let language: Language
    /// The folders under `Queries/` whose `highlights.scm` files make up the language's query. A folder's own
    /// `; inherits:` line brings its parents in before it (`QueryInheritance`), so TypeScript lists `typescript` and
    /// gets `javascript` first. A child's patterns are later in the query than its parents', so they win an overlap
    /// (see `Highlighter`).
    let queryFolders: [String]

    /// The grammar of `language`, or nil when it has none.
    static func grammar(for language: CodeLanguage) -> Grammar? {
        switch language {
        case .swift:
            return Grammar(language: Language(tree_sitter_swift()), queryFolders: ["swift"])
        case .python:
            return Grammar(language: Language(tree_sitter_python()), queryFolders: ["python"])
        case .javascript:
            // The JavaScript grammar parses JSX itself, so the JSX patterns come with it (`jsx` is an alias).
            return Grammar(language: Language(tree_sitter_javascript()), queryFolders: ["javascript-jsx"])
        case .typescript:
            // The TypeScript grammar, not TSX: `<T>x` is a type assertion in TypeScript and JSX in TSX.
            return Grammar(language: Language(tree_sitter_typescript()), queryFolders: ["typescript"])
        case .json:
            return Grammar(language: Language(tree_sitter_json()), queryFolders: ["json"])
        case .bash:
            return Grammar(language: Language(tree_sitter_bash()), queryFolders: ["bash"])
        case .sql:
            return Grammar(language: Language(tree_sitter_sql()), queryFolders: ["sql"])
        case .yaml:
            return Grammar(language: Language(tree_sitter_yaml()), queryFolders: ["yaml"])
        case .html:
            return Grammar(language: Language(tree_sitter_html()), queryFolders: ["html"])
        case .css:
            return Grammar(language: Language(tree_sitter_css()), queryFolders: ["css"])
        case .csharp:
            return Grammar(language: Language(tree_sitter_c_sharp()), queryFolders: ["csharp"])
        case .go:
            return Grammar(language: Language(tree_sitter_go()), queryFolders: ["go"])
        case .rust:
            return Grammar(language: Language(tree_sitter_rust()), queryFolders: ["rust"])
        case .c:
            return Grammar(language: Language(tree_sitter_c()), queryFolders: ["c"])
        case .cpp:
            return Grammar(language: Language(tree_sitter_cpp()), queryFolders: ["cpp"])
        case .java:
            return Grammar(language: Language(tree_sitter_java()), queryFolders: ["java"])
        case .powershell:
            return Grammar(language: Language(tree_sitter_powershell()), queryFolders: ["powershell"])
        }
    }

    /// The query: the `highlights.scm` of every folder and of the folders they inherit from, one after the other.
    /// Throws when a file is missing or does not compile for the grammar.
    func makeQuery() throws -> Query {
        var data = Data()
        for folder in try QueryInheritance.folders(for: queryFolders, source: Self.queryText(in:)) {
            data.append(Data(try Self.queryText(in: folder).utf8))
            data.append(Data("\n".utf8))
        }
        return try Query(language: language, data: data)
    }

    /// The text of `Queries/<folder>/highlights.scm`.
    static func queryText(in folder: String) throws -> String {
        guard
            let url = Bundle.module.url(
                forResource: "highlights", withExtension: "scm", subdirectory: "Queries/\(folder)")
        else {
            throw GrammarError.missingQueryFile(folder)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

enum GrammarError: Error {
    case missingQueryFile(String)
}

/// A language's compiled query and what each of its captures means, made once, on first use, and shared by every
/// thread. Compiling a query takes tens of milliseconds, so it is never done twice.
final class CompiledQuery: Sendable {
    let query: Query
    /// The kind of each capture name of the query, indexed by the capture's `index`: nil for names Scratch does not
    /// colour.
    let kinds: [HighlightKind?]

    init(query: Query, language: CodeLanguage) {
        self.query = query
        self.kinds = (0..<query.captureCount).map { index in
            query.captureName(for: index).flatMap { CaptureMapping.kind(forCapture: $0, language: language) }
        }
    }
}

/// The compiled queries of all languages, each made the first time a text in that language is highlighted.
final class QueryCache: Sendable {
    private enum Entry {
        case notBuilt
        case built(CompiledQuery)
        case failed
    }

    /// One language's entry behind its own lock (a `Mutex` cannot be a dictionary value).
    private final class Slot: Sendable {
        let entry = Mutex<Entry>(.notBuilt)
    }

    private let slots: [CodeLanguage: Slot]

    init() {
        var slots: [CodeLanguage: Slot] = [:]
        for language in CodeLanguage.allCases {
            slots[language] = Slot()
        }
        self.slots = slots
    }

    /// True when the query for `language` has been compiled (and did compile).
    func isBuilt(_ language: CodeLanguage) -> Bool {
        guard let slot = slots[language] else { return false }
        return slot.entry.withLock { state in
            if case .built = state { return true }
            return false
        }
    }

    /// The compiled query for `language`, or nil when its query does not compile (a bug that the highlighter tests
    /// catch). Holds the language's own lock while it compiles, so that two threads asking at once compile it once.
    func compiledQuery(for language: CodeLanguage, grammar: Grammar) -> CompiledQuery? {
        guard let slot = slots[language] else { return nil }
        return slot.entry.withLock { state in
            switch state {
            case .built(let compiled):
                return compiled
            case .failed:
                return nil
            case .notBuilt:
                guard let query = try? grammar.makeQuery() else {
                    state = .failed
                    return nil
                }
                let compiled = CompiledQuery(query: query, language: language)
                state = .built(compiled)
                return compiled
            }
        }
    }
}
