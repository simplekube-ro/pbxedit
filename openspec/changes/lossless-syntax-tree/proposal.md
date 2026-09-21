# Proposal

## Why

Every other layer of pbxedit reads and edits `project.pbxproj`. The tool's central promise — an edit changes only the bytes it means to change — can only be kept if the file is read into a structure that remembers every byte. Nothing exists yet, so this change also creates the package.

## What Changes

- Create the SwiftPM package: `PBXSyntax` library target, its test target, Swift 6 language mode, a CI workflow running `swift test` on macOS.
- Add a parser for the old-style ASCII property list used by `project.pbxproj`: dictionaries, arrays, quoted strings, bare strings, data literals, `/* */` and `//` comments.
- Keep all whitespace and comments as trivia so the tree serializes back to the exact input bytes.
- Add edit primitives — insert, remove and replace, in dictionaries and arrays — that leave all other bytes untouched and format new content like its neighbours.
- Report malformed input as an error with a line and column; never crash.
- Add a round-trip corpus and a mutation fuzzer as permanent tests.

## Capabilities

### New Capabilities
- `pbx-syntax`: lossless parsing, serialization and surgical editing of old-style property-list text, with no knowledge of Xcode.

### Modified Capabilities

None.

## Non-goals

- Any Xcode semantics: object kinds, IDs, sections, groups. That is `typed-project-model`.
- XML or binary property lists. A project file in either form is rejected with a clear error.
- Reformatting or normalizing a file. The layer never changes bytes it was not asked to change.
- A command-line interface. The first command arrives with `integrity-rules-lint`.

## Impact

- New repository content: `Package.swift`, `Sources/PBXSyntax/`, `Tests/PBXSyntaxTests/`, `Tests/Fixtures/`, `.github/workflows/ci.yml`.
- No dependencies.
- `docs/design.md` § Architecture 1 is implemented as written, with one refinement recorded in design.md of this change: the set of characters accepted in a bare string is wider than the set the writer leaves unquoted.
