# 0006: Bold needs word boundaries

Status: accepted, 2026-10-21 (the owner's decision while planning Plan 4). Narrows the Bold row of spec §6.4's marker
table and the rule Plan 3 built (`**text**`, no white space at the content's edges). The second rule under "The rule"
is a [call] of the builder, made while implementing the first: it is the smallest addition that makes the owner's own
examples plain.

## Decision

`MarkupParser` makes a bold run of `**`, content, `**` only when both ends are at a word boundary:

1. An opening `**` counts only when the character before it is the start of the line, or is not a letter or a digit
   (`Character.isLetter || isNumber`, so every script counts, and `e` with a combining accent is a letter).
2. A closing `**` counts only when the character after it is the end of the line, or is not a letter or a digit.
3. **[call]** A `**` that has a punctuation mark on both sides, counting the first character of the content for an
   opening pair and the last one for a closing pair, is neither: it is a glob or an operator. Punctuation here is
   anything that is not white space, a letter or a digit.

Plan 3's rules are unchanged: the content is at least one character, contains no `**` outside inline code, and neither
starts nor ends with white space. Inline code still wins over bold, and nothing inside it is a marker. A run that fails
a rule stays text, and the scan goes on after it, so a later run on the line is still found.

| Text | Bold? |
|---|---|
| `x**2 + y**2`, `2**10 and 3**4`, `a**b**c`, `**a**b` | no |
| `src/**/*.ts and lib/**/*.js`, `"**/*.ts","**/*.js"`, `(a+b)**(n)` | no (rule 3) |
| `(**a**)`, `"**a**"`, `**a**, x`, `**Note:** x`, `😀**a**😀` | yes |
| `(**Note:**)`, `(**"q"**)` | no (rule 3: the trade-off below) |

## Why

The owner's notes hold code that was never fenced: `x**2 + y**2`, `src/**/*.ts`, a Python `**kwargs`. Plan 3 rendered
them as bold and hid the stars, which is the "Mangled code" anti-goal of spec §4 (the characters stay, but what the
owner reads is no longer what they typed). The stars of a real bold run are nearly always next to white space, the line
edge or punctuation, so asking for a word boundary costs little.

The first two rules alone leave one of the owner's two examples bold: in `src/**/*.ts and lib/**/*.js` the opening `**`
follows a `/` and the closing one is followed by a `/`, so the run `/*.ts and lib/` is bold. Rule 3 is the smallest
rule that catches it (`/**/`, `)**(` and `"**/` are all punctuation on both sides), and it is checked at both ends so
that `a **/*.ts,**/*.js` is plain too. It is stricter than CommonMark's flanking rules, which would make `src/**/*.ts`
bold and leave the glob's author to escape it, and a scratchpad has no escape character to offer: every character
of a note is literal.

## Consequences

- **`word**bold**word` is no longer bold.** The stars stay visible. Plan 3 rendered it as bold, and so does Markdown.
- **`(**Note:**)` and `"**stop!**"` are plain**: the content ends with punctuation right inside punctuation. A space
  or a different quote fixes it, and the stars are never hidden by mistake, which is the side to err on.
- **⌘B inside a word wraps the selection and the stars are not a run.** `InlineEditing.toggleBold` is unchanged: it
  finds a run to unwrap through `MarkupParser`, so ⌘B on the `c` of `ab**c**d` wraps again (`ab****c****d`) where it
  used to take the stars off. `docs/features/formatting.md` says so, and ⌘Z is the way back.
- The styler needs no change: it restyles from the parser's spans, and `MarkupParser.mayHaveSpans` still lets every
  line with a `**` through, since the rule can only remove spans.
- The `formatting` and `typical` fixtures have no bold next to a letter or between punctuation, so their screenshots do
  not change.
- Tests: `MarkupParserTests` (`intrawordStarsAreNotBold`, `globsAreNotBold`, `boldAfterPunctuationStillWorks`,
  `boldAtLineEdgesStillWorks`, `wordGluedBoldIsPlain` and the rest of the group "Bold needs word boundaries") and
  `InlineEditingTests.wrapInsideAWordStillInsertsStarsButTheyAreNotBold`.
