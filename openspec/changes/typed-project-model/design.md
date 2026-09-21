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

`Project` owns one syntax tree. Typed objects (`FileReference`, `Group`, …) are lightweight values holding an ID and reading attributes from the tree on demand. There is no second, typed copy to keep in sync, so an unknown attribute or kind can never be lost.

*Alternative considered:* decode into Swift structs and re-encode, as tuist/XcodeProj does. Rejected in `docs/design.md` — it is what forces whole-file re-serialization.

### D2. Indexes are derived and rebuilt after mutation

Parent-group, build-file, phase and target indexes are computed in one pass over `objects` and cached. Any mutation invalidates the cache; the next query rebuilds it. With roughly 5,000 objects a rebuild is sub-millisecond, and correctness does not depend on incremental bookkeeping.

### D3. Multiplicity is data

`parents(of:)` returns an array; `phases(of:)` returns an array. Zero or several entries are legal results, because reporting them is how rules M1, M3 and M5 work.

### D4. Path resolution

`resolve(group)` = `resolve(parent)` joined with the group's `path` when `sourceTree` is `<group>`; its `path` alone when `SOURCE_ROOT`; absolute when `<absolute>`. A group with no `path` resolves to its parent's path. A reference with several parents resolves through the first in object order, and the ambiguity is visible through D3. Resolved paths are normalized (`.` and `..` collapsed, no trailing slash) and compared case-sensitively.

The reverse question — "which existing group represents directory D?" — is answered by an index from resolved path to groups. Several groups may resolve to one directory; callers receive all of them, ordered by depth then object order.

### D5. Sections are found in trivia

Section markers are comments, so they live in the leading trivia of the first entry of each block and, for `End`, of the entry after the block. `SectionMap` scans the trivia of `objects`' entries once and records each block's entry range. Inserting the first entry into a new block writes both markers into the new entry's trivia and the following entry's trivia. This requires one addition to `PBXSyntax`: read and write access to an entry's leading trivia.

### D6. Comments are generated from one function

`annotation(for: ID)` returns the comment text Xcode would write: `name ?? path` for references and groups, `"<file> in <phase>"` for build files, the phase's `name` or its default for its kind, the target's `name`. Rename calls `refreshAnnotations(for: ID)`, which rewrites the comment at the definition and at every reference found through the indexes.

### D7. ID minting

`IDMinter` wraps a `RandomNumberGenerator`; the default is the system generator, tests pass a seeded one. It produces 12 random bytes as uppercase hex and retries while the table or the session's minted set contains the value.

## Risks / Trade-offs

- [Rebuilding indexes after every mutation is quadratic for bulk repairs] → `lint-fix` may apply hundreds of mutations. Measure in this change with a 700-mutation test; if it exceeds one second, add a batch scope that defers invalidation.
- [Xcode's default phase names and comment conventions are learned by observation] → Encode them in one table with a fixture per kind captured from Xcode output; the corpus round-trip already proves existing comments survive.
- [Trivia access widens the `PBXSyntax` API] → Keep it to a getter and setter on entries; add its tests to `PBXSyntaxTests` in this change.
- [Case-insensitive file systems] → Paths are compared case-sensitively because the project file is. A case-only mismatch with disk is a disk-rule concern, not a model concern.
