import Foundation

// The distinctive tokens and idioms of the seventeen languages (Plan 4 Task 4, spec §8.1: "cheap signals first").
//
// Each rule says how many points a language gets for a line that has some token or shape. The points of a rule are
// counted for at most `cap` lines, so that one repeated idiom does not decide alone. The rules are data: a new
// language adds its own, and the order they are applied in changes nothing but the last digits of a sum, which are
// added in the order of the lines, so a text always scores the same.

/// One rule: what a matching line is worth to each language it speaks for.
private struct Rule: Sendable {
    let scores: [(language: Int, weight: Double)]
    /// A word the line must hold for the rule to be tried at all (a cheap filter), or nil to try every line.
    let trigger: String?
    let cap: Int
    let test: @Sendable (DetectionLine) -> Bool
}

private struct RuleBuilder {
    var rules: [Rule] = []

    mutating func add(
        _ languages: [CodeLanguage], _ weight: Double, word: String? = nil, cap: Int = 3,
        _ test: @escaping @Sendable (DetectionLine) -> Bool
    ) {
        let scores = languages.map { (language: LanguageSignals.index(of: $0), weight: weight) }
        rules.append(Rule(scores: scores, trigger: word, cap: cap, test: test))
    }
}

enum LanguageSignals {
    /// Where a language is in the arrays of points: its place in `CodeLanguage.allCases`.
    static func index(of language: CodeLanguage) -> Int {
        CodeLanguage.allCases.firstIndex(of: language) ?? 0
    }

    /// The language at an index of the points.
    static func language(at index: Int) -> CodeLanguage { CodeLanguage.allCases[index] }

    /// How many points each language has for `features`, in the order of `CodeLanguage.allCases`.
    static func points(for features: DetectionFeatures) -> [Double] {
        var points = [Double](repeating: 0, count: CodeLanguage.allCases.count)
        let table = Table.shared
        var hits = [Int](repeating: 0, count: table.rules.count)
        var stamp = [Int](repeating: -1, count: table.rules.count)

        for (number, line) in features.lines.prefix(signalLines).enumerated() {
            func apply(_ rule: Int) {
                guard stamp[rule] != number else { return }
                stamp[rule] = number
                if table.rules[rule].test(line) { hits[rule] += 1 }
            }
            for rule in table.alwaysTried {
                apply(rule)
            }
            for word in line.words {
                for rule in table.byTrigger[word] ?? [] {
                    apply(rule)
                }
            }
        }
        for (number, rule) in table.rules.enumerated() where hits[number] > 0 {
            let counted = Double(min(hits[number], rule.cap))
            for score in rule.scores {
                points[score.language] += counted * score.weight
            }
        }

        addShapes(of: features, to: &points)
        return points
    }

    /// The lines that are read for signals: the idioms of a language show up early.
    static let signalLines = 100

    // MARK: Shapes and markers that decide

    private static func addShapes(of features: DetectionFeatures, to points: inout [Double]) {
        func give(_ language: CodeLanguage, _ weight: Double) { points[index(of: language)] += weight }

        if features.isJSON { give(.json, 14) }
        if features.isYAMLShaped { give(.yaml, 9) }
        if features.isSQLShaped { give(.sql, 9) }
        if features.hasDoctype { give(.html, 10) }
        if features.hasHTMLRoot { give(.html, 6) }
        if let language = shebangLanguage(features.shebang) { give(language, 14) }
    }

    /// The language a shebang line names (without the `#!`), nil for none of the seventeen.
    static func shebangLanguage(_ shebang: String?) -> CodeLanguage? {
        guard let shebang else { return nil }
        let words = shebang.split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "\t" }).map(String.init)
        for word in words.reversed() {
            switch word {
            case "bash", "sh", "zsh", "dash", "ksh": return .bash
            case "python", "python2", "python3": return .python
            case "node", "deno", "bun": return .javascript
            case "pwsh", "powershell": return .powershell
            case "swift": return .swift
            default:
                if word.hasPrefix("python") { return .python }
            }
        }
        return nil
    }

    // MARK: The table

    /// The rules, and which words and lines they are tried on.
    private final class Table: Sendable {
        static let shared = Table()

        let rules: [Rule]
        /// The rules that need a word of the line, by that word.
        let byTrigger: [String: [Int]]
        let alwaysTried: [Int]

        init() {
            var builder = RuleBuilder()
            swiftRules(&builder)
            pythonRules(&builder)
            scriptRules(&builder)
            shellRules(&builder)
            dataRules(&builder)
            markupRules(&builder)
            dotnetAndJavaRules(&builder)
            systemsRules(&builder)
            rules = builder.rules

            var byTrigger: [String: [Int]] = [:]
            var always: [Int] = []
            for (number, rule) in builder.rules.enumerated() {
                if let trigger = rule.trigger {
                    byTrigger[trigger, default: []].append(number)
                } else {
                    always.append(number)
                }
            }
            self.byTrigger = byTrigger
            self.alwaysTried = always
        }
    }
}

// MARK: Rules

private let swiftAttributes: Set<String> = [
    "State", "Binding", "Published", "MainActor", "Environment", "ObservedObject", "StateObject", "objc", "escaping",
    "available", "discardableResult", "Observable", "Bindable", "ViewBuilder", "main", "propertyWrapper", "testable",
    "Test", "Suite", "AppStorage", "Sendable", "frozen", "inlinable",
]

private let swiftModules: Set<String> = [
    "Foundation", "SwiftUI", "UIKit", "AppKit", "Combine", "XCTest", "Testing", "CoreData", "MapKit", "Cocoa",
    "SwiftData", "Dispatch", "OSLog", "CoreGraphics", "Observation", "ArgumentParser",
]

/// An implicit member: `.command` in `modifierFlags: .command`, `(.return, ...)`, `[.titled, .closable]`, `= .zero`.
private func hasImplicitMember(_ line: DetectionLine) -> Bool {
    let bytes = line.bytes
    let afterSpace: Set<UInt8> = [0x3A, 0x2C, 0x3D]
    var index = 0
    while index + 2 < bytes.count {
        let before: UInt8 = bytes[index]
        if bytes[index + 1] == 0x2E, Byte.isLower(bytes[index + 2]) {
            if before == 0x28 || before == 0x5B { return true }
            if before == 0x20, index > 0, afterSpace.contains(bytes[index - 1]) { return true }
        }
        index += 1
    }
    return false
}

/// A method followed by a trailing closure: `.map {`, `.sorted { a, b in`.
private let swiftTrailingClosures: [StaticString] = [
    ".map {", ".filter {", ".sorted {", ".forEach {", ".compactMap {", ".flatMap {", ".first {", ".contains {",
]

private func swiftRules(_ b: inout RuleBuilder) {
    b.add([.swift], 4, word: "func") { $0.has("func ") && $0.has("(") && ($0.has("->") || $0.has(": ")) }
    b.add([.swift], 1.5, word: "func") { $0.has("func ") && $0.has("(") }
    b.add([.swift], 3, word: "guard") { $0.starts("guard ") }
    b.add([.swift], 3, word: "let") { $0.has("if let ") || $0.has("guard let ") || $0.has("if var ") }
    b.add([.swift], 1.5, word: "let") { $0.starts("let ") && !$0.endsWithSemicolon }
    b.add([.swift, .rust, .typescript], 1, word: "let") { $0.starts("let ") && $0.has(": ") }
    b.add([.swift], 1, word: "var") { $0.starts("var ") && !$0.endsWithSemicolon && !$0.starts("var $") }
    b.add([.swift], 5, word: "import") { $0.firstWord == "import" && swiftModules.contains($0.secondWord) }
    b.add([.swift], 5) { line in
        guard line.bytes[0] == 0x40 else { return false }
        return swiftAttributes.contains(line.words.first ?? "")
    }
    b.add([.swift], 3, word: "extension") { $0.starts("extension ") }
    b.add([.swift], 3, word: "protocol") { $0.starts("protocol ") }
    b.add([.swift], 5) { $0.has("\\(") }
    b.add([.swift], 4, word: "View") { $0.has("some View") }
    b.add([.swift], 3) { $0.has("$0") }
    b.add([.swift], 3, word: "fileprivate") { _ in true }
    b.add([.swift], 3, word: "case") { $0.starts("case .") || $0.starts("case let ") }
    b.add([.swift, .go], 1, word: "nil") { _ in true }
    b.add([.swift], 1.5) { line in
        line.has("String?") || line.has("Int?") || line.has("Double?") || line.has("Date?") || line.has("URL?")
            || line.has("[String]") || line.has("[Int]") || line.has("[Double]")
    }
    b.add([.swift], 4) { $0.starts("// MARK:") }
    b.add([.swift], 3) { $0.has("try?") || $0.has("try!") || $0.has("try await") }
    b.add([.swift], 3, word: "throws") { $0.has(") throws") || $0.has(") async throws") }
    b.add([.swift], 5) { $0.has("[weak self]") || $0.has("weak self") }
    b.add([.swift], 3, word: "struct") { $0.starts("struct ") && $0.has(": ") && $0.endsWithOpenBrace }
    b.add([.swift], 2, word: "init") { $0.starts("init(") || $0.starts("override init(") }
    b.add([.swift], 2, word: "print") { $0.starts("print(") }
    b.add([.swift], 2, word: "in") { $0.has("{ ") && $0.has(" in") && !$0.has("for ") }
    b.add([.swift], 2, word: "self") { $0.has("self.") }
    b.add([.swift], 5) { $0.has("XCTAssert") || $0.has("XCTFail") || $0.has("XCTUnwrap") }
    b.add([.swift], 3, word: "try") { line in
        guard line.starts("try ") || line.has("= try ") || line.has("(try ") else { return false }
        return !line.starts("try {") && !line.starts("try:")
    }
    b.add([.swift], 3, word: "defer") { $0.starts("defer {") }
    b.add([.swift], 3, word: "private") { line in
        line.starts("private let ") || line.starts("private var ") || line.starts("private static ")
            || line.starts("private func ") || line.starts("private(set) ")
    }
    b.add([.swift], 3, word: "static") {
        $0.starts("static let ") || $0.starts("static var ") || $0.starts("static func ")
    }
    b.add([.swift], 3, word: "final") { $0.starts("final class ") }
    b.add([.swift], 3, word: "override") { $0.starts("override func ") || $0.starts("override init") }
    b.add([.swift], 3) { line in swiftTrailingClosures.contains { line.has($0) } }
    b.add([.swift], 3) { hasImplicitMember($0) }
    b.add([.swift], 4, word: "import") { $0.starts("@testable import ") }
    b.add([.swift], 1.5) { $0.starts("///") }
    b.add([.swift], 2, word: "Self") { $0.has("Self.") }
}

private func pythonRules(_ b: inout RuleBuilder) {
    b.add([.python], 5, word: "def") { $0.firstWord == "def" && $0.ends(":") }
    b.add([.python], 5, word: "class") { $0.firstWord == "class" && $0.ends(":") }
    b.add([.python], 5, word: "async") { $0.starts("async def ") }
    b.add([.python], 4, word: "elif") { $0.firstWord == "elif" }
    b.add([.python], 2, word: "else") { $0.bytes == Array("else:".utf8) }
    b.add([.python], 2, word: "try") { $0.bytes == Array("try:".utf8) }
    b.add([.python], 3) { $0.isPythonOpener && !$0.endsWithOpenBrace }
    b.add([.python], 3, word: "import") { line in
        guard line.firstWord == "import", !line.has(";"), !line.has("\""), !line.has("'"), !line.has("{") else {
            return false
        }
        guard let head = line.secondWord.utf8.first else { return false }
        return Byte.isLower(head) && !line.has("java.")
    }
    b.add([.python], 5, word: "from") { $0.firstWord == "from" && $0.has(" import ") && !$0.has(";") }
    b.add([.python], 6, word: "__name__") { _ in true }
    b.add([.python], 3, word: "self") { $0.has("self.") || $0.has("(self") || $0.has("self,") }
    b.add([.python], 2, word: "None") { _ in true }
    b.add([.python], 1.5, word: "True") { _ in true }
    b.add([.python], 1.5, word: "False") { _ in true }
    b.add([.python], 2, word: "lambda") { $0.has("lambda ") }
    b.add([.python], 3, word: "range") { $0.has("range(") && $0.has(" in ") }
    b.add([.python], 1.5, word: "print") { $0.starts("print(") }
    b.add([.python], 3, word: "raise") { $0.firstWord == "raise" }
    b.add([.python], 3, word: "pass") { $0.bytes == Array("pass".utf8) }
    b.add([.python], 3, word: "except") { $0.firstWord == "except" }
    b.add([.python], 4, word: "for") { $0.has("[") && $0.has(" for ") && $0.has(" in ") && $0.has("]") }
    b.add([.python], 3, word: "open") { $0.has("with open(") }
    b.add([.python], 2) { $0.has(".append(") || $0.has(".items()") || $0.has(".strip(") || $0.has(".join(") }
    b.add([.python], 1.5, word: "len") { $0.has("len(") }
    b.add([.python], 4, word: "__init__") { _ in true }
    b.add([.python], 0.5) { $0.isHashComment }
}

private func scriptRules(_ b: inout RuleBuilder) {
    let both: [CodeLanguage] = [.javascript, .typescript]
    b.add(both, 3, word: "const") { ($0.starts("const ") || $0.starts("export const ")) && $0.has(" = ") }
    b.add(both, 1.5, word: "let") { $0.starts("let ") && $0.endsWithSemicolon }
    b.add([.rust], 1.5, word: "let") { $0.starts("let ") && $0.endsWithSemicolon }
    b.add(both + [.csharp], 1.5, word: "var") { $0.starts("var ") && $0.endsWithSemicolon }
    b.add(both, 4, word: "function") { line in
        line.starts("function ") || line.has("function(") || line.has("function (") || line.starts("async function ")
            || line.starts("export function ") || line.starts("export default function")
    }
    b.add(both, 2) { $0.has("=>") }
    b.add([.csharp], 1.5) { $0.has("=>") }
    b.add(both, 6, word: "console") { $0.has("console.") }
    b.add(both, 4, word: "require") { $0.has("require(") }
    b.add(both, 5, word: "module") { $0.has("module.exports") }
    b.add(both, 3, word: "exports") { $0.starts("exports.") }
    b.add(both, 5, word: "document") { $0.has("document.") }
    b.add(both, 3, word: "window") { line in
        line.has("window.location") || line.has("window.document") || line.has("window.addEventListener")
            || line.has("window.innerWidth") || line.has("window.onload") || line.has("window.alert")
    }
    b.add(both, 4, word: "addEventListener") { _ in true }
    b.add(both, 4, word: "import") { line in
        line.firstWord == "import"
            && (line.has(" from \"") || line.has(" from '") || line.has("import \"") || line.has("import '"))
    }
    b.add(both, 3, word: "export") { $0.starts("export ") }
    b.add(both, 3) { $0.has("===") || $0.has("!==") }
    b.add(both, 4) { $0.has(".then(") || $0.has(".catch(") }
    b.add(both, 5, word: "JSON") { $0.has("JSON.parse") || $0.has("JSON.stringify") }
    b.add(both, 2, word: "Promise") { _ in true }
    b.add(both, 3, word: "fetch") { $0.has("fetch(") }
    b.add(both, 3, word: "await") { $0.has("await ") && ($0.has("fetch(") || $0.has("res.") || $0.has("response.")) }
    b.add(both + [.csharp, .python, .rust], 1, word: "await") { $0.has("await ") }
    b.add(both, 2, word: "async") { $0.has("async ") }
    b.add(both, 3) { $0.has("`") && $0.has("${") }
    b.add(both, 3, word: "undefined") { _ in true }
    b.add(both + [.java, .csharp], 1, word: "null") { _ in true }
    b.add(both, 5) { $0.has("onClick=") || $0.has("className=") }
    b.add(both, 4, word: "useState") { _ in true }
    b.add(both, 4, word: "useEffect") { _ in true }
    b.add(both + [.java, .csharp], 1.5, word: "this") { $0.has("this.") }
    b.add(both, 2) { $0.has(".forEach(") || $0.has(".map(") || $0.has(".filter(") || $0.has(".reduce(") }
    b.add(both, 3, word: "push") { $0.has(".push(") }
    b.add(both, 3, word: "app") { $0.has("app.get(") || $0.has("app.use(") || $0.has("app.listen(") }
    b.add(both, 2, word: "typeof") { _ in true }

    // TypeScript only.
    b.add([.typescript], 4, word: "interface") { $0.starts("interface ") || $0.starts("export interface ") }
    b.add([.typescript], 5) { line in
        line.has(": string") || line.has(": number") || line.has(": boolean") || line.has(": any")
            || line.has(": void") || line.has(": never") || line.has(": unknown") || line.has(": object")
    }
    b.add([.typescript], 4, word: "type") { ($0.starts("type ") && $0.has(" = ")) || $0.starts("export type ") }
    b.add([.typescript], 4) { $0.has("Promise<") || $0.has("Record<") || $0.has("Partial<") || $0.has("Readonly<") }
    b.add([.typescript], 3) { line in
        (line.starts("private ") || line.starts("public ") || line.starts("protected ") || line.starts("readonly "))
            && line.has(": ") && !line.has("(") && !line.has(" let ") && !line.has(" var ")
    }
    b.add([.typescript], 5) { line in
        guard line.bytes[0] == 0x40 else { return false }
        return ["Injectable", "Component", "NgModule", "Input", "Output", "Directive", "Pipe"].contains(
            line.words.first ?? "")
    }
    b.add([.typescript], 3) { $0.has(") as ") || $0.has("?:") || $0.has("!:") }
    b.add([.typescript], 5, word: "type") { $0.starts("import type ") }
    b.add([.typescript], 1.5, word: "enum") { $0.starts("enum ") || $0.starts("export enum ") }
}

private func shellRules(_ b: inout RuleBuilder) {
    b.add([.bash], 3) { $0.starts("$ ") }
    b.add([.bash], 5, word: "set") { $0.starts("set -") }
    b.add([.bash], 4, word: "export") { $0.firstWord == "export" && $0.has("=") }
    b.add([.bash], 4) { ($0.starts("if [") || $0.starts("elif [") || $0.starts("while [")) || $0.has("[[ ") }
    b.add([.bash], 4) { $0.has("; then") || $0.has("; do") || $0.ends(" do") }
    b.add([.bash], 5) { line in
        ["then", "fi", "done", "esac", "do"].contains(String(decoding: line.bytes, as: UTF8.self))
    }
    b.add([.bash], 3) { $0.has("$(") || $0.has("${") }
    b.add([.bash], 2) { $0.hasShellVariable }
    b.add([.powershell], 1) { $0.hasShellVariable }
    b.add([.bash], 1.5, cap: 4) { $0.isShellCommand }
    b.add([.powershell], 0.3, cap: 4) { $0.isShellCommand }
    b.add([.bash], 1) { $0.has(" | ") || $0.has(" && ") }
    b.add([.powershell], 1) { $0.has(" | ") || $0.ends(" |") }
    b.add([.bash], 1.5) { line in
        line.has(" --") && !line.has(" -- ") || line.has(" -") && !line.has("- ") && Byte.isLower(flagLetter(line))
    }
    b.add([.bash], 2, word: "echo") { $0.firstWord == "echo" }
    b.add([.bash], 3, word: "sudo") { $0.firstWord == "sudo" }
    b.add([.bash], 3) { line in
        // `NAME=value` with no spaces around the `=`.
        guard Byte.isLetter(line.bytes[0]) || line.bytes[0] == 0x5F else { return false }
        var index = 0
        while index < line.bytes.count, Byte.isIdentifier(line.bytes[index]) {
            index += 1
        }
        return index > 0 && index + 1 < line.bytes.count && line.bytes[index] == 0x3D && line.bytes[index + 1] != 0x3D
            && line.bytes[index + 1] != 0x20
    }
    b.add([.bash], 4) { $0.has("2>&1") || $0.has(" >> ") || $0.has("/dev/null") }
    b.add([.bash], 3) { $0.has("$@") || $0.has("$?") || $0.has("$#") || $0.has("$1") || $0.has("$0") }
    b.add([.bash], 0.5) { $0.isHashComment }

    // PowerShell.
    b.add([.powershell], 6, cap: 3) { $0.hasCmdlet }
    b.add([.powershell], 4) { $0.starts("$") && $0.has(" = ") && !$0.endsWithSemicolon }
    b.add([.powershell], 4, word: "param") { $0.starts("param(") || $0.starts("param (") }
    b.add([.powershell], 4, word: "function") { $0.starts("function ") && $0.endsWithOpenBrace && !$0.has("(") }
    b.add([.powershell], 5) { line in
        line.has(" -eq ") || line.has(" -ne ") || line.has(" -gt ") || line.has(" -lt ") || line.has(" -ge ")
            || line.has(" -le ") || line.has(" -like ") || line.has(" -match ") || line.has(" -and ")
            || line.has(" -or ") || line.has(" -not ") || line.has(" -contains ") || line.has(" -in ")
    }
    b.add([.powershell], 4) {
        $0.has("$_") || $0.has("$PSItem") || $0.has("$true") || $0.has("$false") || $0.has("$null")
    }
    b.add([.powershell], 6) { $0.has("$env:") || $0.has("$PSScriptRoot") || $0.has("-ErrorAction") }
    b.add([.powershell], 5, word: "foreach") { $0.starts("foreach (") && $0.has("$") }
    b.add([.powershell], 3) { line in
        // `-Name`, `-Path`: a flag with a capital.
        var index = 0
        while index + 2 < line.bytes.count {
            if line.bytes[index] == 0x20, line.bytes[index + 1] == 0x2D, Byte.isUpper(line.bytes[index + 2]) {
                return true
            }
            index += 1
        }
        return false
    }
    b.add([.powershell], 5) { $0.has("[string]") || $0.has("[int]") || $0.has("[switch]") || $0.has("[CmdletBinding") }
    b.add([.powershell], 5) { $0.starts("<#") || $0.starts("#>") }
    b.add([.powershell], 3) { $0.has("@{") || $0.has("@(") }
    b.add([.powershell], 2) { $0.has(".\\") }
    b.add([.powershell], 0.5) { $0.isHashComment }
}

/// The first letter after the first ` -` of a line (a space when there is none).
private func flagLetter(_ line: DetectionLine) -> UInt8 {
    var index = 0
    while index + 2 < line.bytes.count {
        if line.bytes[index] == 0x20, line.bytes[index + 1] == 0x2D { return line.bytes[index + 2] }
        index += 1
    }
    return 0x20
}

private func dataRules(_ b: inout RuleBuilder) {
    // JSON.
    b.add([.json], 2, cap: 3) { $0.isJSONKeyLine }

    // SQL.
    b.add([.sql], 3, cap: 4) { $0.isSQLKeywordLine }
    b.add([.sql], 6) { line in
        let words = line.words.prefix(3).map { $0.lowercased() }
        guard words.count >= 2,
            line.firstWord == line.firstWord.lowercased() || line.firstWord == line.firstWord.uppercased()
        else { return false }
        let pair = words[0] + " " + words[1]
        return [
            "create table", "create index", "create view", "insert into", "delete from", "alter table", "drop table",
            "create unique", "create or",
        ].contains(pair)
    }
    b.add([.sql], 3) { $0.has("NOT NULL") || $0.has("not null") || $0.has("PRIMARY KEY") || $0.has("primary key") }
    b.add([.sql], 3) { line in
        line.has(" JOIN ") || line.has(" join ") || line.has("GROUP BY") || line.has("group by") || line.has("ORDER BY")
            || line.has("order by")
    }
    b.add([.sql], 2) { $0.has("COUNT(") || $0.has("SUM(") || $0.has("AVG(") || $0.has("MAX(") || $0.has("MIN(") }
    b.add([.sql], 1) { $0.starts("-- ") }

    // YAML.
    b.add([.yaml], 1, cap: 5) { $0.yamlKey != nil }
    b.add([.yaml], 3) { $0.starts("- ") && $0.yamlKey != nil }
    b.add([.yaml], 3) { $0.has("${{") }
    b.add([.yaml], 3) { $0.bytes == [0x2D, 0x2D, 0x2D] }
    b.add([.yaml], 0.5) { $0.isHashComment }
}

private func markupRules(_ b: inout RuleBuilder) {
    // HTML.
    b.add([.html], 2, cap: 5) { line in
        guard line.hasHTMLTag else { return false }
        // The name of the first tag.
        guard let open = line.bytes.firstIndex(of: 0x3C) else { return false }
        var start = open + 1
        if start < line.bytes.count, line.bytes[start] == 0x2F { start += 1 }
        var end = start
        while end < line.bytes.count, Byte.isIdentifier(line.bytes[end]) {
            end += 1
        }
        return htmlTagNames.contains(String(decoding: line.bytes[start..<end], as: UTF8.self).lowercased())
    }
    b.add([.html], 2) { line in
        line.has("class=\"") || line.has("href=\"") || line.has("id=\"") || line.has("src=\"") || line.has("type=\"")
            || line.has("name=\"") || line.has("lang=\"") || line.has("charset=\"") || line.has("rel=\"")
    }
    b.add([.html], 1) { $0.starts("<!--") }

    // CSS.
    b.add([.css], 3, cap: 5) { $0.isCSSDeclaration }
    b.add([.css], 3, cap: 3) { $0.isCSSSelector }
    b.add([.css], 5) {
        $0.starts("@media") || $0.starts("@import") || $0.starts("@font-face") || $0.starts("@keyframes")
    }
    b.add([.css], 4) { $0.has("var(--") || $0.has("!important") || $0.starts(":root") }
    b.add([.css], 4) { $0.starts("--") && $0.has(": ") }
}

private func dotnetAndJavaRules(_ b: inout RuleBuilder) {
    // C#.
    b.add([.csharp], 8, word: "using") { $0.starts("using System") }
    b.add([.csharp], 4, word: "using") { $0.starts("using Microsoft") || $0.starts("using Newtonsoft") }
    b.add([.csharp], 8, word: "Console") { $0.has("Console.Write") || $0.has("Console.Read") }
    b.add([.csharp], 8) { $0.has("get;") || $0.has("{ get =>") }
    b.add([.csharp], 6, word: "foreach") { $0.has("foreach (var ") }
    b.add([.csharp], 3, word: "var") { $0.starts("var ") && $0.has(" = new ") }
    b.add([.csharp], 3, word: "string") { line in
        line.has("<string>") || line.has("<string,") || line.has("(string ") || line.has("public string ")
            || line.has("private string ") || line.has("protected string ") || line.has("string[]")
            || line.starts("string ") || line.has("static string ") || line.has("readonly string ")
    }
    b.add([.csharp], 6, word: "Task") { $0.has("async Task") || $0.has("Task<") }
    b.add([.csharp], 5) { line in
        line.has("IActionResult") || line.has("ActionResult") || line.has("IEnumerable<") || line.has("IList<")
            || line.has("IQueryable")
    }
    b.add([.csharp], 5) { $0.has("$\"") || $0.has("nameof(") }
    b.add([.csharp], 3, word: "namespace") { $0.starts("namespace ") }
    b.add([.cpp], 2, word: "namespace") { $0.starts("namespace ") }
    b.add([.csharp], 5, word: "namespace") { $0.starts("namespace ") && $0.endsWithSemicolon }
    b.add([.csharp], 5) { line in
        // An attribute: `[HttpGet]`, `[Route("x")]`.
        guard line.bytes[0] == 0x5B, line.bytes[line.bytes.count - 1] == 0x5D, line.bytes.count > 2 else {
            return false
        }
        guard Byte.isUpper(line.bytes[1]) else { return false }
        let name = line.words.first ?? ""
        return !["Parameter", "CmdletBinding", "string", "int", "switch"].contains(name)
    }
    b.add([.csharp], 3, word: "override") { $0.has("public override") || $0.has("override string") }
    b.add([.csharp], 4) { line in
        line.has(".Where(") || line.has(".Select(") || line.has(".ToList") || line.has(".OrderBy")
            || line.has(".FirstOrDefault(")
    }
    b.add([.csharp], 5) { $0.starts("internal ") || $0.starts("sealed ") || $0.has("partial class") }
    b.add([.csharp], 3) { line in
        line.has("DateTime") || line.has("Guid") || line.has("StringBuilder") || line.has("Dictionary<")
    }
    b.add([.csharp], 6, word: "Main") { $0.has("static void Main") || $0.has("static int Main") }
    b.add([.csharp], 4, word: "string") { $0.has("string[] args") }
    b.add([.csharp, .java], 1.5, word: "class") { $0.starts("public class ") }
    b.add([.csharp], 1.5) { $0.bytes == [0x7B] }
    b.add([.csharp], 2, word: "private") { $0.has("private readonly") }

    // Java.
    b.add([.java], 8, word: "System") { $0.has("System.out.") || $0.has("System.err.") }
    b.add([.java], 8, word: "import") { $0.starts("import java.") || $0.starts("import javax.") }
    b.add([.java], 6, word: "package") { $0.starts("package ") && $0.has(".") && $0.endsWithSemicolon }
    b.add([.java], 6, word: "Override") { $0.starts("@Override") }
    b.add([.java], 4) { line in
        line.starts("@Autowired") || line.starts("@Service") || line.starts("@RestController")
            || line.starts("@GetMapping")
            || line.starts("@Entity") || line.starts("@Component")
    }
    b.add([.java], 10, word: "main") { $0.has("static void main(") }
    b.add([.java], 4, word: "String") { $0.has("String[] args") }
    b.add([.java], 5) { $0.has("<>()") }
    b.add([.java], 3) { $0.has("ArrayList") || $0.has("HashMap") || $0.has("List<String>") || $0.has("Map<String") }
    b.add([.java], 4, word: "throws") { $0.has(" throws ") && !$0.has("func ") }
    b.add([.java], 5) { $0.has(".stream()") || $0.has("Collectors.") }
    b.add([.java], 4, word: "Optional") { $0.has("Optional<") }
    b.add([.java, .cpp, .rust], 1.5) { line in
        // `Note::getTitle`: a method reference or a scope, with no spaces around the `::`.
        line.has("::") && !line.has(" :: ")
    }
    b.add([.java], 2, word: "private") { $0.has("private final") || $0.has("private static") || $0.has("public final") }
    b.add([.java, .csharp], 3, word: "interface") { $0.starts("public interface ") }
    b.add([.java, .typescript], 2, word: "extends") { $0.has(" extends ") || $0.has(" implements ") }
    b.add([.java, .csharp, .cpp, .javascript], 1) { $0.starts("/**") }
    b.add([.java], 2.5) { line in
        line.has("(String ") || line.has("public String ") || line.has("private String ") || line.starts("String ")
    }
    b.add([.java, .csharp], 3, word: "catch") { $0.has("catch (") && $0.has("Exception") }
    b.add([.java, .csharp, .typescript, .cpp, .rust], 1, word: "enum") {
        $0.starts("enum ") || $0.starts("public enum ")
    }
    b.add([.java, .csharp, .typescript, .rust], 1) { $0.has("<T>") || $0.has("<T,") }
}

private func systemsRules(_ b: inout RuleBuilder) {
    // Go.
    b.add([.go], 6, word: "package") {
        $0.starts("package ") && !$0.has(".") && !$0.endsWithSemicolon && $0.tokenCount == 2
    }
    b.add([.go], 6, word: "main") { $0.starts("func main()") }
    b.add([.go], 6, word: "func") { $0.starts("func (") }
    b.add([.go], 3, word: "func") { $0.starts("func ") && !$0.has("->") && !$0.has(": ") && $0.endsWithOpenBrace }
    b.add([.go], 5) { $0.has(":=") }
    b.add([.go], 8, word: "fmt") { $0.has("fmt.") }
    b.add([.go], 8, word: "err") { $0.has("err != nil") || $0.starts("if err") }
    b.add([.go], 6, word: "defer") { $0.starts("defer ") && !$0.starts("defer {") }
    b.add([.go], 8, word: "go") { $0.starts("go func") || $0.starts("go ") && $0.has("(") }
    b.add([.go], 4, word: "range") { $0.has("range ") }
    b.add([.go], 6, word: "import") { $0.starts("import (") || $0.starts("import \"") }
    b.add([.go], 8, word: "type") { $0.starts("type ") && ($0.has(" struct {") || $0.has(" interface {")) }
    b.add([.go], 2, word: "make") { $0.has("make(") }
    b.add([.go], 5, word: "chan") { _ in true }
    b.add([.go], 3) { $0.has("[]string") || $0.has("[]int") || $0.has("[]byte") || $0.has("[]error") }

    // Rust.
    b.add([.rust], 6, word: "fn") {
        $0.starts("fn ") || $0.starts("pub fn ") || $0.starts("async fn ") || $0.starts("pub(crate) fn ")
    }
    b.add([.rust], 8, word: "let") { $0.has("let mut ") }
    b.add([.rust], 8) { line in
        // A macro: `println!(`, `vec![`.
        var index = 1
        while index + 1 < line.bytes.count {
            if line.bytes[index] == 0x21, Byte.isIdentifier(line.bytes[index - 1]),
                line.bytes[index + 1] == 0x28 || line.bytes[index + 1] == 0x5B || line.bytes[index + 1] == 0x7B
            {
                return true
            }
            index += 1
        }
        return false
    }
    b.add([.rust], 8, word: "use") { $0.starts("use std::") || $0.starts("use crate::") }
    b.add([.rust], 4, word: "use") { $0.starts("use ") && $0.has("::") && $0.endsWithSemicolon }
    b.add([.rust], 4, word: "impl") { $0.starts("impl ") || $0.starts("impl<") }
    b.add([.rust], 3, word: "match") { $0.has("match ") && $0.endsWithOpenBrace }
    b.add([.rust], 6) { $0.has("&self") || $0.has("&mut ") }
    b.add([.rust], 5) { $0.has("-> Result<") || $0.has("-> Option<") || $0.has("Result<") || $0.has("Option<") }
    b.add([.rust], 2) { $0.has("Some(") || $0.has("None") || $0.has("Ok(") || $0.has("Err(") }
    b.add([.rust], 6) { $0.starts("#[") || $0.starts("#![") }
    b.add([.rust], 3) { $0.has("::new(") || $0.has("::from(") }
    b.add([.rust], 4) { line in
        line.has(": u32") || line.has(": i32") || line.has(": u64") || line.has(": usize") || line.has(": f64")
            || line.has(": u8") || line.has(": i64") || line.has("&str") || line.has(": bool") || line.has("<u32>")
            || line.has("<u16>")
    }
    b.add([.rust], 4) { $0.has(".unwrap()") || $0.has(".expect(") || $0.has("?;") }
    b.add([.rust], 4, word: "pub") { $0.starts("pub struct ") || $0.starts("pub enum ") || $0.starts("pub mod ") }
    b.add([.rust], 3, word: "mod") { $0.starts("mod ") }
    b.add([.rust], 4) { $0.has("..=") }
    b.add([.rust], 3, word: "loop") { $0.starts("loop {") }
    b.add([.rust], 3, word: "mut") { $0.has("mut ") }

    // C and C++.
    b.add([.c, .cpp], 6, word: "include") { $0.starts("#include") }
    b.add([.cpp], 8, word: "include") { line in
        line.has("<iostream>") || line.has("<vector>") || line.has("<string>") || line.has("<map>")
            || line.has("<memory>")
            || line.has("<algorithm>") || line.has("<set>") || line.has("<cstdio>") || line.has("<cstdlib>")
    }
    b.add([.c, .cpp], 5, word: "define") { $0.starts("#define") }
    b.add([.c, .cpp], 5, word: "main") { $0.has("int main(") }
    b.add([.c], 5) { line in
        line.has("printf(") || line.has("scanf(") || line.has("malloc(") || line.has("free(") || line.has("sizeof(")
            || line.has("strlen(")
    }
    b.add([.cpp], 2) { line in
        line.has("printf(") || line.has("malloc(") || line.has("sizeof(")
    }
    b.add([.c, .cpp], 1) { $0.has("->") && !$0.has("func ") && !$0.has("fn ") }
    b.add([.c], 6, word: "typedef") { $0.starts("typedef ") }
    b.add([.cpp], 2, word: "typedef") { $0.starts("typedef ") }
    b.add([.c, .cpp, .rust, .swift], 2, word: "struct") { $0.starts("struct ") || $0.starts("typedef struct") }
    b.add([.c], 4, word: "NULL") { _ in true }
    b.add([.c], 4) { line in
        line.has("size_t") || line.has("uint8_t") || line.has("uint32_t") || line.has("uint64_t") || line.has("int32_t")
    }
    b.add([.c], 4) { $0.has("char *") || $0.has("char*") || $0.has("char **") }
    b.add([.cpp], 2) { $0.has("char *") || $0.has("char*") }
    b.add([.c, .cpp], 2) { $0.has("'\\0'") }
    b.add([.c], 2, word: "int") { $0.has("int ") && $0.has("[") && $0.has("]") && $0.endsWithSemicolon }
    b.add([.c, .cpp, .java, .csharp], 1, word: "return") { $0.firstWord == "return" && $0.endsWithSemicolon }
    b.add([.c, .cpp, .java, .csharp], 1, word: "for") { $0.starts("for (") && $0.has(";") }
    b.add([.c, .cpp, .java, .csharp], 1, word: "void") { $0.has("void ") && $0.has("(") }
    b.add([.cpp], 8, word: "std") { $0.has("std::") }
    b.add([.cpp], 8) { $0.starts("public:") || $0.starts("private:") || $0.starts("protected:") }
    b.add([.cpp], 8, word: "template") { $0.starts("template <") || $0.starts("template<") }
    b.add([.cpp], 8) { $0.has("cout") || $0.has("cin >>") || $0.has("std::endl") }
    b.add([.cpp], 6, word: "nullptr") { _ in true }
    b.add([.cpp], 3, word: "auto") { $0.starts("auto ") }
    b.add([.cpp], 6, word: "constexpr") { _ in true }
    b.add([.cpp], 4) { $0.has(") const") || $0.has("explicit ") || $0.has("virtual ") || $0.has(") override") }
    b.add([.cpp], 2, word: "inline") { $0.starts("inline ") }
    b.add([.cpp], 10, word: "using") { $0.starts("using namespace ") }
    b.add([.cpp], 4) { $0.has("const ") && $0.has("&") && !$0.has("&&") }
    b.add([.cpp], 3, word: "class") {
        $0.starts("class ") && ($0.endsWithOpenBrace || $0.has(" : public ")) && !$0.has("extends")
    }
    b.add([.cpp], 4) { line in
        line.has("unique_ptr<") || line.has("shared_ptr<") || line.has("vector<") || line.has("make_unique<")
    }
    b.add([.cpp], 3) { $0.bytes.hasPrefix("~") && $0.has("()") }
    b.add([.cpp], 2) { $0.has("::") && !$0.has("std::") && !$0.has(" :: ") }
}
