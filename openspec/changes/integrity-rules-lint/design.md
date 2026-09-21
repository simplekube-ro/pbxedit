# Design

## Context

`PBXModel` exposes objects, resolved paths and membership with multiplicity preserved (none / one / several). This change turns those observations into judgements and ships the first executable. See proposal.md for motivation and `docs/design.md` § Rules.

## Goals / Non-Goals

**Goals**

- One rule implementation used two ways: whole-project by `lint`, scoped by every mutating command's pre-write check.
- Output stable enough to be a CI contract: deterministic order, versioned JSON.
- A CLI skeleton the later commands slot into without restructuring.

**Non-Goals**

- A plugin system or user-defined rules.
- Per-rule severity overrides. Exemptions by path arrive with `conventions-config`; severity stays fixed.

## Decisions

### D1. A rule is a pure function from model to findings

```
protocol Rule { var id: RuleID { get }; func evaluate(_ p: Project, disk: DiskReader?) -> [Finding] }
```

Rules hold no state and do not see each other. `RuleSet.evaluate(project, scope:)` runs all rules, then filters by scope. Filtering after evaluation costs a few milliseconds and removes any chance of a scoped run disagreeing with a full run.

*Alternative considered:* scope-aware rules that visit only touched objects. Rejected: every rule would need its own notion of "related", and M4/M5 are inherently global.

### D2. Scope matches object or related object

A `Finding` carries `object` and `related: [ID]`. Scoped evaluation keeps a finding when either intersects the scope. This is what lets `add` fail on an M4 between its new reference and a pre-existing one, while ignoring 600 unrelated M3s.

### D3. S5 becomes a warning about canonical quoting

`docs/design.md` states S5 as "quoted if and only if it requires quoting", as an error. `lossless-syntax-tree` D5 established that a bare string with an illegal character cannot parse at all (that is S1), so the only S5 that can occur is a legal but non-canonical spelling — typically a bare hyphen written by another tool. That is harmless to Xcode, so it is a warning. This change updates `docs/design.md` accordingly.

### D4. M6 target roots are inferred

A directory is the *root of target T* when at least 90% of the project-relative files under that top-level directory which are in any Sources phase are in T's. M6 fires for a Sources build file whose file lies under another target's root while its own target has no files there otherwise. The threshold keeps shared-source directories from producing noise. The rule is a warning because inference can be wrong.

### D5. Disk access behind a protocol

`DiskReader` (exists, list directory) is passed only when `--disk` is set. Tests use an in-memory implementation. Rules other than D1/D2 never receive it, which makes "no file-system access without `--disk`" a compile-time property.

### D6. Baseline format

```json
{ "schemaVersion": 1, "entries": [ { "rule": "M3", "object": "AB12" } ] }
```

Sorted by rule then object, one entry per line, so diffs are reviewable. Keyed by object ID rather than path because IDs survive moves and S/M findings on pathless objects still need a key. D1/D2 findings key on path in the `object` field, since D2 has no object.

### D7. CLI layout

`Sources/pbxedit/` holds `PbxEdit` (root `ParsableCommand`), `ProjectOptions` (`--project`, discovery), `OutputOptions` (`--json`), and one file per subcommand. Commands do no logic: they call `PBXOps` and render the result. Exit codes are mapped in one place from a `CommandOutcome` enum (`ok`, `violations`, `usage`).

## Risks / Trade-offs

- [S2's key list misses a reference-bearing key in some object kind] → Add a corpus test that collects every attribute value shaped like an ID present in the object table, grouped by key, and fails on a key that is neither in the S2 list nor in an explicit ignore list.
- [M3 exemptions are too narrow for package products or too wide] → The corpus test asserts zero M3 findings on freshly generated Xcode template projects, including one with a Swift package dependency.
- [JSON output becomes a contract prematurely] → `schemaVersion` is present from the first release; additive fields do not bump it.
- [M6 false positives] → Warning severity, excluded from the exit code unless `--strict`.
