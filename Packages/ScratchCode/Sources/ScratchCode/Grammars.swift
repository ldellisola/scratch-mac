import Foundation
import GrammarPython
import SwiftTreeSitter
import Synchronization
import TreeSitterSwift

/// What the highlighter needs of one language: its tree-sitter grammar and its highlight queries.
///
/// This is the one place a language is wired in (docs/decisions/0007-tree-sitter.md, "Adding a language"). A language
/// with no grammar yet has no entry, and the highlighter leaves its text uncoloured.
struct Grammar: Sendable {
    /// The language's parser.
    let language: Language
    /// The folders under `Queries/` whose `highlights.scm` files make up the language's query, in this order: the
    /// parent languages' first (a child's pattern is later in the query, so it wins an overlap: see `Highlighter`).
    let queryFolders: [String]

    /// The grammar of `language`, or nil when it has none yet.
    static func grammar(for language: CodeLanguage) -> Grammar? {
        switch language {
        case .swift:
            return Grammar(language: Language(tree_sitter_swift()), queryFolders: ["swift"])
        case .python:
            return Grammar(language: Language(tree_sitter_python()), queryFolders: ["python"])
        case .javascript, .typescript, .json, .bash, .sql, .yaml, .html, .css, .csharp, .go, .rust, .c, .cpp, .java,
            .powershell:
            // Plan 4, task 3.
            return nil
        }
    }

    /// The query: every folder's `highlights.scm`, one after the other. Throws when a file is missing or does not
    /// compile for the grammar.
    func makeQuery() throws -> Query {
        var data = Data()
        for folder in queryFolders {
            guard
                let url = Bundle.module.url(
                    forResource: "highlights", withExtension: "scm", subdirectory: "Queries/\(folder)")
            else {
                throw GrammarError.missingQueryFile(folder)
            }
            data.append(try Data(contentsOf: url))
            data.append(Data("\n".utf8))
        }
        return try Query(language: language, data: data)
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
