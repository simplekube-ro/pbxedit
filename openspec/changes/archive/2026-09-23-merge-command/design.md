# Design

## Context

See proposal.md § Why. Everything the merge needs to *change* a project already exists and is checked: `AddPlanner` (with `Conventions.Flags` fully set, it infers nothing), `RemovePlanner` (`--all`, `--target`, and the internal `detach`/`prune`), `MovePlanner` (`keepMembership`, with a `DiskReader` it asks only two `exists` questions), the retained-build-file filter rewrite in `MovePlanner.planMembership`, `Plan.apply(to:)` (a plan executed on a value copy of `Project`), the rule set with `Finding.path`, and `OperationRunner.writeAtomically`. Nothing yet *compares* projects: there is no line diff beyond the renderer's `UnifiedDiff`, no three-way merge, no value-level view of a whole project. The downstream reference implementation (RandomPlayer's `resolve-pbxproj-conflict.py` and its design, D1–D11 there) shells out to `pbxedit`, `plutil` and `git merge-file` and keeps a workspace on disk; in-process, the model replaces `plutil` and `query`, the planners replace the CLI calls, and no workspace is needed.

Constraints from `docs/design.md`: pbxedit writes `project.pbxproj` and nothing else; two dependencies only; untouched bytes are never rewritten; IDs are matched exactly; lookup is by resolved path.

## Goals / Non-Goals

**Goals**

- One pass, one report: a single run surfaces every open unit and hunk (the downstream design's "one round trip").
- The merge never *writes* membership any way but through the planners, and never *decides* anything the user did not.
- Every check is a pure function over `Project` values, testable without the command, with a fault seam so each check's Red test can disable the step it guards.

**Non-Goals**

- Git plumbing, `.pbxedit.yml` merging, a merge-driver mode (proposal § Non-goals).
- Minimal hunks in the git sense: the line merge only has to be correct and deterministic; its hunks need not match `git merge-file` byte for byte.

## Decisions

### D1. Layout

`Sources/PBXOps/Merge/`:

| File | Holds |
|---|---|
| `MembershipSnapshot.swift` | per-version view: managed references, rows, path states (D2) |
| `Units.swift` | linking changed paths into units, unit keys (D3), classification (D4) |
| `LineMerge.swift` | Myers line diff and the three-way merge into stable regions and hunks (D6) |
| `Hunks.swift` | resolving hunks, counterfactual builds, governed sets, `both` eligibility, hunk keys (D7) |
| `PlistValue.swift` | a comment-free value view of a tree and its leaf flattening (D8) |
| `Replay.swift` | the transition planner, the trial replay and its per-path comparison, neutralisation (D4, D5, D6) |
| `MergeChecks.swift` | checks A–F (D9) |
| `Decisions.swift` | the decisions file, template, validation (D10) |
| `MergeEngine.swift` | the pipeline and `MergeReport`, what the command renders (D11) |

CLI: `Sources/pbxedit/Merge.swift` (arguments, locating the output, the atomic write and read-back) and `Sources/pbxedit/MergeReport.swift` (text and JSON). `MergeEngine` never touches the disk; the command reads three files, hands bytes to the engine, and writes the one result.

### D2. What a version's membership is

`MembershipSnapshot(project)` holds, per **managed** reference (spec: a `PBXFileReference` with `sourceTree` `<group>` or `SOURCE_ROOT`, a `.relative` resolved path no synchronized folder covers, only `PBXGroup` parents, not any target's `productReference`, and every build file of it listed, at least once, only in Sources, Resources or Headers phases that some target owns — the phases `add --phase` can write; a build file in no phase or in an orphaned phase is damage the replay cannot reproduce, so its reference is text), keyed by resolved path:

- `reference`: ID, `path`, `name`, `sourceTree`, parent IDs, the resolved path of the first parent (`groupPath`), and every other attribute as a `PlistValue` (D8);
- `rows`: for each target (by name) × phase listing a build file of it: phase kind, platform filters (`PlatformFilters.read`), `settings` as a `PlistValue`, build-file ID;
- the *masked* state: the same without any object ID, rows sorted — what "the same membership" means everywhere below.

A non-managed reference and its build files are text (D6) and are accounted for by check C. A path at which two managed references resolve in one version (M4 damage) is recorded, and if it lands in a unit the merge is unsupported (exit `2`): a replay cannot say which reference it means.

*Alternative considered:* rows from every phase kind, like `query --target`. Rejected — a Frameworks or Copy Files row cannot be replayed by any planner, so treating its reference as managed would neutralise lines the replay cannot put back (the downstream design's gap: a managed reference in Frameworks lost its row).

### D3. Units

Changed paths: every path whose masked state differs between base and theirs, or whose reference ID or build-file IDs differ (theirs re-created the objects: masked-equal, but its lines would otherwise arrive as text beside ours'). Linking is a union–find over paths across all three versions: a reference ID or build-file ID seen at two paths (in any versions) joins them, which makes both ends of a rename — including ours' own rename of a path theirs touched — one unit. Units are ordered by their smallest path.

Unit key: `u` + the first 12 hex characters of SHA-256 over the sorted paths and the three masked states, canonically encoded. The same inputs give the same key; a unit whose content changes gets a new key, so a stale decision cannot silently apply.

### D4. Classification and the trial replay

Per unit, over its paths: masked(ours) == masked(theirs) → **skipped**; else masked(ours) == masked(base) → candidate **replay**; else **decision** (`ours`, and `theirs` or `theirs-membership`). Classification compares membership only; attributes are left to the trial, so an attribute ours changed does not by itself force a decision (a deliberate departure from the downstream D5 table, which made any ours-side attribute change a decision: the replay keeps ours' reference, so ours' attribute survives, and check E proves it). *(2026-09-23, change `merge-attribute-conflicts-asked`, issue #20: this holds where **only** ours changed the attribute. Where both sides changed one to different values, the comparison reports a conflicting residual whatever the result holds, so the unit is a decision offering `ours` and `theirs-membership` — and, since the skip above compares membership only, the conflicts are looked for before it too; see that change's design D1 and D3.)*

The **trial**: the unit's transition (D5) planned and applied to ours in memory, then compared with theirs by the per-path comparison of check E (D9). The differences are the unit's residuals. A candidate replay with residuals becomes a decision offering `ours` and `theirs-membership`; a decision unit with residuals offers `theirs-membership` instead of `theirs`. A trial whose planner throws (`noSuchPhase` because ours' target lacks the phase, `unknownTarget`, …) leaves `ours` as the only choice, with the planner's message as the reason — still a decision the user can settle, rather than exit `2`.

The trial runs against ours, while the real replay runs against the text-merged file. The two hold the same membership for unit paths (every unit path is neutralised on the other two sides, D6), so the trial predicts the replay; check E on the real result catches the rare case where text merged elsewhere (a group's `path`) changed what the replay sees.

### D5. The transition planner

`Replay.plan(unit, from current: Project, to theirs: MembershipSnapshot)` returns a sequence of plans, each planned against the project the previous one produced, each applied with `Plan.apply`:

1. **Moves.** For each theirs reference whose ID `current` holds at another path of the unit, when `current` holds no managed reference at theirs' path (keyed on `current` rather than base, so a unit decided `theirs` also moves the file from where ours renamed it): `MovePlanner.plan(from:to:keepMembership: true, disk: ReplayDisk)` where `ReplayDisk` answers `exists(to) = true`, `exists(from) = false`, `files(in:) = []`. Per file, so a directory move becomes its files' moves and add's group resolution plus remove's pruning rebuild the group tree.
2. **Removals.** Paths `current` holds and theirs does not (not moved): `RemovePlanner.plan([path], all: true)`.
3. **References.** Paths theirs holds and `current` does not: `AddPlanner` with `Flags(phase: .none)` — reference and group child only (or none, for an `M3`-exempt path), as add spells it.
4. **Rows**, per path, per target, compared as sorted lists (row order follows build-file IDs, which differ between versions). A target theirs drops → `RemovePlanner.plan([path], target:)`. Otherwise rows are matched by phase kind, since a file may be in two phases of one target (Sources and Resources; two rows in one phase are M5): a kind in both with different filters → the filter rewrite, extracted from `MovePlanner.planMembership` into `PlanBuilder.rewriteFilters(of:to:path:)` and used by both, keeping the build file; a kind only `current` has → `RemovePlanner`'s internal per-phase detach (`plan(_:in:target:phase:)`); a kind only theirs has → `AddPlanner` with `Flags(targets: [T], platformFilters: f, phase: kind)` in its internal `perPhase` mode, where only a build file in a phase of that kind makes the target "already a member". Neither mode is reachable from the CLI: `add` and `remove --target` keep their per-target semantics. A target with two phases of one kind cannot be matched: its rows are removed and theirs' attached, and the trial names whatever that loses.

`theirs-membership` runs the same transition; `ours` and skipped units run nothing. The replay's `touched` sets are unioned only for the report; the check is whole-project (D9 A).

*Alternative considered:* `remove --all` then `add` for every changed path (the downstream's first revision). Rejected, measured downstream: it drops `includeInIndex` and `name`, and it would give every re-filtered file new IDs.

### D6. Neutralisation and the line merge

Neutralisation: `RemovePlanner.plan(pathsHeld, all: true, keeping: kept)` applied to base and to theirs, where `pathsHeld` are the unit paths at which that version has a managed reference — never a path covered only by a synchronized folder (N1 downstream). A throw here is a defect, not a user error (exit `1`, naming the path).

`kept` (`Neutralise.keptGroups`) holds the groups that neutralising base or theirs would prune for being left empty and that theirs holds with a change apart from `children`, or added. Pruned in both copies, such a group reached the text merge only from ours, so theirs' change to it (an `indentWidth`, a `name`) was silently lost, and check C saw an ours-only leaf. Kept, empty, in both copies, the change is merged as text like any other, and check C accounts for it. The same set is passed to the replay's removals and moves (theirs holds the group, so the result must too) and to check D's two neutralisations. A group theirs deleted is not kept: base's pruned copy then matches theirs, as before, and no modify/delete hunk appears for a group whose only file theirs removed. A group theirs left alone is pruned as before, so pruning still keeps a group ours holds out of the text merge's way. *Alternative considered:* no pruning during neutralisation at all. Rejected: a group theirs removed with its last file would then be a modify/delete hunk against ours' untouched copy on every such merge.

Line merge: lines are byte ranges ending in `\n`; they are interned to integers. `LineDiff` is Myers' O((N+M)·D) greedy algorithm with the usual linear-space bookkeeping unnecessary at these sizes (10k lines, D in the hundreds). `ThreeWay.merge(base:ours:theirs:)` diffs base→ours and base→theirs, walks both edit scripts over base, and emits regions: unchanged; changed by one side (take it); changed by both into identical text (take once); otherwise a hunk. Two changes conflict when their base ranges overlap, or when both are insertions at the same base position; a replacement ending where the other side's change starts does not conflict (git conflicts there; a plist line is self-contained, so taking both is exact, and check C would catch it if not). A hunk is then trimmed zealously: lines common to the start (and end) of ours' and theirs' text become stable context, as `--zdiff3` does, so `both` sees only the differing lines.

*Alternatives considered:* `git merge-file` as a subprocess — rejected: a runtime dependency on git, and the tool would stop being a pure function of three files. A tree-level merge of the `objects` dictionary — rejected for v1.1: attractive (no line conflicts inside different objects), but hunks are what the user decides and what the issue asks to report, and the text merge keeps every untouched byte of ours untouched.

### D7. Hunks

For each hunk, three counterfactual texts are built with every *other* hunk resolved `ours` and this one resolved `base`, `ours`, `theirs`. `ours` or `theirs` that does not parse and load → unsupported (exit `2`, naming the hunk). Leaf maps (D8) of the three give `oursTouched = leafDiff(base, ours)` and `theirsTouched = leafDiff(base, theirs)`; the **governed set** is their union, reported as `(object ID, key path)` pairs. `both` is offered when the `both` text parses, the two touched sets are disjoint, and the `both` text's leaves equal base's with ours' changes and theirs' changes applied (so a duplicated dictionary key, which a leaf map would silently hide, disqualifies it — checked by counting duplicate keys in the tree too). *(2026-09-23, change `merge-both-unordered-insertions`, issue #13: the touched sets may also share leaves that are insertions of different elements into one unordered array, each passing D9 C's array rule in the `both` text; see that change's design D1–D2.)* Hunk key: `h` + 12 hex of SHA-256 over the three texts and the sorted governed object IDs; should two hunks still collide (identical text, empty governed sets), the later gets `-2`, `-3` in file order.

When every hunk is decided, the text-merged result (the *pre-replay* project) is the regions with each hunk resolved; it must parse and load (else exit `1`: the merge produced text that is not a project).

### D8. Values and leaves

`PlistValue` is `.string`, `.data`, `.array([PlistValue])`, `.dictionary([(key, PlistValue)])` read from the tree without trivia. `leaves(of: Project)` flattens the root: a dictionary recurses per key (first entry wins, as every lookup does), an array is one leaf (ordered, compared whole or by the array rule), a string or data is one leaf. Keys are paths of strings, so every leaf under `objects` is naturally keyed by object ID: `objects/1000000000000000000000A2/buildSettings/SWIFT_VERSION`. Reports print them as `<ID> buildSettings.SWIFT_VERSION`.

### D9. Checks

- **A** — `RuleSet.standard.evaluate(result, exemptions:)`, whole project, no disk rules. Tolerated: the findings of ours and of theirs, each keyed `(rule, path)` when the finding has a path, else `Finding.identity`. Any other finding fails. Relative, not absolute, because a project with pre-existing findings must still merge (`add`'s "Unrelated damage does not block").
- **B** — per target name: the masked managed rows of the result equal ours' with the rows at every path of each replayed or `theirs`/`theirs-membership` unit replaced by theirs'. Rows of owed residuals compare without the owed fields.
- **C** — over `leaves(baseN)`, `leaves(ours)`, `leaves(theirsN)`, `leaves(pre)`, the three-way rule of the spec; leaves governed by a hunk decided `ours`/`theirs` expect the decided side's counterfactual value; a `both` hunk's leaves follow the ordinary rule. *(2026-09-23, change `merge-accounting-shared-leaves`, issue #12: this holds for a leaf one hunk governs. A leaf several hunks govern composes every governing hunk's counterfactual against the all-`ours` text; see that change's design D1.)* Arrays changed by both sides: multiset `ours + (theirs' additions − ours' additions) − (theirs' removals − ours' removals)` and each side's retained elements as a subsequence in its order. Run on the pre-replay project (a failure costs no replay).
- **D** — `neutralise(result, replayedPaths)` and `neutralise(pre, replayedPaths)`, both keeping D6's `kept` groups, compared by leaves (not bytes: two removals of the same object from differently formatted neighbourhoods need not give identical trivia).
- **E** — the trial comparison (D4) on the result for every replayed path; any difference outside the unit's owed residuals fails. *(2026-09-23, change `merge-attribute-conflicts-asked`, issue #20: an attribute both sides changed to different values is such a difference, so E fails on one that no decision owed; before that change the comparison accepted whichever value the result held and E could not see it.)*
- **F** — between ours and pre-replay: the managed references by ID (spelling, resolved path, parents) and their build files by ID (phases, filters) are identical.

Order: C and F on the pre-replay project; then the replay; then D, E, B, A on the result. The first failing check ends the run with exit `1`; its report names every failing leaf or path, not just the first.

**Fault seam.** `MergeEngine` takes an internal `Faults` option set — `skipTextMerge` (pre-replay = ours), `skipStructuralDiscovery` (units from rows only, no reference-only units), `skipPresenceFilter` (neutralise every unit path in both copies), `wholeDictionaryLeaves`, `multisetArrays`, `replayRemoveAll` — reachable only through `@testable import`, so each Red test of the spec's "fails" scenarios disables the step the check guards. It is not a flag and not an environment variable.

### D10. Decisions

`MergeDecisions` decodes `{"inputs": {"base", "ours", "theirs"}, "units": {key: choice|null}, "hunks": {key: choice|null}}` with `JSONDecoder`. SHA-256 of each input's bytes (CryptoKit's `SHA256`, lower-case hex). A mismatch, a key that matches no open item, or a choice not in the item's `choices` → exit `2`, naming it. `null` means undecided. A decision for an item that needs none (a replayed unit) is "a key that matches nothing". The template is the same object with every open key `null`; it goes to standard output (text: a fenced JSON block after the report; JSON: `template`), never to a file.

### D11. The command

`pbxedit merge <base> <ours> <theirs> [--decisions <file>] [--output <file>] [--project <path>] [--config <path>] [--dry-run] [--json]`. Order: read the three inputs (unreadable → `2`); locate the output (D12); load the configuration against the located project; run the engine; render; write when the outcome is `merged` and not `--dry-run`. The write reuses `OperationRunner.writeAtomically` (made `internal` → shared through a small public `AtomicFile` wrapper in `PBXOps`), then reads back, re-parses and re-runs A and B on the bytes read; a failure restores the previous bytes, exactly as `OperationRunner` does. `modified` compares the bytes on disk after the run with those before it. `CommandOutcome` gains `decisionsNeeded` (`3`); `PbxEdit`'s discussion lists it.

### D12. Where the output goes

`--output` wins. Otherwise `ProjectOptions` locates the project exactly as `add` does and the output is its `project.pbxproj`; if locating fails and there is no `--output`, the usage error says both ways to name it. A configuration that does not load is reported as itself, never as nowhere to write (loading and locating are separate steps, `loadConfig()` then `locate(config:)`). The configuration is bound to the located project's source root (its paths are relative to it, the existing rule). With `--output` alone, no configuration is read and no exemptions apply. With `--output` and `--project` or `--config`, the project is located and the configuration bound to it; an explicit `--config` with no project to find is a usage error that says the configuration needs a source root, rather than silently ignoring a file the user named. The output may be `<ours>` itself (the `git merge-file` convention); the inputs are read fully before anything is written.

### D13. Tests

- `PBXOpsTests/LineMergeTests`: diff minimality on small cases, every region kind, same-position insertions, adjacent replacements, zealous trimming, determinism.
- `PBXOpsTests/MergeFixture` (support): builds ours and theirs from the Xcode-saved base in memory with the planners and a text helper for settings; `MergeEngine` runs on bytes.
- `PBXOpsTests/MergeEngineTests`: one test per spec scenario of units, classification, replay, text, decisions and unsupported inputs, each asserting on the model of the result, that `RuleSet` is clean relative to the inputs, and `plutil -lint` on the serialized result.
- `PBXOpsTests/MergeCheckTests`: C, E, F on synthesised results (wrong configuration, lost reorder, smuggled membership, dropped attribute) and the fault-seam Red tests, each paired with a `lint` that passes on the same result.
- `CLITests/MergeCommandTests`: default and explicit output, nowhere to write, exit codes, `--json` shape, `--dry-run`, decisions round trip, stale decisions, input byte-invariance. Fixtures `Tests/Fixtures/merge/<scenario>/{base,ours,theirs}.pbxproj`, generated once by a documented test helper and committed so the command tests do not depend on the planners they exercise.
- `CLITests/OracleTests`: three merge scenarios read by `xcodebuild -list`.
- The downstream fixture shapes (issue § Acceptance) map onto these: clean replay, rename vs filter, delete vs move, attach/detach, settings residual, adjacent insertions, order-sensitive arrays.

## Risks / Trade-offs

- [The line merge differs from git's, so the hunks a user sees differ from `git diff`'s conflict markers] → They are reported with their three texts and governed keys; nothing depends on git's hunk boundaries.
- [A trial replay against ours may not predict the replay against the text-merged file] → Check E runs on the real result; a mismatch exits `1`, loudly, with nothing written.
- [Accounting keyed by object ID cannot see a value moved between two objects that swap IDs] → IDs are identity in this format; a swap is two changes, both accounted.
- [Performance: several full parses per hunk (counterfactuals)] → Only for conflicting hunks, which are few; the 1 MB downstream file parses in milliseconds (the model's performance test). Measured at apply (task 7.4, `MergePerformanceTests`, release build, Apple silicon): on the largest corpus file (`Alamofire.pbxproj`, 223 KB, 880 objects) with a file added on each side and one conflicting setting, the run to the decisions report takes 0.061 s and the decided run, all six checks included, 0.128 s, against a 2 s limit; the 10k-line line merge takes 0.004 s.
- [`both` hides a duplicate key] → Excluded by D7's duplicate-key count and the leaf equality.
- [A `.pbxedit.yml` that differs between the sides] → Out of scope; the caller resolves it first. The one read is exemptions for check A, which tolerates what either input already had anyway.

## Migration Plan

Additive: a new subcommand; `add`'s spec gains scenarios for behaviour it already has; `MovePlanner`'s filter rewrite moves into a shared helper with no behaviour change (its tests stay green unchanged). Ships as `v1.1.0` per `docs/RELEASING.md`. Rollback is a revert; no file format or flag changes for existing commands.
