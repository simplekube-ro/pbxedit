# Tasks

## 1. Package scaffold

- [ ] 1.1 Create `Package.swift` (Swift 6 language mode, macOS 13+, library target `PBXSyntax`, test target `PBXSyntaxTests`, no dependencies); verify `swift build` and `swift test` succeed with one placeholder test
- [ ] 1.2 Add `.gitignore` for `.build/` and `.swiftpm/`, and `.github/workflows/ci.yml` running `swift test` on `macos-latest`; verify the workflow is green on the pushed branch

## 2. Lexer

- [ ] 2.1 Write failing lexer tests: structural tokens, bare strings over the CoreFoundation character set, quoted strings with `\"`, `\\`, `\n`, `\U` escapes, data literals, block and line comments, CRLF, leading trivia ownership per design D1–D2
- [ ] 2.2 Implement the byte-level lexer until 2.1 passes; verify concatenating all token trivia and text reproduces each test input

## 3. Parser and tree

- [ ] 3.1 Write failing parser tests for the three Grammar coverage scenarios in the spec, asserting key order, decoded values and preserved raw text
- [ ] 3.2 Implement the tree types and recursive-descent parser with a nesting limit of 64; verify 3.1 passes

## 4. Serializer and round trip

- [ ] 4.1 Write failing round-trip tests for the two Byte-exact round trip scenarios, using a hand-written fixture with mixed indentation, CRLF lines and no trailing newline
- [ ] 4.2 Implement serialization; verify 4.1 passes and `serialize(parse(x)) == x` holds for every fixture in `Tests/Fixtures/`

## 5. Errors

- [ ] 5.1 Write failing tests for the Located errors scenarios: bare `+` at a known line and column, unterminated comment, XML and binary prefixes, invalid UTF-8 byte offset, nesting past the limit
- [ ] 5.2 Implement `ParseError` and the up-front UTF-8 and format checks; verify 5.1 passes and a grep of `Sources/PBXSyntax` finds no `fatalError`, `try!` or force unwrap

## 6. Edits

- [ ] 6.1 Write failing tests for insert, remove and replace that assert on the **diff** against the input: one added line, one removed line including its comment, value bytes only
- [ ] 6.2 Write failing tests for the three sibling-formatting scenarios (two indentation depths in one file, single-line dictionary entries, empty array) and for positional insertion
- [ ] 6.3 Write failing tests for canonical quoting on write and for preservation of existing non-canonical quoting
- [ ] 6.4 Implement path addressing (design D3), the edit primitives and template-sibling formatting (design D6); verify 6.1–6.3 pass

## 7. Corpus

- [ ] 7.1 Build `Tests/Fixtures/corpus/` from Xcode-template projects across the `objectVersion`s available locally, plus a copy of the originating project's `project.pbxproj`; record provenance and licence of each file in `Tests/Fixtures/NOTICE`
- [ ] 7.2 Add the corpus round-trip test; verify every file round-trips byte for byte, and answer design.md's open question about Xcode 27 quoting by inspecting which strings Xcode left bare — update design D5 if the write-side set differs

## 8. Robustness

- [ ] 8.1 Add a seeded mutation fuzzer test (insert, delete, replace random bytes in corpus files; 2,000 iterations in CI) asserting the Fuzzed input scenario; verify it passes and completes in under 30 s
- [ ] 8.2 Add a performance test: parse, 100 edits, serialize on the largest corpus file; verify it completes in under 100 ms in a release build, or record the measurement and a follow-up in design.md
