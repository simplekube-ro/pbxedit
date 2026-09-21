# Tasks

## 1. Target and fixtures

- [ ] 1.1 Add the `PBXModel` library and `PBXModelTests` targets to `Package.swift`; verify `swift build` succeeds
- [ ] 1.2 Create `Tests/Fixtures/model/`: a small hand-auditable project (two targets, nested groups with and without `path`, one shared source, one synchronized root group) and a `broken` variant (dangling `fileRef`, orphaned reference, build file in no phase, ID pair `X`/`X0`); verify both pass `plutil -lint` and round-trip through `PBXSyntax`

## 2. Loading and lookup

- [ ] 2.1 Write failing tests for Exact-ID lookup (the `TVOSTEST0002` / `TVOSTEST00020` scenario), opaque IDs, and the two Broken projects load scenarios
- [ ] 2.2 Implement `Project` loading, the object table and typed object views per design D1; verify 2.1 passes
- [ ] 2.3 Write a failing test for Unknown kinds pass through, asserting the diff is one line; implement opaque objects; verify it passes

## 3. Paths

- [ ] 3.1 Write failing tests for the three Path resolution scenarios and the two Lookup by resolved path scenarios
- [ ] 3.2 Implement resolution, normalization and the path-to-reference and path-to-group indexes per design D4; verify 3.1 passes

## 4. Membership

- [ ] 4.1 Write failing tests for both Membership indexes scenarios and for the synchronized root group scenario, including `platformFilters` on a build file
- [ ] 4.2 Implement the derived indexes with invalidate-on-mutation per design D2–D3; verify 4.1 passes

## 5. Sections, comments, IDs

- [ ] 5.1 Add leading-trivia get and set on entries to `PBXSyntax`, test-first in `PBXSyntaxTests`; verify round-trip tests still pass
- [ ] 5.2 Write failing tests for both placement scenarios (sorted section, first object of a kind) and for a file with no section markers
- [ ] 5.3 Implement `SectionMap` and object creation per design D5; verify 5.2 passes and the output passes `plutil -lint`
- [ ] 5.4 Write failing tests for annotation comments on create and for the Rename scenario; implement `annotation(for:)` and `refreshAnnotations(for:)` per design D6; verify they pass
- [ ] 5.5 Write a failing test for the ID collision scenario with a scripted generator; implement `IDMinter`; verify it passes

## 6. Primitive mutations

- [ ] 6.1 Write failing diff-based tests, one per primitive (create, delete, add child, remove child, add phase entry, remove phase entry, set attribute), each asserting the exact changed lines
- [ ] 6.2 Implement the primitives; verify 6.1 passes and every mutated fixture passes `plutil -lint`

## 7. Scale

- [ ] 7.1 Add a test applying 700 add-child mutations to the originating project's file from the corpus; verify it completes in under one second in a release build, or implement the deferred-invalidation batch scope from design.md's first risk and re-measure
- [ ] 7.2 Load every corpus file through `PBXModel` and assert no load errors and a byte-identical re-serialization; verify the test passes
