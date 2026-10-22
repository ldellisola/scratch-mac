import Foundation
import Testing

@testable import ScratchCode

// Plan 4 Task 4, "Code detection" (spec §6.4, §8.1): is a paste code, and which language? The corpus under
// `Tests/ScratchCodeTests/Corpus/` is what the detector is tuned against: a folder of samples for each language,
// `unknown/` (code of languages Scratch does not know), and `prose/`, whose samples must stay prose. Every sample was
// written for this corpus. docs/features/code.md.

// MARK: The corpus

private struct Sample {
    let folder: String
    let name: String
    let text: String

    var path: String { "\(folder)/\(name).txt" }
    var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: true).count }
}

private let corpusURL: URL = Bundle.module.resourceURL!.appendingPathComponent("Corpus", isDirectory: true)

private func folders() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: corpusURL.path)) ?? []).sorted()
}

/// The samples of a folder of the corpus, in the order of their names.
private func samples(in folder: String) -> [Sample] {
    let directory = corpusURL.appendingPathComponent(folder, isDirectory: true)
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    return files.filter { $0.hasSuffix(".txt") }.compactMap { file in
        guard let text = try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8) else {
            return nil
        }
        return Sample(folder: folder, name: String(file.dropLast(4)), text: text)
    }
}

/// What the detector made of a sample, for the message of a failure.
private func describe(_ sample: Sample) -> String {
    let analysis = CodeDetector.analyze(sample.text)
    let best = analysis.points.enumerated()
        .sorted { $0.element != $1.element ? $0.element > $1.element : $0.offset < $1.offset }.prefix(3)
        .map { "\(CodeLanguage.allCases[$0.offset].fenceName)=\($0.element)" }
    let parsed = analysis.parsed.map { "\($0.language.fenceName)=\(String(format: "%.2f", $0.errorRate))" }
    let evidence = String(format: "%.2f", analysis.features.evidence)
    return "\(sample.path): evidence \(evidence), code lines \(analysis.features.hardLineCount), points \(best), "
        + "parsed \(parsed), result \(String(describing: analysis.detection))"
}

private func answer(_ text: String) -> String {
    guard let detection = CodeDetector.detect(text) else { return "prose" }
    return detection.language?.fenceName ?? "unknown"
}

// MARK: The corpus is what the plan says it is

@Test func theCorpusHasEnoughSamples() {
    for language in CodeLanguage.allCases {
        let found = samples(in: language.fenceName)
        #expect(found.count >= 4, "\(language.fenceName) has \(found.count) samples")
        #expect(
            found.allSatisfy { (3...60).contains($0.lineCount) },
            "\(language.fenceName) has a sample that is not 3 to 60 lines")
        #expect(found.contains { (3...5).contains($0.lineCount) }, "\(language.fenceName) has no short sample")
        let markers = ["//", "#", "--", "/*", "<!--"]
        #expect(
            found.contains { sample in markers.contains { sample.text.contains($0) } },
            "\(language.fenceName) has no sample with a comment")
    }
    #expect(samples(in: "prose").count >= 30)
    #expect(samples(in: "unknown").count >= 4)
    #expect(samples(in: "ambiguous").count <= 3)
}

@Test func theCorpusHasNoFolderThatIsNotALanguage() {
    let known = Set(CodeLanguage.allCases.map(\.fenceName) + ["prose", "unknown", "ambiguous"])
    #expect(Set(folders()).isSubset(of: known), "\(Set(folders()).subtracting(known))")
}

// MARK: Code

@Test func everyCodeSampleIsCodeWithItsLanguage() {
    for language in CodeLanguage.allCases {
        for sample in samples(in: language.fenceName) {
            #expect(CodeDetector.detect(sample.text)?.language == language, "\(describe(sample))")
        }
    }
}

@Test func everyProseSampleStaysProse() {
    for sample in samples(in: "prose") {
        #expect(CodeDetector.detect(sample.text) == nil, "\(describe(sample))")
    }
}

@Test func codeOfAnUnknownLanguageIsCodeWithNoLanguage() {
    for sample in samples(in: "unknown") {
        let detection = CodeDetector.detect(sample.text)
        #expect(detection != nil && detection?.language == nil, "\(describe(sample))")
    }
}

// MARK: Single lines, determinism, speed

@Test func singleLineIsNeverCode() {
    #expect(CodeDetector.detect("let x = 1;") == nil)
    #expect(CodeDetector.detect("let x = 1;\n") == nil)
    #expect(CodeDetector.detect("\n\nSELECT * FROM notes;\n\n") == nil)
    #expect(CodeDetector.detect("") == nil)
    #expect(CodeDetector.detect("   \n  \n") == nil)
    // The first line of every sample alone.
    for folder in folders() {
        for sample in samples(in: folder) {
            let first = sample.text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
            #expect(CodeDetector.detect(first ?? "") == nil, "\(sample.path): \(first ?? "")")
        }
    }
}

@Test func detectionIsDeterministic() {
    var texts: [String] = []
    for folder in folders() {
        texts.append(contentsOf: samples(in: folder).map(\.text))
    }
    let first = texts.map { CodeDetector.detect($0) }
    for _ in 0..<20 {
        #expect(texts.map { CodeDetector.detect($0) } == first)
    }
}

/// `unit` repeated until the text has `lines` lines.
private func repeated(_ unit: String, lines: Int) -> String {
    var text = ""
    var count = 0
    let perUnit = unit.split(separator: "\n", omittingEmptySubsequences: false).count
    while count < lines {
        text += unit + "\n"
        count += perUnit
    }
    return text
}

/// The bound of a timing test. The figure a test names is its Release budget, and a test run is a Debug build: on
/// macOS the CI runner took 107 ms for the 100 of `fiveHundredLinesIsFast` and 498 ms for the 400 of the test of every
/// language, so there the bound is 4 times that figure. Linux keeps the figure itself. What is held to the budget is
/// the Release build, by `paste_code_ms` (AGENTS.md section 4).
private func bound(_ releaseBudget: Duration) -> Duration {
    #if os(macOS)
        return releaseBudget * 4
    #else
        return releaseBudget
    #endif
}

/// The shortest of a few runs, so that a busy runner does not fail a test of speed.
private func fastest(of runs: Int = 3, _ work: () -> Void) -> Duration {
    var best = Duration.seconds(1000)
    for _ in 0..<runs {
        let clock = ContinuousClock()
        let start = clock.now
        work()
        best = min(best, clock.now - start)
    }
    return best
}

@Test func fiveHundredLinesIsFast() {
    let unit = samples(in: "swift").first { $0.name == "model" }?.text ?? ""
    let text = repeated(unit, lines: 500)
    #expect(text.split(separator: "\n", omittingEmptySubsequences: false).count >= 500)
    #expect(CodeDetector.detect(text)?.language == .swift)
    let elapsed = fastest { _ = CodeDetector.detect(text) }
    #expect(elapsed < bound(.milliseconds(100)), "took \(elapsed)")
}

@Test func fiveHundredLinesOfEveryLanguageIsFast() {
    // The ones that need a parse (a tie between languages) cost the most.
    for language in CodeLanguage.allCases {
        for sample in samples(in: language.fenceName) {
            let text = repeated(sample.text, lines: 500)
            let elapsed = fastest(of: 2) { _ = CodeDetector.detect(text) }
            #expect(elapsed < bound(.milliseconds(400)), "\(sample.path) took \(elapsed)")
        }
    }
}

@Test func aHugePasteIsLookedAtInPart() {
    let log = (0..<50_000).map { "2026-03-02 08:14:\($0 % 60) INFO worker \($0) finished job \($0 * 7) ok" }
    let text = log.joined(separator: "\n")
    let elapsed = fastest(of: 1) { #expect(CodeDetector.detect(text) == nil) }
    #expect(elapsed < bound(.milliseconds(500)), "took \(elapsed)")

    // One enormous line, and a minified file of a few lines.
    let long = String(repeating: "let value = compute(a, b);", count: 20_000)
    let minified = long + "\n" + long
    let longElapsed = fastest(of: 1) { _ = CodeDetector.detect(minified) }
    #expect(longElapsed < bound(.milliseconds(1_000)), "took \(longElapsed)")
}

@Test func aFiftyThousandLineJSONDocumentIsFoundQuickly() {
    // Plan 5 task 7, the "large code paste" follow-up: 50,000 lines of pretty-printed JSON, 760 KB, which is under the size
    // up to which a JSON document is validated whole, so every byte goes through `JSONShape`. The app's paste test
    // (`LargeInsertTests`) holds the detection and the wrap that follows it to 500 ms together, in a debug build.
    let objects = 16_666
    var lines = ["["]
    for index in 1...objects {
        lines.append("  {")
        lines.append("    \"id\": \(index), \"name\": \"item \(index)\"")
        lines.append(index == objects ? "  }" : "  },")
    }
    lines.append("]")
    let text = lines.joined(separator: "\n")
    #expect(lines.count == 50_000)
    #expect(text.utf8.count < 1_000_000)
    #expect(answer(text) == "json")
    let elapsed = fastest(of: 2) { _ = CodeDetector.detect(text) }
    #expect(elapsed < bound(.milliseconds(250)), "took \(elapsed)")
}

// MARK: The strong signals

@Test func aShebangNamesTheLanguage() {
    #expect(answer("#!/bin/bash\necho hi\n") == "bash")
    #expect(answer("#!/usr/bin/env zsh\nprint hello\n") == "bash")
    #expect(answer("#!/bin/sh\nexit 0\n") == "bash")
    #expect(answer("#!/usr/bin/env python3\nprint('hi')\n") == "python")
    #expect(answer("#!/usr/bin/env node\nconsole.log(1)\n") == "javascript")
    #expect(answer("#!/usr/bin/env pwsh\nWrite-Host hi\n") == "powershell")
    // A language that Scratch does not know is code without a language.
    #expect(answer("#!/usr/bin/env ruby\nputs 1\n") == "unknown")
}

@Test func phpAndXMLAreCodeOfAnUnknownLanguage() {
    #expect(answer("<?php\necho 1;\n") == "unknown")
    #expect(answer("<?xml version=\"1.0\"?>\n<a/>\n") == "unknown")
}

@Test func jsonShapeDecides() {
    #expect(answer("{\n  \"a\": 1,\n  \"b\": [1, 2, 3]\n}") == "json")
    #expect(answer("[\n  1,\n  2\n]") == "json")
    // Comments, as in settings files.
    #expect(answer("{\n  // note\n  \"a\": 1, /* two */\n  \"b\": \"x // not a comment\"\n}") == "json")
    // One object on each line.
    #expect(answer("{\"a\": 1}\n{\"a\": 2}\n") == "json")
    // Not JSON: an object literal of JavaScript.
    #expect(answer("const o = {\n  a: 1,\n  b: 2,\n};\n") == "javascript")
}

@Test func sqlNeedsAStatementAndAClause() {
    #expect(answer("SELECT id, name\nFROM users\nWHERE active = 1;") == "sql")
    #expect(answer("select id, name\nfrom users\nwhere active = 1") == "sql")
    #expect(answer("INSERT INTO t (a) VALUES (1);\nDELETE FROM t WHERE a = 1;") == "sql")
    // A sentence that happens to start with the words is not.
    #expect(answer("select the best option from the list below\nand then confirm it") == "prose")
}

@Test func typeAnnotationsTellTypeScriptFromJavaScript() {
    #expect(answer("const n: number = 5;\nlet s: string = \"a\";") == "typescript")
    #expect(answer("const n = 5;\nlet s = \"a\";") == "javascript")
    #expect(answer("interface A {\n  x: number;\n}\n") == "typescript")
}

@Test func cppFeaturesTellCPlusPlusFromC() {
    #expect(answer("#include <stdio.h>\nint main(void) {\n    printf(\"a\");\n    return 0;\n}") == "c")
    #expect(answer("#include <iostream>\nint main() {\n    std::cout << \"a\";\n    return 0;\n}") == "cpp")
}

@Test func swiftAndRustBothHaveLet() {
    #expect(answer("let x: Int = 5\nprint(x)\n") == "swift")
    #expect(answer("let mut x: i32 = 5;\nprintln!(\"{}\", x);\n") == "rust")
}

// MARK: Code with no semicolons or braces

@Test func codeWithoutPunctuationIsStillCode() {
    #expect(answer("def add(a, b):\n    return a + b\n\nprint(add(1, 2))\n") == "python")
    #expect(answer("const x = 1\nlet y = 2\nvar z = x + y\n") == "javascript")
    #expect(
        answer("curl -X POST https://api.example.com/items \\\n  -H \"Accept: text/html\" \\\n  -d 'a=1'\n") == "bash")
    #expect(answer("# update\nsudo apt update\nsudo apt install -y git\n") == "bash")
    #expect(answer("x := 5\nfmt.Println(x)\n") == "go")
}

// MARK: Prose that must stay prose, beyond the corpus

@Test func moreProseStaysProse() {
    let texts = [
        "On Mon, 12 Oct, Dana wrote:\n> Are we still on for Thursday?\n> I can do 3 pm.\n\nYes, 3 pm works.\n",
        "[10:42] dana: did the build pass?\n[10:43] joel: yes, green now\n[10:45] dana: great, merging\n",
        "-rw-r--r--  1 lucas  staff  1024 Oct 21 10:42 notes.txt\ndrwxr-xr-x  5 lucas  staff   160 Oct 20 09:12 src\n",
        "commit 3f2a9c1\nAuthor: Dana Okafor <dana@example.com>\nDate:   Tue Oct 20 10:42:07 2026\n\n    Fix it\n",
        "@@ -1,3 +1,4 @@\n-old line\n+new line\n unchanged\n",
        "\"Smith, John\",42,London\n\"Doe, Jane\",37,Paris\n",
        "今日は会議があります。\n午後三時から始まります。\n資料を準備してください。\n",
        "Guten Morgen zusammen,\n\nanbei die Unterlagen für heute. Bitte schaut sie euch vor dem Treffen an.\n",
        "f(x) = 2x + 3\nf(2) = 7\nf(0) = 3\n",
        "12:30\n13:45\n15:10\n",
        "- [ ] buy milk\n- [x] call mum\n- [ ] book flights\n",
        "- [Docs](https://example.com/docs)\n- [Blog](https://example.com/blog)\n",
        "Run `npm install` first.\nThen start the server with `npm start`.\n",
        "1) update the changelog\n2) bump the version\n3) tag the release\n",
        "tea = 2.50\ncoffee = 3.00\ncake = 4.25\n",
        "Flat 3, 14 Orchard Lane\nBrightwell OX7 4QA\nTel: (01865) 555 0142\n",
        "// TODO: refactor the loader\n// FIXME: remove the old path\n",
        "x = 5\nprint(x)\n",
        "Remember to call init() before run(). The loader reads settings.json first.\nThen restart the app.\n",
        "Dear <name>,\n\nYour order <number> ships on <date>.\n",
        "== Background ==\nThe club was started by neighbours.\n\n== Meetings ==\nSecond Saturday of the month.\n",
        "the tenant shall pay the rent on the first day of each month;\nthe landlord shall keep the hallway clean;\n",
        "-- \nIna Varga\nStudio manager\n",
        "check getUser() returns null\nthen call render() with the result\n",
        "milk;\neggs;\nbread;\n",
        "green apples;\nred pears;\nyellow plums;\n",
        "- fix login bug (issue #123)\n- update README\n- deploy to staging\n- ask Anna about API keys\n",
        "Plan A -> Plan B\nPlan B -> ask finance\n",
        "Hello {{name}},\nYour code is {{code}}\n",
        "#!important remember this\nbuy milk tomorrow\n",
        "#!\nhello\n",
    ]
    for text in texts {
        #expect(answer(text) == "prose", "\(text)")
    }
}

@Test func labelsOfAPlainNoteAreNotYAML() {
    #expect(answer("monday: gym\ntuesday: dentist\nwednesday: call mum\n") == "prose")
    #expect(answer("Subject: Lunch\nFrom: Dana\nTo: Joel\nDate: Friday\n") == "prose")
    // Not YAML either: short lowercase keys with words, numbers, phone numbers, emails or a comma list (Plan 5, task 3).
    #expect(answer("name: John\nage: 30\ncity: Paris\n") == "prose")
}

// MARK: `key: value` notes and the cues of YAML (Plan 5, task 3; docs/features/code.md, "Detection")

@Test func flatKeyValueNotesAreProse() {
    #expect(answer("rooms: 2\nrent: 950\ndeposit: 1900\n") == "prose")
    #expect(answer("phone: 07700 900 123\nemail: jo@example.com\nowner: jo\n") == "prose")
    #expect(answer("buy: eggs, flour, butter\ntodo: call the vet\nidea: a lamp\n") == "prose")
    #expect(answer("draft: false\nreviewed: true\nowner: jo\n") == "prose")
    #expect(answer("version: 2\nbuild: 14\nowner: jo\n") == "prose")
    // The lines are only "indented", under a key that has a value: that is not nesting.
    #expect(answer("name: John\n  age: 30\n  city: Paris\n") == "prose")
    // A list that is not under a key.
    #expect(answer("name: John\n- age: 30\n- city: Paris\n") == "prose")
}

@Test func yamlNeedsAStructuralCue() {
    // Nesting under a key that has no value.
    #expect(answer("server:\n  host: localhost\n  port: 8080\n") == "yaml")
    // A list under a key, indented or not.
    #expect(answer("tags:\n  - work\n  - plan\nowner: jo\n") == "yaml")
    #expect(answer("tags:\n- work\n- plan\nowner: jo\n") == "yaml")
    // A document start.
    #expect(answer("---\nname: build\non: push\n") == "yaml")
    // A value that is YAML syntax: a block scalar, an anchor, a quoted string with a colon in it.
    #expect(answer("name: build\nrun: |\n  make test\n  make lint\n") == "yaml")
    #expect(answer("description: >\n  runs the checks\nowner: jo\n") == "yaml")
    #expect(answer("base: &base debug\nname: web\nenv: staging\n") == "yaml")
    #expect(answer("name: db\nports: \"5432:5432\"\nimage: postgres\n") == "yaml")
}

@Test func inlineCodeIsAWordOfTheSentence() {
    #expect(answer("Call `init()` first, then `run()` as usual\nand `stop()` when you are done\n") == "prose")
    #expect(answer("- Write `release-notes.sh`.\n- Set `CURRENT_PROJECT_VERSION: ${SCRATCH_VERSION}`.\n") == "prose")
    // The same lines without the backticks are code.
    #expect(answer("init()\nrun()\nstop()\n") != "prose")
}

@Test func yamlNeedsStructureNotJustIndentation() {
    #expect(answer("  monday: gym\n  tuesday: dentist\n  wednesday: call mum\n") == "prose")
    #expect(answer("shopping:\n  milk: 2\n  eggs: 6\n") == "yaml")
    #expect(answer("tags:\n  - work\n  - plan\ndraft: false\n") == "yaml")
}

@Test func anUnsignalledTieNamesNoLanguage() {
    // Valid C, C++, C# and Java, and nothing in it that only one of them has.
    #expect(answer("for (int i = 0; i < 3; i++) {\n    total += i;\n}\n") == "unknown")
    // Words with a `;` after them parse, and are still not code.
    #expect(answer("milk;\neggs;\nbread;\n") == "prose")
}

// MARK: Line endings and white space

@Test func lineEndingsAndBlankLinesDoNotMatter() {
    for folder in folders() {
        for sample in samples(in: folder) {
            // The language, not the confidence: the share of a sample that fails to parse counts its line breaks.
            let expected = answer(sample.text)
            let crlf = sample.text.replacingOccurrences(of: "\n", with: "\r\n")
            #expect(answer(crlf) == expected, "\(sample.path) with CR LF")
            let cr = sample.text.replacingOccurrences(of: "\n", with: "\r")
            #expect(answer(cr) == expected, "\(sample.path) with CR")
            #expect(answer("\n\n" + sample.text + "\n\n\n") == expected, "\(sample.path) with blank lines")
        }
    }
}

@Test func confidenceIsBetweenZeroAndOne() {
    for folder in folders() {
        for sample in samples(in: folder) {
            if let detection = CodeDetector.detect(sample.text) {
                #expect((0.0...1.0).contains(detection.confidence), "\(sample.path): \(detection.confidence)")
            }
        }
    }
}

// MARK: Odd input

private struct SeededGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}

@Test func oddInputNeverCrashesAndStaysDeterministic() {
    let alphabet = Array("abcXYZ019 \t\n\r{}[]()<>=;:,.'\"`$#@*&|/\\-+!?_é日😀")
    var generator = SeededGenerator(state: 42)
    for _ in 0..<300 {
        let length = Int(generator.next() % 200)
        var text = ""
        for _ in 0..<length {
            text.append(alphabet[Int(generator.next() % UInt64(alphabet.count))])
        }
        let first = CodeDetector.detect(text)
        #expect(CodeDetector.detect(text) == first)
    }
    // Lines of one symbol, a NUL and other control characters.
    for text in [
        "{\n}\n", "}\n}\n", ";\n;\n", "(\n)\n", "\u{0}\n\u{0}\n", "\u{1}\u{2}\n\u{3}\n", "<\n>\n", "$\n$\n", "@\n@\n",
    ] {
        _ = CodeDetector.detect(text)
    }
}

// MARK: Features

@Test func featuresReadTheLines() {
    let features = DetectionFeatures(text: "int a;\n  if (a) {\n    a++;\n  }\n\nThe end of this text.\n")
    #expect(features.nonBlankLineCount == 5)
    #expect(features.lines.count == 5)
    #expect(features.endingShare == 4.0 / 5.0)
    #expect(features.indentShare == 3.0 / 5.0)
    #expect(features.sentenceShare == 1.0 / 5.0)
    #expect(features.symbolDensity > 0)
    #expect(features.keywordShare > 0)
    #expect(features.shebang == nil)
}

@Test func featuresSeeShebangsAndDeclarations() {
    #expect(DetectionFeatures(text: "#!/usr/bin/env python3\nprint(1)\n").shebang == "/usr/bin/env python3")
    #expect(DetectionFeatures(text: "#! /bin/sh\necho 1\n").shebang == " /bin/sh")
    #expect(DetectionFeatures(text: "#!todo\nbuy milk\n").shebang == nil)
    #expect(DetectionFeatures(text: "#!\nhello\n").shebang == nil)
    #expect(DetectionFeatures(text: "<?xml version=\"1.0\"?>\n<a/>\n").hasXMLDeclaration)
    #expect(DetectionFeatures(text: "<?php\necho 1;\n").hasPHPTag)
    #expect(DetectionFeatures(text: "<!DOCTYPE html>\n<html>\n</html>\n").hasDoctype)
    #expect(DetectionFeatures(text: "<html lang=\"en\">\n</html>\n").hasHTMLRoot)
    #expect(DetectionFeatures(text: "{\n\"a\": 1\n}\n").isJSON)
    #expect(!DetectionFeatures(text: "{\n\"a\": 1,\n}\n").isJSON)
}

@Test func onlyAPrefixOfALongTextIsRead() {
    let text = (0..<5_000).map { "line \($0);" }.joined(separator: "\n")
    let features = DetectionFeatures(text: text)
    #expect(features.lines.count == DetectionFeatures.maximumLines)
    #expect(features.sample.split(separator: "\n").count <= DetectionFeatures.parseLines)
}
