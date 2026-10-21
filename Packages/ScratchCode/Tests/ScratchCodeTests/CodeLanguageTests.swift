import Testing

@testable import ScratchCode

// Plan 4, "Languages": the 17 languages, their fence names, aliases and labels (docs/features/code.md).

@Test func aliasesResolve() {
    #expect(CodeLanguage.fromFence("PY") == .python)
    #expect(CodeLanguage.fromFence("c#") == .csharp)
    #expect(CodeLanguage.fromFence("yml") == .yaml)
    #expect(CodeLanguage.fromFence("ruby") == nil)
}

@Test func everyAliasOfThePlanResolves() {
    let table: [(String, CodeLanguage)] = [
        ("py", .python), ("js", .javascript), ("jsx", .javascript), ("ts", .typescript), ("tsx", .typescript),
        ("sh", .bash), ("zsh", .bash), ("shell", .bash), ("yml", .yaml), ("cs", .csharp), ("c#", .csharp),
        ("rs", .rust), ("h", .c), ("c++", .cpp), ("cc", .cpp), ("hpp", .cpp), ("ps1", .powershell),
        ("pwsh", .powershell),
    ]
    for (alias, language) in table {
        #expect(CodeLanguage.fromFence(alias) == language, "\(alias)")
        #expect(CodeLanguage.fromFence(alias.uppercased()) == language, "\(alias.uppercased())")
    }
}

@Test func noNameIsALanguage() {
    #expect(CodeLanguage.fromFence("") == nil)
    #expect(CodeLanguage.fromFence("   ") == nil)
    #expect(CodeLanguage.fromFence("text") == nil)
    #expect(CodeLanguage.fromFence("c--") == nil)
}

@Test func whiteSpaceAroundANameIsIgnored() {
    #expect(CodeLanguage.fromFence("  swift ") == .swift)
    #expect(CodeLanguage.fromFence("python\n") == .python)
}

@Test func thereAreSeventeenLanguages() {
    #expect(CodeLanguage.allCases.count == 17)
}

@Test func fenceNamesAreCanonical() {
    let names = [
        "swift", "python", "javascript", "typescript", "json", "bash", "sql", "yaml", "html", "css", "csharp", "go",
        "rust", "c", "cpp", "java", "powershell",
    ]
    #expect(CodeLanguage.allCases.map(\.fenceName) == names)
    for language in CodeLanguage.allCases {
        // The canonical name resolves to its language, in any case, and is never also somebody's alias.
        #expect(CodeLanguage.fromFence(language.fenceName) == language)
        #expect(CodeLanguage.fromFence(language.fenceName.uppercased()) == language)
        #expect(CodeLanguage(rawValue: language.fenceName) == language)
        for other in CodeLanguage.allCases where other != language {
            #expect(!other.aliases.contains(language.fenceName), "\(language.fenceName) is an alias of \(other)")
        }
    }
}

@Test func aliasesBelongToOneLanguageOnly() {
    var seen: [String: CodeLanguage] = [:]
    for language in CodeLanguage.allCases {
        for alias in language.aliases {
            #expect(alias == alias.lowercased())
            #expect(seen[alias] == nil, "\(alias) is an alias of two languages")
            seen[alias] = language
        }
    }
}

@Test func labels() {
    let labels: [CodeLanguage: String] = [
        .swift: "Swift", .python: "Python", .javascript: "JavaScript", .typescript: "TypeScript", .json: "JSON",
        .bash: "Shell", .sql: "SQL", .yaml: "YAML", .html: "HTML", .css: "CSS", .csharp: "C#", .go: "Go",
        .rust: "Rust", .c: "C", .cpp: "C++", .java: "Java", .powershell: "PowerShell",
    ]
    #expect(labels.count == CodeLanguage.allCases.count)
    for language in CodeLanguage.allCases {
        #expect(language.label == labels[language])
    }
}
