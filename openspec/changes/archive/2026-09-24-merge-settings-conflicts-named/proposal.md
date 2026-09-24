# Proposal

## Why

Issue #28, a follow-up to #20: `pbxedit merge` 1.2.0 does ask about a build file's `settings` that both sides changed to different values — the unit is a decision offering `ours` and `theirs-membership`, and `theirs` is refused — but it reports the difference as a one-sided one. Measured on the issue's repro (base has no `settings` on `App/Filtered/F1.swift`'s build file, ours `{COMPILER_FLAGS = "-w"; }`, theirs `{COMPILER_FLAGS = "-Wall"; }` and theirs re-creates the row):

```json
{"what": "settings of the build file in App", "ours": null,
 "theirs": "{COMPILER_FLAGS = \"-Wall\"; }", "merged": "{COMPILER_FLAGS = \"-w\"; }", "conflicting": false}
```

A consumer reading `residuals` (or `owed` after `theirs-membership`) cannot tell that from "only theirs changed the settings", and cannot show the user the value they are keeping: `ours` is `null`. A reference attribute in the same shape has said `ours: "4"`, `conflicting: true` since #20.

The cause is that `PathComparison.compare` (`Sources/PBXOps/Merge/Replay.swift`) resolves reference and build-file attributes three-way — base against ours against theirs, the rule #20 added — but compares `settings`, spelling and parent group against theirs' value alone, so the conflict test never runs on them. #20's design said as much and left it: "A build file's `settings` is already compared against theirs' directly, so a conflict there is already a residual and stays one." It is a residual, but an unlabelled one.

## What Changes

- The per-path comparison applies #20's conflict test — ours differs from base, theirs differs from base, and the two differ from each other, an absent value counting as a value — to a build file's `settings` as well. A conflicting `settings` is a residual **whatever value the result holds**, exactly as for an attribute: no verb writes `settings`, so a result that happens to hold theirs' value holds it by accident and ours' change was still dropped.
- The same test marks a **spelling** (`path`, `name`, `sourceTree`) or **parent group** difference that survives the replay as conflicting, carrying ours' value. For these the conflict only labels a difference that is already reported: the replay *does* write them, through `move` and `add`, and a "whatever the result holds" rule would declare a conflict where the replay reproduced theirs exactly (measured: both sides moving one file to different paths — base `App/Filtered/F1.swift`, ours `App/Views/F1.swift`, theirs `App/Other/F1.swift` — leaves no residual today and the unit rightly offers `theirs`).
- `rows` and `presence` are left alone, and the specs say why: they are the unit's own membership question, which its choices settle and whose three versions the report already prints per path.
- No new residual kind, no new choice, no new check, no JSON shape change: `ours` and `conflicting` are the fields #20 added, and `schemaVersion` stays `1`. Check E keeps matching an owed residual by `(path, kind)`, and check B keeps reading `.settings` as "compare this path's rows without settings".
- The regression is committed as the three-way fixture `Tests/Fixtures/merge/settings-conflict/` and run through the binary for the issue's repro and its both-sides-re-filter variant.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `merge`: "Replay reproduces theirs exactly or says what it cannot" states which values the conflict test covers — a build file's `settings` and the attributes it covers today, whatever the result holds; a spelling or parent-group difference that survives the replay — and why rows and presence are not among them.

## Non-goals

- A verb for build-file `settings`. `docs/design.md` § Out of scope for v1 keeps `settings`, a group other than the directory's and reference attributes as residuals a decision settles; this change names the conflict, it does not resolve it. A `theirs-settings` choice would need a writer and is not in this change.
- Any change to which residuals exist for a *one-sided* `settings` change. Where only theirs changed the settings the comparison still expects theirs' value, reports `conflicting: false`, and the unit still owes it; where only ours did, the residual it produces today is unchanged too.
- Making a conflicting `settings` a text hunk. The unit's paths are neutralised before the line merge by design (merge design D3); check F exists to forbid membership reaching the merge as bytes.
- Any change to the classification, to the skip, to checks A–F, to the line merge, to hunk or unit keys, or to the decisions file shape. A unit that carries a residual is already a decision offering `ours` and `theirs-membership`, so no unit's outcome or choices change; a unit key derives from the paths and the three versions' masked membership, so keys written against `v1.2.0` are unchanged.
- Extending the conflict test to `rows` or `presence`, or widening what counts as membership.
- A version bump inside the change. The release that carries it decides the number.

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. The change is a reporting-fidelity fix inside the shipped `merge` capability.

## Impact

- `Sources/PBXOps/Merge/Replay.swift`: `PathComparison.compare` runs the conflict test on `settings` (with the row counterparts in base and ours it already resolves for build-file attributes) and on spelling and parent group where a difference survives; `PathComparison.conflicting` becomes generic over the compared value so `String?` spellings and group paths go through the one rule.
- Tests: `ResidualTests` (a conflicting `settings`, the one-sided controls, a conflicting `name`, and the move case that must stay conflict-free), `MergeEngineTests` (the repro's residual and `owed` entry, and the both-sides-re-filter variant), `MergeCheckTests` (check E over an unowed `settings` conflict through the `ignoreAttributeConflicts` seam), `MergeCommandTests` (the repro through the binary, text and `--json`), `MergeFixtureFileTests` plus `Tests/Fixtures/merge/settings-conflict/` and its README row.
- `docs/design.md`: the `merge` Commands row (the conflict test's reach), the status line, and a Motivation-table row for issue #28; a dated note at the archived `merge-attribute-conflicts-asked` design's D1.
- No new dependency, no new public type, no CLI surface change. Depends on `merge-attribute-conflicts-asked` (shipped in `v1.2.0`).
