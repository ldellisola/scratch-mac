import Foundation

/// The languages Scratch colours (spec §6.4, Plan 4 "Languages"). The raw value is the canonical fence name, the
/// only one ever written into a note.
public enum CodeLanguage: String, CaseIterable, Sendable {
    case swift, python, javascript, typescript, json, bash, sql, yaml, html, css, csharp, go, rust, c, cpp, java,
        powershell

    /// The language a fence name stands for: a canonical name or an alias, in any case, with the white space around it
    /// ignored. An unknown name, such as `ruby`, and an empty one give nil.
    public static func fromFence(_ name: String) -> CodeLanguage? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return byFenceName[key]
    }

    /// The name written after the opening fence.
    public var fenceName: String { rawValue }

    /// The name the label above a block shows.
    public var label: String {
        switch self {
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .bash: "Shell"
        case .sql: "SQL"
        case .yaml: "YAML"
        case .html: "HTML"
        case .css: "CSS"
        case .csharp: "C#"
        case .go: "Go"
        case .rust: "Rust"
        case .c: "C"
        case .cpp: "C++"
        case .java: "Java"
        case .powershell: "PowerShell"
        }
    }

    /// The names other than the canonical one that stand for the language (lower case).
    var aliases: [String] {
        switch self {
        case .swift: []
        case .python: ["py"]
        case .javascript: ["js", "jsx"]
        case .typescript: ["ts", "tsx"]
        case .json: []
        case .bash: ["sh", "zsh", "shell"]
        case .sql: []
        case .yaml: ["yml"]
        case .html: []
        case .css: []
        case .csharp: ["cs", "c#"]
        case .go: []
        case .rust: ["rs"]
        case .c: ["h"]
        case .cpp: ["c++", "cc", "hpp"]
        case .java: []
        case .powershell: ["ps1", "pwsh"]
        }
    }

    private static let byFenceName: [String: CodeLanguage] = {
        var table: [String: CodeLanguage] = [:]
        for language in allCases {
            table[language.fenceName] = language
            for alias in language.aliases {
                table[alias] = language
            }
        }
        return table
    }()
}
