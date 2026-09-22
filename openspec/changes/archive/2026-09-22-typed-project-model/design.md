# Design

## Context

`PBXSyntax` provides a lossless tree addressed by structural path, with sibling-formatted edits. This layer interprets that tree as an Xcode project. See proposal.md for motivation and `docs/design.md` § Architecture 2.

Two facts from the originating project constrain the design: 38% of file references have no parent group, and several directories hold files with the same basename in different targets. The model must represent both without complaint.

## Goals / Non-Goals

**Goals**

- One place that knows Xcode's object kinds, comment conventions and section layout.
- Queries cheap enough that rules and inference can call them freely.
- Mutations that are individually trivial and individually verifiable by diff.

**Non-Goals**

- Validation. The model never refuses a mutation because the result would be "wrong"; that judgement belongs to the rule set.
- Transactions. A failed multi-step plan is discarded along with the whole in-memory model; nothing needs rollback.

## Decisions

### D1. The model is a view; the tree is the only state

`Project` owns one syntax tree. Typed objects (`FileReference`, `Group`, …) are lightweight values holding an ID and the object's own `DictionaryNode` from the tree (copy-on-write, so no bytes are duplicated), reading attributes from it on demand. There is no second, typed copy to keep in sync, so an unknown attribute or kind can never be lost. `Project` is a value type: every mutation goes through one function that edits the tree and drops the cache, so a copy taken before a mutation is an independent snapshot — which is what `PBXOps` needs to check a post-edit model against the original.

Typed views cover the kinds the tool mutates plus the kinds that stand in the same structural position and would otherwise break an index: `Group` covers `PBXGroup`, `PBXVariantGroup` and `XCVersionGroup` (all have `children` and take part in path resolution); `BuildPhase` covers the seven `*BuildPhase` kinds (all have `files`); `Target` covers `PBXNativeTarget`, `PBXAggregateTarget` and `PBXLegacyTarget` (all have `buildPhases`). Each view exposes its `isa`. Everything else is an opaque `Object`.

*Alternative considered:* decode into Swift structs and re-encode, as tuist/XcodeProj does. Rejected in `docs/design.md` — it is what forces whole-file re-serialization.

### D2. Indexes are derived and rebuilt after mutation

Three indexes — parents (child → groups), paths (resolved paths and their reverse lookups, built on parents) and membership (file reference → build files → phases → targets) — are each computed in one pass over `objects` when first queried and cached. A mutation drops the indexes it can affect: a child edit drops parents and paths, a phase-entry edit drops membership, an attribute edit drops all three, a comment edit drops none. Invalidation is lazy, so a plan applied without queries in between costs nothing beyond the edits themselves.

Two mutations are patched instead of dropped, because a bulk M3 repair makes them hundreds of times and queries between them: creating a file reference or synchronized root group (an orphan at the root) and giving an orphan its first parent. The object table and the section map are patched on every create and delete for the same reason; table positions are hints, checked against the entry they name and corrected by a scan when an insertion has shifted them. A test asserts after every kind of mutation that each patched structure equals one built from scratch, so correctness still does not depend on the bookkeeping being right — only speed does.

### D3. Multiplicity is data

`parents(of:)` returns an array; `phases(of:)` returns an array. Zero or several entries are legal results, because reporting them is how rules M1, M3 and M5 work.

### D4. Path resolution

`resolve(group)` = `resolve(parent)` joined with the group's `path` when `sourceTree` is `<group>`; its `path` alone when `SOURCE_ROOT`; absolute when `<absolute>`. A group with no `path` resolves to its parent's path. A reference with several parents resolves through the first in object order, and the ambiguity is visible through D3. Resolved paths are normalized (`.` and `..` collapsed, no trailing slash) and compared case-sensitively.

The reverse question — "which existing group represents directory D?" — is answered by an index from resolved path to groups. Several groups may resolve to one directory; callers receive all of them, ordered by depth then object order.

### D5. Sections are found in trivia

Section markers are comments, so they live in the leading trivia of the first entry of each block and, for `End`, of the entry after the block — or of `objects`' closing brace for the last block. `SectionMap` scans the trivia of `objects`' entries once and records each block's entry range. Inserting the first entry into a new block writes both markers into the new entry's trivia and the following entry's (or closing brace's) trivia; deleting the last entry of a block removes both markers, as Xcode does not write empty sections. A new block's entry takes the single-line or multi-line layout Xcode uses for its kind (`PBXBuildFile`, `PBXFileReference` and `PBXFileSystemSynchronizedRootGroup` on one line, everything else across lines); an entry added to an existing block copies its sibling's layout.

This requires a small addition to `PBXSyntax`, all trivia-only so no value bytes change: get and set the leading trivia of an entry, element or the root; get and set the leading trivia of a container's closing delimiter; get and set the annotation comment after a value (`fileRef = X /* Foo.swift */;`) and after a dictionary key (`X /* Foo.swift */ = {`). `replaceValue` cannot serve the last two because it rewrites the value with canonical quoting, which would change bytes the caller did not name.

### D6. Comments are generated from one function

`annotation(for: ID)` returns the comment text Xcode would write: `name ?? path` for references and groups, `"<file> in <phase>"` for build files, the phase's `name` or its default for its kind (`Sources`, `Frameworks`, `Resources`, `Headers`, `CopyFiles`, `ShellScript`, `Rez` — all seven witnessed in the corpus), the target's `name`, `Project object` for the project. A build file that is in no phase has no Xcode comment (Xcode never writes one), so `annotation(for:)` is `nil` until `addPhaseEntry` puts it in a phase, which then writes the definition-line comment. Kinds the model does not know have no annotation.

`refreshAnnotations(for: ID)` rewrites the comment at the definition and at every reference to the ID among the objects — but only where a comment already exists: Xcode leaves some references bare (`mainGroup`, `remoteGlobalIDString`) and the model must not add comments Xcode would not. Renaming a file reference also refreshes its build files, whose comments embed the file name; renaming a phase refreshes its build files likewise. `setAttribute` calls it after every change.

### D7. ID minting

`IDMinter` wraps a `RandomNumberGenerator`; the default is the system generator, tests pass a seeded one. It produces 12 random bytes as uppercase hex — all eight bytes of one `next()` and the low four of a second — and retries while the table or the session's minted set contains the value.

### D8. What the model refuses, and what it does not

The model refuses only what it cannot express: an unknown object, an ID that already exists, a child or phase entry that is not there to remove, a container of the wrong kind, and changing `isa` (delete and recreate instead). It never refuses a mutation because the result would be *wrong*: deleting an object leaves the references to it (rule S2's business), adding a child twice or a build file to two phases is allowed (rules S3 and M5 report it). Loading refuses only a non-dictionary root, a missing or non-dictionary `objects`, and a missing or unresolvable `rootObject`.

## Risks / Trade-offs

- [Rebuilding indexes after every mutation is quadratic for bulk repairs] → `lint-fix` may apply hundreds of mutations. Measured in this change with a 700-repair test (`ModelPerformanceTests`: create a file reference, add it as a group child — the M3 repair shape) on the largest corpus file, `Alamofire.pbxproj` (222,891 bytes, 880 objects), in three shapes: no queries between repairs (plan, then apply), a parent-index query after each repair, and a path-index query after each repair (the lookup an M3 repair needs). The test also runs on every `PBXEDIT_EXTRA_CORPUS` file, so the originating project is measured locally without being committed. **Result, release build, Apple silicon: 0.198 s, 0.202 s and 0.200 s** against a limit of 1 s; debug build about 2 s, 2 s and 4 s against a guard of 30 s. Before the D2 patching the same three shapes took 0.99 s, 2.96 s and 1.90 s (rebuilding the object table and section map on every create, and the whole path index on every query), so the patching is what makes the interleaved shapes affordable. **No batch scope is needed** (TODO § 2 and § 9): `lint-fix` may query between repairs; the plan-then-apply shape is the cheapest, but not necessary. The remaining per-repair cost is the tree edit itself, which is what `PBXSyntax` measures. Follow-ups: the number scales with the file (about 0.25 ms per repair here); the originating project is roughly three times larger, so its 655-orphan repair is expected well under the two seconds TODO § 9 allows, which change 9 verifies. `swift test` in CI is a debug build, where the test only guards against a blow-up; the 1 s limit is enforced by the existing release-mode CI step, whose `--filter PerformanceTests` matches `ModelPerformanceTests` as well.
- [The trivia accessors and the quoted-string fast path touch `PBXSyntax`] → Both are covered by new `PBXSyntaxTests` (`TriviaAccessTests`) and by the unchanged corpus round-trip, fuzzer and hygiene tests. The fast path in `StringNode.matches` and `value` — a quoted string with no backslash is compared and decoded without the escape decoder — incidentally brought the syntax layer's own benchmark from 7.2 ms to 4.7 ms (median, release).
- [Xcode's default phase names and comment conventions are learned by observation] → Encoded in one table (`Kind.buildPhaseDefaultNames`, `annotation(for:)`), all seven phase kinds witnessed in the corpus. `CorpusModelTests.testAnnotationsAgreeWithEveryCommentXcodeWrote` checks the table against every definition-line comment in every corpus file where the model has an opinion (over 3,000 objects): all agree. The corpus round-trip proves existing comments survive.
- [Trivia access widens the `PBXSyntax` API] → Keep it to a getter and setter on entries; add its tests to `PBXSyntaxTests` in this change.
- [Case-insensitive file systems] → Paths are compared case-sensitively because the project file is. A case-only mismatch with disk is a disk-rule concern, not a model concern.
