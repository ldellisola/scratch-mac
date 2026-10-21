import Foundation

/// Which folders of `Queries/` make up a language's query: the folder, and the folders that its `; inherits:` line
/// names, before it.
///
/// Some grammar packages ship a query that holds only what a language adds to another's (TypeScript's to JavaScript's,
/// C++'s to C's) and leave the other to the editor, with a line such as `; inherits: javascript` at the top of the
/// file (the convention of nvim-treesitter). Scratch honours that line itself, whether the package resolves it or not,
/// so a copy of a grammar's query can stay as it is with that line added.
enum QueryInheritance {
    /// `roots` and everything they inherit from, parents first, each folder once. The patterns of a folder come after
    /// those of its parents, so they win when captures overlap. `source` gives the text of a folder's query and throws
    /// when there is none. A folder that inherits from itself, directly or not, is read once.
    static func folders(for roots: [String], source: (String) throws -> String) throws -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []
        func visit(_ folder: String) throws {
            guard seen.insert(folder).inserted else { return }
            for parent in parents(in: try source(folder)) {
                try visit(parent)
            }
            ordered.append(folder)
        }
        for root in roots {
            try visit(root)
        }
        return ordered
    }

    /// The parents named by the `; inherits: a,b` lines in the comment lines at the top of a query's text. Only that
    /// leading block of comments and blank lines is read, so a comment further down is never a directive. A name may
    /// have a `?` in front (nvim-treesitter's "optional"), which is ignored.
    static func parents(in text: String) -> [String] {
        var parents: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard line.hasPrefix(";") else { break }
            let comment = line.drop(while: { $0 == ";" }).trimmingCharacters(in: .whitespaces)
            guard comment.hasPrefix("inherits:") else { continue }
            for name in comment.dropFirst("inherits:".count).split(separator: ",") {
                let parent = name.trimmingCharacters(in: .whitespaces).drop(while: { $0 == "?" })
                if !parent.isEmpty {
                    parents.append(String(parent))
                }
            }
        }
        return parents
    }
}
