import Foundation

// The cheap, language-independent facts that `CodeDetector` starts from (Plan 4 Task 4, spec §8.1). Everything here
// reads UTF-8 bytes in one pass over the lines: no regular expressions, no randomness and no dictionary that is
// iterated, so the same text always gives the same numbers.

// MARK: Bytes

/// ASCII character classes over UTF-8 bytes. Every byte of a multi-byte character counts as a letter.
enum Byte {
    static func isUpper(_ byte: UInt8) -> Bool { byte >= 0x41 && byte <= 0x5A }
    static func isHexDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (byte >= 0x41 && byte <= 0x46) || (byte >= 0x61 && byte <= 0x66)
    }
    static func isLower(_ byte: UInt8) -> Bool { byte >= 0x61 && byte <= 0x7A }
    static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
    static func isLetter(_ byte: UInt8) -> Bool { isUpper(byte) || isLower(byte) || byte >= 0x80 }
    static func isIdentifier(_ byte: UInt8) -> Bool { isLetter(byte) || isDigit(byte) || byte == 0x5F }
    static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }
}

extension [UInt8] {
    /// The index of the first occurrence of `needle` at or after `start`.
    func index(of needle: StaticString, from start: Int = 0) -> Int? {
        needle.withUTF8Buffer { pattern in
            let length = pattern.count
            guard length > 0 else { return start }
            guard count >= length, start >= 0 else { return nil }
            let last = count - length
            var index = start
            while index <= last {
                if self[index] == pattern[0] {
                    var offset = 1
                    while offset < length, self[index + offset] == pattern[offset] {
                        offset += 1
                    }
                    if offset == length { return index }
                }
                index += 1
            }
            return nil
        }
    }

    func contains(_ needle: StaticString) -> Bool { index(of: needle) != nil }

    func hasPrefix(_ prefix: StaticString) -> Bool {
        prefix.withUTF8Buffer { pattern in
            guard count >= pattern.count else { return false }
            for offset in 0..<pattern.count where self[offset] != pattern[offset] {
                return false
            }
            return true
        }
    }

    func hasSuffix(_ suffix: StaticString) -> Bool {
        suffix.withUTF8Buffer { pattern in
            guard count >= pattern.count else { return false }
            let start = count - pattern.count
            for offset in 0..<pattern.count where self[start + offset] != pattern[offset] {
                return false
            }
            return true
        }
    }
}

// MARK: Word lists

/// Words that start a statement in some language Scratch knows (lower case; SQL is also matched in upper case).
private let statementKeywords: Set<String> = [
    "if", "else", "elif", "for", "foreach", "while", "do", "switch", "case", "return", "break", "continue", "func",
    "function", "def", "fn", "class", "struct", "enum", "interface", "protocol", "extension", "import", "from",
    "export",
    "package", "namespace", "using", "use", "let", "var", "val", "const", "static", "public", "private", "protected",
    "final", "async", "await", "try", "catch", "except", "finally", "throw", "raise", "new", "delete", "typedef",
    "template", "impl", "mod", "pub", "type", "guard", "defer", "select", "insert", "update", "create", "alter", "drop",
    "where", "join", "lambda", "pass", "echo", "param", "include", "define",
]

/// Commands that mean a shell when a line starts with one (case sensitive).
private let shellCommands: Set<String> = [
    "git", "npm", "npx", "yarn", "pnpm", "pip", "pip3", "brew", "apt", "apt-get", "yum", "dnf", "curl", "wget",
    "docker",
    "docker-compose", "kubectl", "helm", "terraform", "cargo", "rustup", "xcodebuild", "xcrun", "python3", "dotnet",
    "gradle", "mvn", "sudo", "chmod", "chown", "mkdir", "rmdir", "ssh", "scp", "rsync", "tar", "gzip", "gunzip",
    "unzip",
    "grep", "sed", "awk", "cd", "ls", "cat", "echo", "export", "touch", "cp", "mv", "rm", "ln", "tail", "head", "wc",
    "xargs", "tee", "diff", "systemctl", "make", "cmake", "vim", "nano", "tmux", "psql", "mysql", "sqlite3", "aws",
    "gcloud", "pwd", "whoami", "source", "alias", "kill", "killall", "df", "du", "find", "open", "ping", "tree", "sort",
    "uniq", "cut", "jq", "bundle", "gem", "rake", "pod", "gh", "which", "env", "unset", "exit", "sleep", "clear",
    "swift", "go", "python", "node", "java", "xcode-select", "softwareupdate", "defaults", "launchctl", "mdfind",
    "pbcopy", "pbpaste", "say", "caffeinate", "ffmpeg", "nvm", "pyenv", "venv", "conda", "pytest", "mypy", "ruff",
]

/// Shell commands that are also English words. A line starting with one is a command only with an argument that looks
/// like a shell one (a flag, a path, a variable, a pipe), or with a subcommand the tool really has.
private let ambiguousCommands: Set<String> = [
    "make", "open", "find", "sort", "cat", "go", "head", "tail", "tree", "source", "alias", "kill", "env", "exit",
    "sleep", "java", "swift", "python", "node", "which", "say", "clear", "cut", "diff", "ping", "pod", "gem", "export",
    "defaults", "bundle", "unset", "touch", "tee", "ln", "du", "df", "brew", "curl", "tar",
]

private let subcommands: [String: Set<String>] = [
    "swift": ["build", "test", "run", "package", "format", "--version"],
    "go": ["build", "run", "test", "mod", "get", "fmt", "vet", "install", "generate", "version"],
    "make": ["clean", "all", "install", "test", "build", "lint", "project", "format"],
    "python": ["-m", "--version"],
    "node": ["--version"],
    "java": ["-jar", "-version"],
    "pod": ["install", "update"],
    "gem": ["install", "update"],
    "bundle": ["install", "exec", "update"],
    "brew": [
        "install", "upgrade", "update", "uninstall", "list", "tap", "search", "info", "doctor", "services", "cleanup",
        "remove", "reinstall", "outdated",
    ],
]

/// Commands that are a line by themselves.
private let bareCommands: Set<String> = ["ls", "pwd", "whoami", "clear", "exit", "tree", "df", "du", "env", "history"]

/// The verbs of PowerShell's `Verb-Noun` cmdlets.
private let cmdletVerbs: Set<String> = [
    "Get", "Set", "New", "Remove", "Write", "Read", "Out", "Add", "Invoke", "Start", "Stop", "Test", "Select", "Where",
    "ForEach", "Import", "Export", "Copy", "Move", "Rename", "Clear", "Format", "Measure", "Sort", "Group", "Join",
    "Split", "Enable", "Disable", "Install", "Uninstall", "Find", "Update", "Wait", "Register", "Compare", "ConvertTo",
    "ConvertFrom", "Resolve", "Restart", "Show", "Send", "Receive", "Connect", "Disconnect", "Push", "Pop", "Enter",
    "Exit", "Expand", "Compress", "Unregister", "Grant", "Revoke", "Lock", "Unlock", "Publish", "Save", "Use",
]

/// The words that start a declaration that assigns (`const x = 1`).
private let declarationKeywords: Set<String> = ["const", "let", "var", "val", "final"]

/// The lower case letters a line starts with, as a word.
private func leadingLowercaseWord(_ bytes: [UInt8]) -> String {
    var end = 0
    while end < bytes.count, Byte.isLower(bytes[end]) {
        end += 1
    }
    return String(decoding: bytes[0..<end], as: UTF8.self)
}

/// The names of HTML elements (lower case).
let htmlTagNames: Set<String> = [
    "div", "span", "p", "a", "ul", "li", "ol", "nav", "form", "input", "label", "button", "h1", "h2", "h3", "h4",
    "h5", "h6", "table", "tr", "td", "th", "thead", "tbody", "img", "br", "section", "header", "footer", "main",
    "script", "style", "link", "meta", "title", "head", "body", "html", "article", "aside", "select", "option",
    "textarea", "pre", "code", "em", "strong", "i", "b", "hr", "iframe", "svg", "canvas", "video", "audio", "details",
    "summary",
]

/// The words that start the statements of SQL, and the ones that continue them.
private let sqlStarters: Set<String> = ["select", "insert", "update", "delete", "create", "alter", "drop", "with"]
private let sqlContinuations: Set<String> = [
    "from", "where", "join", "left", "right", "inner", "outer", "group", "order", "having", "limit", "offset",
    "values", "set", "union", "into",
]

/// Properties that make a `name: value;` line CSS (a property with a hyphen is CSS as well).
private let cssProperties: Set<String> = [
    "color", "background", "margin", "padding", "border", "display", "width", "height", "font", "position", "top",
    "left", "right", "bottom", "flex", "grid", "opacity", "overflow", "content", "cursor", "transition", "transform",
    "outline", "float", "clear", "visibility", "gap", "order", "filter", "animation", "fill", "stroke", "resize",
    "direction", "appearance", "columns", "inset", "isolation", "quotes", "src", "size", "zoom", "gap", "all",
]

/// Words that open a block, so that `word {` is a statement and not a CSS selector.
private let blockKeywords: Set<String> = [
    "if", "else", "for", "foreach", "while", "do", "switch", "try", "catch", "finally", "func", "function", "class",
    "struct", "enum", "interface", "impl", "fn", "loop", "match", "defer", "guard", "init", "static", "namespace",
    "extension", "protocol", "union", "trait", "mod", "unsafe", "async", "return", "default", "case", "get", "set",
    "willSet", "didSet", "deinit", "subscript", "extern", "using", "lock", "checked", "unchecked", "fixed", "public",
    "private", "protected", "internal", "open", "abstract", "sealed", "partial", "export", "final", "data", "object",
    "record", "fileprivate", "override", "pub", "const", "let", "var", "val", "typedef", "template", "type", "where",
    "new", "catch",
]

// MARK: One line

/// One non-blank line of the text under test, trimmed, with the facts the detector asks of it.
struct DetectionLine {
    /// The line without the white space around it, and without what is between backticks: the inline code of a
    /// Markdown note (`call `init()` first`) is a word of the sentence, not code. Every other fact is read from this.
    let bytes: [UInt8]
    /// The columns of white space before it (a tab counts as four).
    let indent: Int
    /// The identifier words of the line, in order (`[A-Za-z_][A-Za-z0-9_]*`).
    let words: [String]
    /// The first word when the line starts with one, otherwise "".
    let firstWord: String
    /// The number of runs of non-blank characters.
    let tokenCount: Int
    /// The share of the characters that are not white space and are symbols (`{}[]()<>=;:$#@*&|`).
    let symbolDensity: Double

    let endsWithCodePunctuation: Bool
    let endsWithSemicolon: Bool
    let endsWithOpenBrace: Bool
    let endsWithCloseBrace: Bool
    /// Code, then a `// comment`.
    let hasTrailingComment: Bool
    /// A line of closing brackets and separators only: `}`, `});`, `],`.
    let isCloser: Bool
    let hasCall: Bool
    /// The first word of the line is a call: `print(x)`, `foo.bar(1)`.
    let startsWithCall: Bool
    let hasStrongOperator: Bool
    let hasArrow: Bool
    let isSimpleAssignment: Bool
    /// `from a import b`, and `import a.b` with nothing else on the line.
    let isImport: Bool
    /// A line that closes a block with a word: `end`, `fi`, `done`, `esac`.
    let isBlockEnd: Bool
    /// `const x = 1`, `let y = foo`, `var z: Int = 3`: a declaration that assigns.
    let isDeclaration: Bool
    /// A flag of a command on a line of its own (`--data-raw '{}'`, `-H "Accept: text/html"`).
    let isFlagLine: Bool
    /// A line that ends in a backslash: the command goes on.
    let endsWithContinuation: Bool
    /// A rule of repeated symbols (`=====`, `-----`, `| --- | --- |`).
    let isSeparator: Bool
    /// Nothing but letters, digits, spaces and the punctuation of prose.
    let isPureProse: Bool
    let startsWithComment: Bool
    /// A comment of the `# text` kind: a Python, shell or YAML comment, or a Markdown heading.
    let isHashComment: Bool
    let isPreprocessor: Bool
    let hasHTMLTag: Bool
    let hasShellVariable: Bool
    let isDecorator: Bool
    let isPythonOpener: Bool
    let isJSONKeyLine: Bool
    let isCSSDeclaration: Bool
    let isShellCommand: Bool
    let hasCmdlet: Bool
    let isKeywordStart: Bool
    /// A line of SQL: its first word is a statement or clause word, all in lower case or all in upper case.
    let isSQLKeywordLine: Bool
    /// A whole sentence: a capital, four words or more, little but letters, and a full stop at the end.
    let isSentence: Bool
    /// Six words or more and little but letters, with no end to the sentence: a line of a wrapped paragraph.
    let isWrappedProse: Bool

    init(bytes raw: [UInt8], indent: Int) {
        let bytes = DetectionLine.maskingInlineCode(raw)
        self.bytes = bytes
        self.indent = indent
        let last = bytes[bytes.count - 1]

        // Counts over the characters.
        var tokenCount = 0
        var inToken = false
        var symbols = 0
        var nonSpace = 0
        var wordy = 0
        for byte in bytes {
            if Byte.isSpace(byte) {
                inToken = false
                continue
            }
            nonSpace += 1
            if !inToken {
                tokenCount += 1
                inToken = true
            }
            if DetectionLine.isSymbol(byte) { symbols += 1 }
            if DetectionLine.isProseCharacter(byte) { wordy += 1 }
        }

        // Words.
        var words: [String] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if Byte.isLetter(byte) || byte == 0x5F {
                var end = index + 1
                while end < bytes.count, Byte.isIdentifier(bytes[end]) {
                    end += 1
                }
                words.append(String(decoding: bytes[index..<end], as: UTF8.self))
                index = end
            } else if Byte.isDigit(byte) {
                // A number: its letters (`10px`, `0x1F`) are not words.
                var end = index + 1
                while end < bytes.count, Byte.isIdentifier(bytes[end]) {
                    end += 1
                }
                index = end
            } else {
                index += 1
            }
        }
        self.words = words
        self.tokenCount = tokenCount
        self.firstWord = Byte.isLetter(bytes[0]) || bytes[0] == 0x5F ? (words.first ?? "") : ""
        self.symbolDensity = nonSpace == 0 ? 0 : Double(symbols) / Double(nonSpace)

        // Endings.
        self.endsWithSemicolon = last == 0x3B
        self.endsWithOpenBrace = last == 0x7B
        self.endsWithCloseBrace = last == 0x7D
        self.hasTrailingComment = bytes.contains(" // ") || bytes.contains("\t// ")
        self.endsWithCodePunctuation = DetectionLine.codeEndings.contains(last)
        self.isCloser = bytes.allSatisfy { DetectionLine.closerBytes.contains($0) }

        // Operators and calls.
        self.hasCall = DetectionLine.findsCall(in: bytes)
        self.startsWithCall = DetectionLine.findsCall(in: Array(bytes.prefix { !Byte.isSpace($0) }))
        self.hasStrongOperator = DetectionLine.findsOperator(in: bytes)
        self.hasArrow = bytes.contains("->")
        self.isSimpleAssignment = DetectionLine.isAssignment(bytes)
        self.isImport = DetectionLine.isImportLine(bytes)
        self.endsWithContinuation = bytes.hasSuffix(" \\")
        self.isFlagLine = DetectionLine.isFlag(bytes)
        let declaring = leadingLowercaseWord(bytes)
        if declarationKeywords.contains(declaring) {
            self.isDeclaration = DetectionLine.isAssignment(Array(bytes.dropFirst(declaring.utf8.count + 1)))
        } else {
            self.isDeclaration = false
        }
        self.isBlockEnd = DetectionLine.blockEnds.contains(bytes)
        self.isSeparator =
            bytes.count >= 3 && bytes.allSatisfy { Byte.isSpace($0) || DetectionLine.separatorBytes.contains($0) }
        self.isPureProse = wordy == nonSpace

        // Comments and markers.
        let startsWithSlashComment = bytes.hasPrefix("//") || bytes.hasPrefix("/*") || bytes.hasPrefix("*/")
        self.startsWithComment =
            startsWithSlashComment || bytes.hasPrefix("#!") || bytes.hasPrefix("<!--")
        self.isHashComment =
            bytes[0] == 0x23 && (bytes.count == 1 || bytes[1] == 0x20) || bytes.hasPrefix("## ")
        self.isPreprocessor = DetectionLine.isPreprocessorLine(bytes)
        self.hasHTMLTag = DetectionLine.findsHTMLTag(in: bytes)
        self.hasShellVariable = DetectionLine.findsShellVariable(in: bytes)
        self.isDecorator = DetectionLine.isDecoratorLine(bytes)
        self.isJSONKeyLine = DetectionLine.isJSONKey(bytes)
        self.isCSSDeclaration = DetectionLine.isCSSDeclarationLine(bytes, last: last)

        // Words that decide.
        let first = self.firstWord
        self.isKeywordStart =
            statementKeywords.contains(first)
            || statementKeywords.contains(first.lowercased())
                && first.uppercased() == first
        self.isPythonOpener = DetectionLine.isPythonBlockOpener(first: first, last: last, bytes: bytes)
        self.isShellCommand = DetectionLine.isShellCommandLine(bytes: bytes)
        self.hasCmdlet = DetectionLine.findsCmdlet(in: bytes)
        let lowered = first.lowercased()
        let consistentCase = first == lowered || first == first.uppercased()
        self.isSQLKeywordLine =
            consistentCase && (sqlStarters.contains(lowered) || sqlContinuations.contains(lowered))

        // Prose.
        let wordyShare = nonSpace == 0 ? 0 : Double(wordy) / Double(nonSpace)
        let startsWithCapital = Byte.isUpper(bytes[0])
        let endsSentence = last == 0x2E || last == 0x3F || last == 0x21
        self.isSentence = startsWithCapital && tokenCount >= 4 && wordyShare >= 0.95 && endsSentence
        self.isWrappedProse = tokenCount >= 6 && wordyShare >= 1 && last != 0x3B && last != 0x7B
    }

    /// `bytes` with every inline code span (between a pair of backticks) turned into letters. A line with an odd
    /// number of backticks (a fence, a continued line) is left as it is.
    static func maskingInlineCode(_ bytes: [UInt8]) -> [UInt8] {
        var ticks = 0
        for byte in bytes where byte == 0x60 {
            ticks += 1
        }
        guard ticks >= 2, ticks % 2 == 0, !bytes.contains("```") else { return bytes }
        var masked = bytes
        var inside = false
        for index in masked.indices {
            if masked[index] == 0x60 {
                inside.toggle()
            } else if inside {
                masked[index] = 0x78
            }
        }
        return masked
    }

    /// The last characters of a line that code has more often than prose: `;`, `{`, `}`, `)`, `:` and `,`.
    private static let codeEndings: Set<UInt8> = [0x3B, 0x7B, 0x7D, 0x29, 0x3A, 0x2C]
    /// The words that close a block by themselves.
    private static let blockEnds: [[UInt8]] = ["end", "fi", "done", "esac"].map { Array($0.utf8) }
    /// What a line of closers is made of: `}`, `)`, `]`, `;`, `,` and a space (`});`, `],`).
    private static let closerBytes: Set<UInt8> = [0x7D, 0x29, 0x5D, 0x3B, 0x2C, 0x20]
    /// The first characters of the operators of `findsOperator`.
    private static let operatorStarts: Set<UInt8> = [0x3D, 0x21, 0x3C, 0x3E, 0x26, 0x7C, 0x2B, 0x2D, 0x2A, 0x3A]
    /// What the type annotation of an assignment is made of, besides identifier characters.
    private static let annotationBytes: Set<UInt8> = [0x20, 0x5B, 0x5D, 0x3C, 0x3E, 0x2C, 0x2E, 0x7C, 0x3F]

    // MARK: Matching helpers

    func starts(_ prefix: StaticString) -> Bool { bytes.hasPrefix(prefix) }
    func ends(_ suffix: StaticString) -> Bool { bytes.hasSuffix(suffix) }
    func has(_ needle: StaticString) -> Bool { bytes.contains(needle) }

    /// The second word of the line.
    var secondWord: String { words.count > 1 ? words[1] : "" }

    /// Whether a `# comment` or `// comment` of any kind makes the line.
    var isComment: Bool { startsWithComment || isHashComment }

    // MARK: Scans

    private static func isSymbol(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x7B, 0x7D, 0x5B, 0x5D, 0x28, 0x29, 0x3C, 0x3E, 0x3D, 0x3B, 0x3A, 0x24, 0x23, 0x40, 0x2A, 0x26, 0x7C:
            return true
        default:
            return false
        }
    }

    /// Characters a sentence is made of: letters, digits, spaces and the punctuation of prose.
    private static func isProseCharacter(_ byte: UInt8) -> Bool {
        if Byte.isLetter(byte) || Byte.isDigit(byte) { return true }
        switch byte {
        case 0x2C, 0x2E, 0x27, 0x22, 0x2D, 0x21, 0x3F, 0x3A, 0x3B, 0x28, 0x29, 0x26, 0x25:
            return true
        default:
            return false
        }
    }

    /// An identifier of two characters or more that is followed at once by `(`, with the `)` on the line (or the call
    /// opening at the end of it). `item(s)` and `(es)` are plurals, not calls.
    private static func findsCall(in bytes: [UInt8]) -> Bool {
        var index = 1
        while index < bytes.count {
            if bytes[index] == 0x28, Byte.isIdentifier(bytes[index - 1]) {
                var start = index - 1
                while start > 0, Byte.isIdentifier(bytes[start - 1]) {
                    start -= 1
                }
                if index - start >= 2 {
                    if index == bytes.count - 1 { return true }
                    var close = index + 1
                    while close < bytes.count, bytes[close] != 0x29 {
                        close += 1
                    }
                    if close < bytes.count {
                        let inner = bytes[(index + 1)..<close]
                        let plural = inner.elementsEqual([0x73]) || inner.elementsEqual([0x65, 0x73])
                        if !plural { return true }
                    }
                }
            }
            index += 1
        }
        return false
    }

    /// `name = value`, `a.b[0] += value`, `x := value`, `@name = value`, `title: str = ""`: an assignment to one name,
    /// with something after it. A line with two `=` (`time=10 level=info`, `a = b = c`) is not counted.
    private static func isAssignment(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count, bytes[index] == 0x40 || bytes[index] == 0x24 {
            index += 1
        }
        guard index < bytes.count, Byte.isLetter(bytes[index]) || bytes[index] == 0x5F else { return false }
        guard bytes.lazy.filter({ $0 == 0x3D }).count == 1 else { return false }
        while index < bytes.count {
            let byte = bytes[index]
            guard Byte.isIdentifier(byte) || byte == 0x2E || byte == 0x5B || byte == 0x5D else { break }
            index += 1
        }
        while index < bytes.count, Byte.isSpace(bytes[index]) {
            index += 1
        }
        guard index < bytes.count else { return false }

        // A type annotation: `title: str = ""`, `count: Int = 0`.
        if bytes[index] == 0x3A, index + 1 < bytes.count, bytes[index + 1] == 0x20,
            let equals = bytes.firstIndex(of: 0x3D), equals > index
        {
            let annotation = bytes[(index + 1)..<equals]
            let plain = annotation.allSatisfy {
                Byte.isIdentifier($0) || annotationBytes.contains($0)
            }
            guard plain else { return false }
            index = equals
        }

        var operatorEnd = index
        let byte = bytes[index]
        let next: UInt8 = index + 1 < bytes.count ? bytes[index + 1] : 0
        switch byte {
        case 0x3D:
            guard next != 0x3D, next != 0x3E else { return false }
            operatorEnd = index + 1
        case 0x3A, 0x2B, 0x2D, 0x2A, 0x2F, 0x25, 0x7C, 0x26, 0x5E:
            guard next == 0x3D else { return false }
            operatorEnd = index + 2
        default:
            return false
        }
        while operatorEnd < bytes.count, Byte.isSpace(bytes[operatorEnd]) {
            operatorEnd += 1
        }
        return operatorEnd < bytes.count
    }

    /// Operators that only code has, with something on both sides of them: `a == b`, `x != y`, `Foo::bar`, `a && b`.
    /// `== History ==` is a heading and `>>` at the end of a line is not an operator.
    private static let operators: [[UInt8]] = [
        "==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", ":=", "::", "<<", ">>", "=>", "++;", "++)",
    ].map { Array($0.utf8) }

    private static func findsOperator(in bytes: [UInt8]) -> Bool {
        guard bytes.count >= 3 else { return false }
        var index = 1
        while index < bytes.count - 1 {
            let byte = bytes[index]
            // Every operator starts with one of these.
            if operatorStarts.contains(byte) {
                for pattern in operators where bytes[index] == pattern[0] && index + pattern.count <= bytes.count {
                    var matches = true
                    for offset in 1..<pattern.count where bytes[index + offset] != pattern[offset] {
                        matches = false
                        break
                    }
                    if matches && (index + pattern.count < bytes.count || pattern.last == 0x3B || pattern.last == 0x29)
                    {
                        return true
                    }
                }
            }
            index += 1
        }
        return false
    }

    /// `--name` or `-n` as the first word of a line, with an argument or nothing after it.
    private static func isFlag(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2, bytes[0] == 0x2D else { return false }
        if bytes[1] == 0x2D { return bytes.count > 2 && Byte.isLetter(bytes[2]) }
        guard Byte.isLetter(bytes[1]) else { return false }
        return bytes.count == 2 || bytes[2] == 0x20
    }

    /// The bytes a rule of repeated symbols is made of.
    private static let separatorBytes: Set<UInt8> = [0x3D, 0x2D, 0x5F, 0x2A, 0x23, 0x7E, 0x2B, 0x2E, 0x3A, 0x7C]

    /// `from a import b`, and `import a`, `import a.b`, `import a as b`, `@testable import A` with nothing else on the
    /// line.
    private static func isImportLine(_ bytes: [UInt8]) -> Bool {
        if bytes.hasPrefix("from "), bytes.contains(" import "), !bytes.contains(";") { return true }
        let line: [UInt8] = bytes.hasPrefix("@testable ") ? Array(bytes.dropFirst(10)) : bytes
        guard line.hasPrefix("import "), line.count > 7, Byte.isLetter(line[7]) else { return false }
        for byte in line.dropFirst(7) {
            let allowed = Byte.isIdentifier(byte) || byte == 0x2E || byte == 0x20 || byte == 0x2C
            if !allowed { return false }
        }
        return line.split(separator: 0x20).count <= 4
    }

    private static let preprocessorWords: Set<String> = [
        "include", "define", "if", "ifdef", "ifndef", "endif", "else", "elif", "pragma", "import", "undef", "error",
        "region", "endregion", "warning",
    ]

    private static func isPreprocessorLine(_ bytes: [UInt8]) -> Bool {
        guard bytes[0] == 0x23, bytes.count > 1 else { return false }
        let index = 1
        var end = index
        while end < bytes.count, Byte.isLetter(bytes[end]) {
            end += 1
        }
        guard end > index else { return false }
        return preprocessorWords.contains(String(decoding: bytes[index..<end], as: UTF8.self))
    }

    /// A tag of HTML or JSX: `<div>`, `<input type="email">`, `</p>`, `<Counter />`, `<br/>`, `<!DOCTYPE html>`,
    /// `<!-- -->`. A tag that is not an HTML one needs to close, to close itself or to have an attribute with a quoted
    /// value, so that `<name>`, `<Enter>`, `List<String>` and `Kate <kate@example.com>` are not tags.
    private static func findsHTMLTag(in bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count - 1 {
            guard bytes[index] == 0x3C else {
                index += 1
                continue
            }
            var start = index + 1
            let closing = bytes[start] == 0x2F
            if closing { start += 1 }
            guard start < bytes.count else { return false }
            if bytes[start] == 0x21 { return true }
            if Byte.isLetter(bytes[start]) {
                var end = start + 1
                while end < bytes.count, Byte.isIdentifier(bytes[end]) || bytes[end] == 0x2D {
                    end += 1
                }
                let known = htmlTagNames.contains(String(decoding: bytes[start..<end], as: UTF8.self).lowercased())
                if end < bytes.count {
                    let next = bytes[end]
                    if next == 0x3E {
                        if known || closing { return true }
                    } else if next == 0x2F {
                        if end + 1 < bytes.count, bytes[end + 1] == 0x3E { return true }
                    } else if Byte.isSpace(next) {
                        var cursor = end
                        while cursor < bytes.count, Byte.isSpace(bytes[cursor]) {
                            cursor += 1
                        }
                        if cursor + 1 < bytes.count, bytes[cursor] == 0x2F, bytes[cursor + 1] == 0x3E { return true }
                        let attribute = cursor
                        while cursor < bytes.count, Byte.isIdentifier(bytes[cursor]) || bytes[cursor] == 0x2D {
                            cursor += 1
                        }
                        if cursor > attribute, cursor + 1 < bytes.count, bytes[cursor] == 0x3D {
                            let value = bytes[cursor + 1]
                            if known || value == 0x22 || value == 0x27 || value == 0x7B { return true }
                        }
                    }
                }
            }
            index += 1
        }
        return false
    }

    /// `$name`, `${name}` and `$(command)`. `$5` is money.
    private static func findsShellVariable(in bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count - 1 {
            if bytes[index] == 0x24 {
                let next = bytes[index + 1]
                if Byte.isLetter(next) || next == 0x5F || next == 0x7B || next == 0x28 { return true }
            }
            index += 1
        }
        return false
    }

    /// `@Name`, `@Name(arguments)` and `@pkg.Name` on a line of its own, and nothing else on the line. `@dana can you
    /// look?` is a mention.
    private static func isDecoratorLine(_ bytes: [UInt8]) -> Bool {
        guard bytes[0] == 0x40, bytes.count > 1, Byte.isLetter(bytes[1]) else { return false }
        var index = 1
        while index < bytes.count, Byte.isIdentifier(bytes[index]) || bytes[index] == 0x2E {
            index += 1
        }
        if index == bytes.count { return true }
        return bytes[index] == 0x28 && bytes[bytes.count - 1] == 0x29
    }

    /// `"key": value` (the value may be missing at the end of a line: `"items": [`).
    private static func isJSONKey(_ bytes: [UInt8]) -> Bool {
        guard bytes[0] == 0x22 else { return false }
        var index = 1
        while index < bytes.count, bytes[index] != 0x22 {
            if bytes[index] == 0x5C { index += 1 }
            index += 1
        }
        index += 1
        while index < bytes.count, Byte.isSpace(bytes[index]) {
            index += 1
        }
        return index < bytes.count && bytes[index] == 0x3A
    }

    /// `property: value;` where the property is one CSS has.
    private static func isCSSDeclarationLine(_ bytes: [UInt8], last: UInt8) -> Bool {
        guard last == 0x3B, Byte.isLower(bytes[0]) || bytes[0] == 0x2D else { return false }
        var end = 0
        while end < bytes.count, Byte.isLower(bytes[end]) || bytes[end] == 0x2D {
            end += 1
        }
        guard end < bytes.count, bytes[end] == 0x3A else { return false }
        let property = String(decoding: bytes[0..<end], as: UTF8.self)
        return property.contains("-") || cssProperties.contains(property)
    }

    private static let pythonOpeners: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "try", "except", "finally", "with", "async", "match",
        "case",
    ]

    /// `def f(x):`, `class A:`, `if x == 1:`, `else:` and the like.
    private static func isPythonBlockOpener(first: String, last: UInt8, bytes: [UInt8]) -> Bool {
        guard last == 0x3A, pythonOpeners.contains(first) else { return false }
        switch first {
        case "else", "try", "finally":
            return bytes.count == first.utf8.count + 1
        case "def", "class", "async":
            return bytes.contains("(") || first == "class"
        default:
            // `for example:` is a sentence. A condition has an operator, a call, a name to loop over or a bracket.
            return bytes.contains("(") || bytes.contains("==") || bytes.contains("!=") || bytes.contains(" in ")
                || bytes.contains(" as ") || bytes.contains(" not ") || bytes.contains("<") || bytes.contains(">")
                || bytes.contains(" is ") || bytes.contains("[") || bytes.contains(" and ") || bytes.contains(" or ")
        }
    }

    /// A line that is a shell command: `$ git status`, `npm install`, `ls -la | wc -l`, `cd ..`.
    private static func isShellCommandLine(bytes: [UInt8]) -> Bool {
        let hasPrompt = bytes.hasPrefix("$ ") && bytes.count > 2
        let line = hasPrompt ? Array(bytes[2...]) : bytes
        guard let first = line.first else { return false }
        if hasPrompt {
            // After a prompt, a command, a path or a script.
            guard Byte.isLower(first) || first == 0x2E || first == 0x2F || first == 0x7E else { return false }
        } else if first == 0x2E {
            // `./build.sh`, `../run`: a script called by its path.
            return line.hasPrefix("./") || line.hasPrefix("../")
        } else if !Byte.isLower(first) {
            return false
        }
        var tokens: [[UInt8]] = []
        var current: [UInt8] = []
        for byte in line {
            if Byte.isSpace(byte) {
                if !current.isEmpty { tokens.append(current) }
                current = []
            } else {
                current.append(byte)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        guard let head = tokens.first else { return false }
        let command = String(decoding: head, as: UTF8.self)
        guard shellCommands.contains(command) else { return hasPrompt }
        if tokens.count == 1 {
            return bareCommands.contains(command)
        }
        let lastToken = tokens[tokens.count - 1]
        let lastByte = lastToken[lastToken.count - 1]
        if [0x2E, 0x3F, 0x21].contains(lastByte) && lastToken != [0x2E] && lastToken != [0x2E, 0x2E] {
            return false
        }
        let arguments = tokens.dropFirst()
        let shellish = arguments.contains { token in
            let b = token[0]
            return b == 0x2D || b == 0x2F || b == 0x7E || b == 0x24 || b == 0x22 || b == 0x27 || b == 0x2E
                || token.contains(0x7C) || token.contains(0x3D) || token.contains(0x2A) || token.contains(0x3E)
                || token.contains(0x3C) || token.contains(0x26) || token.contains(0x2F)
        }
        if ambiguousCommands.contains(command) {
            if shellish { return true }
            let second = String(decoding: tokens[1], as: UTF8.self)
            return subcommands[command]?.contains(second) ?? false
        }
        if tokens.count > 5 { return shellish }
        return true
    }

    /// `Get-Process`, `Write-Host`: a known verb, a hyphen and a capitalised noun.
    private static func findsCmdlet(in bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count {
            if Byte.isUpper(bytes[index]), index == 0 || !Byte.isIdentifier(bytes[index - 1]) {
                var end = index + 1
                while end < bytes.count, Byte.isLetter(bytes[end]) {
                    end += 1
                }
                if end + 1 < bytes.count, bytes[end] == 0x2D, Byte.isUpper(bytes[end + 1]) {
                    let verb = String(decoding: bytes[index..<end], as: UTF8.self)
                    if cmdletVerbs.contains(verb) { return true }
                }
                index = end
            } else {
                index += 1
            }
        }
        return false
    }

    private static let selectorPunctuation: Set<UInt8> = [
        0x2E, 0x23, 0x3A, 0x3E, 0x2B, 0x7E, 0x2C, 0x5B, 0x5D, 0x3D, 0x22, 0x27, 0x2A, 0x20, 0x2D, 0x28, 0x29,
    ]

    /// `selector {` in CSS: no keyword that opens a statement and no call before the brace.
    var isCSSSelector: Bool {
        guard endsWithOpenBrace, bytes.count > 1 else { return false }
        if bytes[0] == 0x40 {
            return starts("@media") || starts("@supports") || starts("@font-face") || starts("@keyframes")
                || starts("@layer") || starts("@container")
        }
        guard !blockKeywords.contains(firstWord) else { return false }
        guard
            bytes[0] == 0x2E || bytes[0] == 0x23 || bytes[0] == 0x3A || bytes[0] == 0x2A || bytes[0] == 0x5B
                || Byte.isLower(bytes[0])
        else { return false }
        for byte in bytes.dropLast() where !Byte.isIdentifier(byte) && !DetectionLine.selectorPunctuation.contains(byte)
        {
            return false
        }
        return !hasCall
    }

    // MARK: A `key: value` line of YAML

    /// The key of a `key: value` line, `- key: value` list items included, when it reads as YAML: an identifier that
    /// is not a capitalised word (`Subject:` and `Date:` are labels of prose), with a value that is empty, short,
    /// quoted or a flow collection. Python's `else:` is no key.
    var yamlEntry: (key: String, isConfiguration: Bool)? {
        var start = 0
        if bytes.hasPrefix("- ") {
            start = 2
            while start < bytes.count, Byte.isSpace(bytes[start]) {
                start += 1
            }
        }
        guard start < bytes.count, Byte.isLetter(bytes[start]) || bytes[start] == 0x5F else { return nil }
        var end = start
        while end < bytes.count, Byte.isIdentifier(bytes[end]) || bytes[end] == 0x2D || bytes[end] == 0x2E {
            end += 1
        }
        guard end < bytes.count, bytes[end] == 0x3A else { return nil }
        if end + 1 < bytes.count, bytes[end + 1] != 0x20 { return nil }
        let key = String(decoding: bytes[start..<end], as: UTF8.self)
        guard !DetectionLine.yamlReservedKeys.contains(key) else { return nil }

        // A label of prose is a capitalised word (`Date`) or a single capital letter; a key starts with a lower case
        // letter, or is an environment variable (`POSTGRES_PASSWORD`).
        guard Byte.isLower(bytes[start]) || key.contains("_") else { return nil }

        // The value.
        var valueStart = end + 1
        while valueStart < bytes.count, Byte.isSpace(bytes[valueStart]) {
            valueStart += 1
        }
        var value = Array(bytes[min(valueStart, bytes.count)...])
        if let hash = value.index(of: " #") { value = Array(value[..<hash]) }
        while let tail = value.last, Byte.isSpace(tail) {
            value.removeLast()
        }
        // A trailing comma or a call is Swift or JavaScript, not YAML: `name: "ScratchCode",`, `files: [.f("a")]`.
        if let tail = value.last, tail == 0x2C || tail == 0x28 || tail == 0x29 { return nil }
        if DetectionLine.findsCall(in: value) { return nil }
        if value.isEmpty { return (key, false) }
        if value.contains("=") && !value.hasPrefix("\"") && !value.hasPrefix("'") { return nil }
        // `isEmpty: Bool; hasTitle: Bool` is a pair of declarations: a `;` or a second `: ` is not in a plain value.
        if !value.hasPrefix("\"") && !value.hasPrefix("'") && (value.contains(";") || value.contains(": ")) {
            return nil
        }
        if let firstValue = value.first, [0x22, 0x27, 0x5B, 0x7B, 0x7C, 0x3E, 0x26, 0x2A, 0x21].contains(firstValue) {
            return (key, true)
        }
        let valueTokens = value.split(separator: 0x20).count
        let valueEndsSentence = [0x2E, 0x3F, 0x21].contains(value[value.count - 1])
        guard valueTokens <= 4, !valueEndsSentence else { return nil }
        // A value that is more than plain words (a number, a version, a path, `true`) reads as configuration.
        let plainWords = value.allSatisfy { Byte.isLetter($0) || $0 == 0x20 }
        return (key, !plainWords)
    }

    /// The key of a `key: value` line of YAML, nil when the line is not one.
    var yamlKey: String? { yamlEntry?.key }

    private static let yamlReservedKeys: Set<String> = [
        "else", "try", "finally", "default", "do", "then", "begin", "http", "https", "ftp", "file", "mailto",
    ]
}

// MARK: The text

/// What `CodeDetector` knows of a text before it asks which language it is: the lines, a handful of shares, and the
/// shapes (JSON, YAML, SQL) and markers (shebang, XML declaration, doctype) that decide on their own.
///
/// Only a prefix of a long text is looked at (`maximumLines`, `maximumBytes`), so that the cost stays bounded.
struct DetectionFeatures {
    static let maximumLines = 300
    static let maximumBytes = 40_000
    /// The prefix of the text that is parsed to compare grammars (at most this many lines and bytes).
    static let parseLines = 50
    static let parseBytes = 4_000

    /// The non-blank lines, at most `maximumLines`.
    let lines: [DetectionLine]
    /// The first lines of the text as they are, for parsing (indentation matters to some grammars).
    let sample: String
    /// The number of lines that are not blank in the part of the text that is read (`maximumBytes`).
    let nonBlankLineCount: Int

    // The features of the plan, as shares of the lines read.
    /// Lines that end in `;`, `{`, `}`, `)`, `:` or `,`.
    let endingShare: Double
    /// Lines that start with two columns of white space or more.
    let indentShare: Double
    /// Symbols (`{}[]()<>=;:$#@*&|`) over the characters that are not white space.
    let symbolDensity: Double
    /// Lines that start with a keyword of some language.
    let keywordShare: Double
    /// Lines that are sentences.
    let sentenceShare: Double

    /// The first line when it is a shebang (`#!/usr/bin/env python3`), without the `#!`.
    let shebang: String?
    let hasXMLDeclaration: Bool
    let hasPHPTag: Bool
    let hasDoctype: Bool
    let hasHTMLRoot: Bool
    /// The whole text is a JSON document (an object or an array), `//` and `/* */` comments allowed.
    let isJSON: Bool
    let isYAMLShaped: Bool
    let isSQLShaped: Bool

    /// A shape or a marker that says "code" without the lines having to: JSON, YAML, SQL, a shebang, a doctype.
    let isShaped: Bool

    /// The mean evidence of the lines, -1 (prose) to 1 (code), with the hard and soft evidence counted.
    let evidence: Double
    /// The lines that have a marker only code has.
    let hardLineCount: Int
    /// The lines of code that have syntax in them (a call, an operator, a block opening), not only a `;` or a `}`.
    let strongLineCount: Int

    init(text: String) {
        // The prefix that is read.
        let units = Array(text.utf8.prefix(DetectionFeatures.maximumBytes))
        var lines: [DetectionLine] = []
        var parseEnd = 0
        var parseLineCount = 0
        var lineStart = 0
        var nonBlank = 0
        var index = 0
        func finishLine(upTo end: Int, next: Int) {
            var from = lineStart
            var to = end
            var indent = 0
            while from < to, Byte.isSpace(units[from]) || units[from] == 0x0B || units[from] == 0x0C {
                indent += units[from] == 0x09 ? 4 : 1
                from += 1
            }
            while to > from, Byte.isSpace(units[to - 1]) || units[to - 1] == 0x0B || units[to - 1] == 0x0C {
                to -= 1
            }
            if to > from {
                nonBlank += 1
                if lines.count < DetectionFeatures.maximumLines {
                    lines.append(DetectionLine(bytes: Array(units[from..<to]), indent: indent))
                }
            }
            if parseLineCount < DetectionFeatures.parseLines, next <= DetectionFeatures.parseBytes {
                parseLineCount += 1
                parseEnd = next
            }
            lineStart = next
        }
        while index < units.count {
            let byte = units[index]
            if byte == 0x0A {
                finishLine(upTo: index, next: index + 1)
            } else if byte == 0x0D {
                let next = index + 1 < units.count && units[index + 1] == 0x0A ? index + 2 : index + 1
                finishLine(upTo: index, next: next)
                index = next - 1
            }
            index += 1
        }
        if lineStart < units.count {
            finishLine(upTo: units.count, next: units.count)
        }
        self.lines = lines
        self.nonBlankLineCount = nonBlank
        let sampleUnits = parseEnd > 0 ? Array(units[0..<parseEnd]) : Array(units.prefix(DetectionFeatures.parseBytes))
        self.sample = String(decoding: sampleUnits, as: UTF8.self)

        // The shares.
        let count = Double(max(lines.count, 1))
        self.endingShare = Double(lines.filter(\.endsWithCodePunctuation).count) / count
        self.indentShare = Double(lines.filter { $0.indent >= 2 }.count) / count
        let symbolSum = lines.reduce(0.0) { $0 + $1.symbolDensity }
        self.symbolDensity = symbolSum / count
        self.keywordShare = Double(lines.filter(\.isKeywordStart).count) / count
        self.sentenceShare = Double(lines.filter(\.isSentence).count) / count

        // Markers.
        let first = lines.first?.bytes ?? []
        if first.hasPrefix("#!") {
            self.shebang = String(decoding: first.dropFirst(2), as: UTF8.self)
        } else {
            self.shebang = nil
        }
        self.hasXMLDeclaration = first.hasPrefix("<?xml")
        self.hasPHPTag = first.hasPrefix("<?php") || first.hasPrefix("<?=")
        self.hasDoctype = lines.contains { $0.starts("<!DOCTYPE") || $0.starts("<!doctype") }
        self.hasHTMLRoot = lines.contains { $0.starts("<html") }

        // Shapes.
        self.isJSON = DetectionFeatures.isJSONDocument(text, lines: lines)
        self.isYAMLShaped = DetectionFeatures.isYAMLShape(lines)
        self.isSQLShaped = DetectionFeatures.isSQLShape(lines)

        // Evidence.
        let shaped = isJSON || isYAMLShaped || isSQLShaped || shebang != nil || hasDoctype || hasHTMLRoot
        self.isShaped = shaped
        let sqlShaped = isSQLShaped
        let yamlShaped = isYAMLShaped
        let jsonShaped = isJSON
        var values = lines.map {
            DetectionFeatures.evidence(of: $0, sqlShaped: sqlShaped, yamlShaped: yamlShaped, jsonShaped: jsonShaped)
        }
        // Structure: an indented line under a line of code is a little code itself (the body of a Python class).
        var open: [(indent: Int, isCode: Bool)] = []
        for index in lines.indices {
            let indent = lines[index].indent
            while let top = open.last, top.indent >= indent {
                open.removeLast()
            }
            if indent >= 2, let parent = open.last, parent.isCode, values[index] >= 0, values[index] < 0.5 {
                values[index] = 0.5
            }
            open.append((indent, values[index] >= 1))
        }
        // Lines of code, not counting comments: a text of comments only is not asked about its language.
        var hard = 0
        for (index, value) in values.enumerated() where value >= 1 && !lines[index].startsWithComment {
            hard += 1
        }
        let sum = values.reduce(0, +)
        var strong = 0
        for (index, value) in values.enumerated() where value >= 1 {
            if !lines[index].startsWithComment, DetectionFeatures.hasStrongMarker(lines[index]) { strong += 1 }
        }
        self.strongLineCount = strong
        self.hardLineCount = hard
        self.evidence = shaped ? max(sum / count, 0.95) : sum / count
    }

    // MARK: Evidence

    /// How much a line says "code" (1: a marker only code has, 0.5: a hint) or "prose" (-1: a sentence, -0.5: a line
    /// of a paragraph), 0 when it says nothing.
    static func evidence(of line: DetectionLine, sqlShaped: Bool, yamlShaped: Bool, jsonShaped: Bool) -> Double {
        if line.isSeparator { return 0 }
        if jsonShaped { return 1 }
        if sqlShaped && line.isSQLKeywordLine { return 1 }
        if yamlShaped && (line.yamlKey != nil || line.starts("- ") || line.starts("---")) { return 1 }
        // A whole sentence is prose, even with a `foo()` or a `;` in it.
        if line.isSentence { return -1 }
        if hasStrongMarker(line) || hasWeakMarker(line) { return 1 }
        if line.isSimpleAssignment {
            return DetectionFeatures.isPlainWordValue(line) ? 0.2 : 0.6
        }
        if line.hasArrow || line.isHashComment && Byte.isLower(line.bytes.count > 2 ? line.bytes[2] : 0x41) {
            return 0.5
        }
        if line.isKeywordStart && line.tokenCount <= 8 && !line.isWrappedProse { return 0.5 }
        if line.isWrappedProse { return -0.5 }
        return 0
    }

    /// A marker that is syntax: a call, an operator, a brace that opens a block, a tag, a comment, a shell command.
    static func hasStrongMarker(_ line: DetectionLine) -> Bool {
        // A call in a line of words (`check getUser() returns null`) is prose that mentions code.
        let mention = line.hasCall && line.isPureProse && line.tokenCount >= 4 && !line.startsWithCall
        let call = line.hasCall && !mention
        return call || line.startsWithComment || line.endsWithOpenBrace || line.hasTrailingComment
            || line.hasStrongOperator || line.isPreprocessor || line.hasHTMLTag || line.hasShellVariable
            || line.isDecorator || line.isPythonOpener || line.isJSONKeyLine || line.isCSSDeclaration
            || line.isShellCommand || line.hasCmdlet || line.isCSSSelector || line.isImport || line.isDeclaration
            || line.isFlagLine || line.endsWithContinuation || line.has("#{") || line.has("\\(")
            || hasSigilAssignment(line)
    }

    /// `@name = value`, `$name = value`: an instance variable or a variable with a sigil.
    private static func hasSigilAssignment(_ line: DetectionLine) -> Bool {
        (line.bytes[0] == 0x40 || line.bytes[0] == 0x24) && line.isSimpleAssignment
    }

    /// A marker that code has and prose may have as well: a `;` or a `}` at the end, a line of closing brackets, `end`.
    /// A line of nothing but words that ends in `;` is a clause of a contract, not a statement.
    static func hasWeakMarker(_ line: DetectionLine) -> Bool {
        let semicolon = line.endsWithSemicolon && !(line.isPureProse && line.tokenCount >= 4)
        return semicolon || line.endsWithCloseBrace || line.isCloser || line.isBlockEnd
    }

    /// `house = casa`: the value is one plain word, as in a list of translations.
    private static func isPlainWordValue(_ line: DetectionLine) -> Bool {
        guard let equals = line.bytes.firstIndex(of: 0x3D) else { return false }
        let value = line.bytes[(equals + 1)...].drop { Byte.isSpace($0) }
        return !value.isEmpty && value.allSatisfy { Byte.isLetter($0) }
    }

    // MARK: Shapes

    /// A JSON object or array, with `//` and `/* */` comments (as in settings files) allowed.
    private static func isJSONDocument(_ text: String, lines: [DetectionLine]) -> Bool {
        guard lines.count >= 2, let first = lines.first?.bytes.first else { return false }
        // The end of the text itself: only a prefix of the lines is read.
        guard let last = text.utf8.reversed().first(where: { !Byte.isSpace($0) && $0 != 0x0A && $0 != 0x0D }) else {
            return false
        }
        guard (first == 0x7B && last == 0x7D) || (first == 0x5B && last == 0x5D) else { return false }
        guard text.utf8.count <= 1_000_000 else { return false }
        if JSONShape.isDocument(stripComments(from: Array(text.utf8))) { return true }
        return isJSONLines(lines)
    }

    /// One JSON object or array on each line (JSON Lines), at least two.
    private static func isJSONLines(_ lines: [DetectionLine]) -> Bool {
        guard lines.count >= 2 else { return false }
        for line in lines {
            let first = line.bytes[0]
            let last = line.bytes[line.bytes.count - 1]
            guard (first == 0x7B && last == 0x7D) || (first == 0x5B && last == 0x5D) else { return false }
            guard JSONShape.isDocument(line.bytes) else { return false }
        }
        return true
    }

    /// `bytes` without the `//` and `/* */` comments that are outside strings.
    private static func stripComments(from bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        var inString = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                result.append(byte)
                if byte == 0x5C, index + 1 < bytes.count {
                    result.append(bytes[index + 1])
                    index += 1
                } else if byte == 0x22 {
                    inString = false
                }
            } else if byte == 0x22 {
                inString = true
                result.append(byte)
            } else if byte == 0x2F, index + 1 < bytes.count, bytes[index + 1] == 0x2F {
                while index < bytes.count, bytes[index] != 0x0A {
                    index += 1
                }
                continue
            } else if byte == 0x2F, index + 1 < bytes.count, bytes[index + 1] == 0x2A {
                index += 2
                while index + 1 < bytes.count, !(bytes[index] == 0x2A && bytes[index + 1] == 0x2F) {
                    index += 1
                }
                index += 2
                result.append(0x20)
                continue
            } else {
                result.append(byte)
            }
            index += 1
        }
        return result
    }

    /// Lines of `key: value` and `- item` with no braces or semicolons, and at least two keys: a YAML file. A key is
    /// an identifier that is not a capitalised word, so that the headers of an email and the labels of a note are not
    /// YAML. With three keys it is YAML; with two it takes a `---`, a list or an indented key to say so.
    private static func isYAMLShape(_ lines: [DetectionLine]) -> Bool {
        var keys = 0
        var items = 0
        var others = 0
        var configuration = 0
        var emptyKeys = 0
        var minimumIndent = Int.max
        var maximumIndent = 0
        var documentStart = false
        for line in lines {
            if line.bytes == [0x2D, 0x2D, 0x2D] {
                documentStart = true
            } else if line.isHashComment {
                continue
            } else if line.endsWithSemicolon || line.endsWithOpenBrace || line.isCloser {
                return false
            } else if let entry = line.yamlEntry {
                keys += 1
                if entry.isConfiguration { configuration += 1 }
                if line.bytes.last == 0x3A { emptyKeys += 1 }
                minimumIndent = min(minimumIndent, line.indent)
                maximumIndent = max(maximumIndent, line.indent)
            } else if line.starts("- ") {
                items += 1
                minimumIndent = min(minimumIndent, line.indent)
                maximumIndent = max(maximumIndent, line.indent)
            } else {
                others += 1
            }
        }
        guard keys >= 2, others * 5 <= keys + items + others else { return false }
        // A document start, keys inside keys, or a list under a key say YAML on their own.
        if documentStart || maximumIndent > minimumIndent || (items > 0 && emptyKeys > 0) { return true }
        // Flat `key: value` lines are YAML when one value is more than a word (`age: 30`): `monday: gym` is a note.
        return keys >= 3 && configuration >= 1
    }

    /// A line that starts a statement of SQL and another one that continues it, with something SQL-like on one of
    /// them (a comma, `*`, `=`, a bracket, a semicolon or capital keywords).
    private static func isSQLShape(_ lines: [DetectionLine]) -> Bool {
        var starters = 0
        var continuations = 0
        var symbols = false
        for line in lines where line.isSQLKeywordLine {
            if sqlStarters.contains(line.firstWord.lowercased()) {
                starters += 1
            } else {
                continuations += 1
            }
            if line.firstWord == line.firstWord.uppercased() || line.endsWithSemicolon || line.has(",")
                || line.has("*") || line.has("=") || line.has("(")
            {
                symbols = true
            }
        }
        if starters >= 1, continuations >= 1, symbols { return true }
        return starters >= 2 && symbols && lines.filter(\.endsWithSemicolon).count >= 2
    }
}
