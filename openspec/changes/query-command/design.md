# Design

## Context

`PBXModel` already answers these questions in memory; this change is a rendering of its membership indexes plus the first handling of user-supplied paths. See proposal.md for motivation.

## Goals / Non-Goals

**Goals**

- A path-argument convention decided once and reused by every later command.
- A JSON shape that is the same object `add`, `remove` and `move` later embed in their own output as "membership after the operation".

**Non-Goals**

- Performance work. Loading dominates; a query is an index lookup.

## Decisions

### D1. Path arguments: cwd-relative in, source-root-relative inside

`PathArgument.resolve(_ raw:, cwd:, sourceRoot:)` makes the argument absolute against the current directory, normalizes it lexically (no symlink resolution, no disk access), and strips the source-root prefix. Everything downstream sees source-root-relative paths only. It lives in `PBXOps` so all commands share it.

*Alternative considered:* always interpret arguments relative to the source root. Rejected: shell completion and agent habits produce cwd-relative paths, and a silent mismatch would surface as "not a member".

Lexical normalization only, because `query` must not touch the disk and because a moved or deleted file still needs to be addressable.

### D2. One `MembershipReport` type

```
MembershipReport { path, member, fileReference?, groupPath?, groups: [ID], memberships: [Membership], synchronized: SyncCoverage? }
Membership { target?, phase?, buildFile, platformFilters: [String] }
```

`Codable`, with optionals encoded as `null` rather than omitted so consumers can rely on keys being present. Later commands return `[MembershipReport]` for the paths they touched.

### D3. Exit code `1` for non-members

An agent's verification step is `pbxedit query <file>`; it must fail when the file is not built. A path covered by a synchronized group counts as success because it *is* built.

### D4. Facts, not judgements

A build file with no phase is rendered as a membership with `target: null, phase: null`. `query` does not print rule IDs; the human renderer adds the hint "run `pbxedit lint`" when a report contains an absent group or phase.

## Risks / Trade-offs

- [Lexical normalization disagrees with the disk when symlinks are involved] → Accepted. The project file stores lexical paths; matching it lexically is the consistent choice. Documented in `--help`.
- [The JSON shape is reused by three later commands, so a mistake here propagates] → `schemaVersion` plus additive-only evolution; reviewed against `add-command`'s needs before this change is applied.
