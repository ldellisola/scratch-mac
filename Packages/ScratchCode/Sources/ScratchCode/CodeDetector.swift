import Foundation

/// What `CodeDetector` made of a text that is code.
public struct CodeDetection: Equatable, Sendable {
    /// The language, or nil for code of a language Scratch does not know (an unnamed fence).
    public let language: CodeLanguage?
    /// How sure the detector is that this is code, 0 to 1. It is the mean evidence of the lines, less the share of the
    /// text the winning grammar could not parse.
    public let confidence: Double

    public init(language: CodeLanguage?, confidence: Double) {
        self.language = language
        self.confidence = confidence
    }
}

/// Is this paste code, and in which language? (Plan 4 Task 4, spec §6.4 and §8.1.)
///
/// It is offline and deterministic: the same text always gives the same answer. It never changes the text. The rule is
/// the spec's: when unsure, it is prose.
///
/// 1. `DetectionFeatures` reads the lines. Their evidence (a `;` or `{` at the end, a call, an operator, a comment
///    marker, a tag, a shell command, a keyword) gives a code score. A text of sentences, lists, labels and logs scores
///    below the threshold and stays prose.
/// 2. `LanguageSignals` counts the idioms of each language (a shebang, `func`, `def ...:`, `package main`, `SELECT ...
///    FROM`, a JSON document).
/// 3. A language that is far ahead is the answer. Otherwise the candidates (at most four) are parsed, and the one with
///    the lowest `Highlighter.errorRate` is. When even that one does not parse, the code is of an unknown language.
public enum CodeDetector {
    /// nil is prose (it stays plain text). Only call it for text of two or more lines: one line, and a text whose
    /// lines but one are blank, give nil.
    public static func detect(_ text: String) -> CodeDetection? {
        analyze(text).detection
    }

    // MARK: Thresholds

    /// The mean evidence of the lines from which a text is code.
    static let codeThreshold = 0.5
    /// ... and from which code of a language that does not parse is still code of an unknown language.
    static let unknownLanguageThreshold = 0.7
    /// The share of a sample that may fail to parse in the winning grammar: more when the language had signals of its
    /// own, almost nothing when it was picked by the parse alone.
    static let maximumErrorRate = 0.15
    static let maximumErrorRateWithoutSignal = 0.03
    static let signalPoints = 3.0
    /// A language is the answer without a parse when it has this many points and leads by `decisiveLead`.
    static let decisivePoints = 6.0
    static let decisiveLead = 3.0
    /// ... and the second language has less than this share of the points of the first.
    static let decisiveShare = 0.4
    /// Candidates are the languages within this many points of the best one.
    static let candidateWindow = 4.0
    static let maximumCandidates = 4
    /// Tried when the text has no signal of any language.
    static let defaultCandidates: [CodeLanguage] = [.swift, .python, .javascript, .java]

    // MARK: Analysis

    /// TypeScript has every idiom of JavaScript and some of its own, so their points are close, and a parse cannot tell
    /// them apart (a TSX file does not parse as TypeScript, and JavaScript parses a little of anything). The idioms
    /// that only TypeScript has decide: with three points of them it is TypeScript, otherwise JavaScript.
    private static func settleScriptFamily(_ points: inout [Double]) {
        let javascript = LanguageSignals.index(of: .javascript)
        let typescript = LanguageSignals.index(of: .typescript)
        if points[typescript] - points[javascript] >= 3 {
            points[javascript] = 0
        } else {
            points[typescript] = 0
        }
    }

    /// What the detector found out, step by step (the tests read it to explain a miss).
    struct Analysis {
        let features: DetectionFeatures
        /// Points of each language, in the order of `CodeLanguage.allCases`.
        let points: [Double]
        /// The candidates that were parsed, with their error rates (empty when a language was decisive).
        let parsed: [(language: CodeLanguage, errorRate: Double)]
        let detection: CodeDetection?
    }

    static func analyze(_ text: String) -> Analysis {
        let features = DetectionFeatures(text: text)
        let none = Analysis(features: features, points: [], parsed: [], detection: nil)
        guard features.nonBlankLineCount >= 2 else { return none }

        // Markers that say "code" and name a language, or say it is one Scratch does not know.
        if features.hasXMLDeclaration || features.hasPHPTag {
            return Analysis(
                features: features, points: [], parsed: [],
                detection: CodeDetection(language: nil, confidence: 0.9))
        }
        if features.shebang != nil, LanguageSignals.shebangLanguage(features.shebang) == nil {
            return Analysis(
                features: features, points: [], parsed: [],
                detection: CodeDetection(language: nil, confidence: 0.9))
        }

        // Code or prose.
        let confidence = min(1, max(0, features.evidence))
        guard features.evidence >= codeThreshold, features.hardLineCount >= 2 || features.isShaped else { return none }

        // Which language.
        var points = LanguageSignals.points(for: features)
        Self.settleScriptFamily(&points)
        let ranked = Array(points.indices).sorted { lhs, rhs in
            points[lhs] != points[rhs] ? points[lhs] > points[rhs] : lhs < rhs
        }
        let best = points[ranked[0]]
        let second = points[ranked[1]]
        let lead = best - second
        if best >= decisivePoints, lead >= decisiveLead, second <= best * decisiveShare {
            let language = LanguageSignals.language(at: ranked[0])
            return Analysis(
                features: features, points: points, parsed: [],
                detection: CodeDetection(language: language, confidence: confidence))
        }

        var candidates: [Int] = []
        if best >= 1 {
            for index in ranked where points[index] >= 1 && points[index] >= best - candidateWindow {
                if candidates.count < maximumCandidates { candidates.append(index) }
            }
        }
        // Few signals: the common languages are tried as well, so that a weak hint is not the only choice.
        if candidates.count < 3 {
            for language in defaultCandidates {
                let index = LanguageSignals.index(of: language)
                if candidates.count < maximumCandidates, !candidates.contains(index) { candidates.append(index) }
            }
        }
        var parsed: [(language: CodeLanguage, errorRate: Double)] = []
        for index in candidates {
            let language = LanguageSignals.language(at: index)
            parsed.append((language, Highlighter.shared.errorRate(of: features.sample, language: language)))
        }
        // The lowest error rate wins; rates within a hundredth of each other are a tie that the points settle.
        var winner = 0
        for index in parsed.indices.dropFirst() {
            let rate = parsed[index].errorRate
            let current = parsed[winner].errorRate
            if rate < current - 0.01 {
                winner = index
            } else if rate <= current + 0.01 {
                let better = points[candidates[index]] > points[candidates[winner]]
                let sameButEarlier =
                    points[candidates[index]] == points[candidates[winner]] && candidates[index] < candidates[winner]
                if better || sameButEarlier { winner = index }
            }
        }
        let rate = parsed[winner].errorRate
        let hasSignal = points[candidates[winner]] >= signalPoints
        // With no idiom of the language, a parse is all there is, and a list of words with `;` after them parses.
        let enoughSyntax =
            features.strongLineCount >= 2 || (features.strongLineCount >= 1 && features.hardLineCount >= 3)
        if !hasSignal, !enoughSyntax, !features.isShaped {
            return Analysis(features: features, points: points, parsed: parsed, detection: nil)
        }
        let limit = hasSignal ? maximumErrorRate : maximumErrorRateWithoutSignal
        if rate > limit {
            guard features.evidence >= unknownLanguageThreshold, features.strongLineCount >= 3 else {
                return Analysis(features: features, points: points, parsed: parsed, detection: nil)
            }
            return Analysis(
                features: features, points: points, parsed: parsed,
                detection: CodeDetection(language: nil, confidence: confidence * (1 - min(rate, 1))))
        }
        // No idiom of any language, and more than one grammar reads it with no more errors: C-like code that is as much
        // Swift as Java as JavaScript. It is code, and no one can say whose.
        let tied = parsed.indices.contains { $0 != winner && parsed[$0].errorRate <= rate + 0.01 }
        if !hasSignal, tied {
            return Analysis(
                features: features, points: points, parsed: parsed,
                detection: CodeDetection(language: nil, confidence: confidence * (1 - rate)))
        }
        return Analysis(
            features: features, points: points, parsed: parsed,
            detection: CodeDetection(language: parsed[winner].language, confidence: confidence * (1 - rate)))
    }
}
