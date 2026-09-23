# Proposal

## Why

Issue #9. Today pbxedit has no answer when `project.pbxproj` has a merge conflict, so the conflict is resolved outside it, and "pbxedit is the only writer of file membership" stops holding exactly where it matters most. A downstream project (RandomPlayer) is building a ~1,650-line Python helper to fill the gap. The helper rebuilds a second model of the file from `plutil -convert json` and `pbxedit query --json`, neutralises membership with `pbxedit remove`, merges the rest with `git merge-file --zdiff3`, replays membership with `pbxedit add`/`remove`/`move`, and runs six checks before writing. Most of that does not depend on the project. A second model of the file can drift from pbxedit's own. And every step that shells out to pbxedit re-parses a 1 MB file. The project-file part belongs in pbxedit, where the model, the planners and the rule set already live. The helper then shrinks to git orchestration.

The same design also removes a conflict that occurs every time today. Two branches that each `add` a different file insert lines at the same places, the section block, the group's `children` and the phase's `files`, so git's line merge conflicts. A semantic merge replays both additions instead.

## What Changes

- **New command `pbxedit merge <base> <ours> <theirs>`.** It is a non-interactive three-way merge of three versions of one `project.pbxproj`. It never prompts, and it writes the merged file only after every check passes. The output file is the project's own `project.pbxproj` by default, located like every other command (`--project`, `.pbxedit.yml`, or the single `.xcodeproj`). `--output <file>` names another file. The three inputs are only read. It honours `--config`, `--dry-run` (report plus a unified diff against `<ours>`, nothing written) and `--json`.
- **Discovery.** Membership is compared per path between base, ours and theirs: a file reference's spelling, resolved path and parent group, and its rows `(target, phase, platform filters, build-file settings)` in Sources, Resources and Headers. The paths each side changed are linked into *units* by path, file-reference ID and build-file ID, so a rename is one unit. This finds reference-only changes (attach, detach, directory moves of files no target builds) as well as membership changes.
- **Classification.** Each unit that theirs changed has one of three outcomes:
  - *replayed*: only theirs changed it;
  - *skipped*: ours already holds the same change;
  - a *decision*: both sides changed it differently, or replaying it cannot reproduce theirs exactly.

  The second kind of decision is a *residual*: build-file `settings`, a reference placed outside its directory's group, or an attribute such as `fileEncoding`, `includeInIndex` or `name`. pbxedit has no verb that writes these. A dry run of the replay against ours finds them, and the replay is then compared with theirs.
- **Merge.** Every unit path is neutralised in base and theirs with `remove`'s own planner. The remaining text is merged three-way with a built-in line merge. Each conflicting hunk is resolved from the decisions input. Theirs' membership is then replayed onto the result as a transition from what the file holds: `add`'s, `remove`'s and `move`'s planners reuse the existing file reference and build files wherever they survive, so their attributes survive too.
- **Verification before anything is written.** A failed check exits `1` naming the object and key:
  - (A) no finding that neither input had;
  - (B) every target's membership equals the expected membership;
  - (C) three-way accounting of every non-membership leaf, keyed by object ID, arrays compared with their order;
  - (D) replay isolation;
  - (E) per-path membership, placement and attributes against theirs;
  - (F) no managed membership reached the result as bytes.
- **Decisions round trip.** Exit `3` when decisions are needed. The report, as text or `--json`, lists every open unit and hunk with a stable key, its base, ours and theirs values, and the allowed choices:
  - `ours` or `theirs` for a unit, and `theirs-membership` in place of `theirs` when it has a residual;
  - `ours` or `theirs` for a hunk, plus `both` only when the two sides change disjoint `(object ID, key path)` sets.

  It also carries a decisions template bound to the SHA-256 of the three inputs. `--decisions <file>` feeds the choices back. A stale or unknown key exits `2`.
- **Exit codes.**
  - `0`: merged and verified, or nothing to do.
  - `1`: a check failed or a step was refused. Nothing is written.
  - `2`: usage error, or input the merge does not support:
    - a file that does not parse or load;
    - a target added or removed by theirs, or removed by ours;
    - a hunk whose resolutions do not parse;
    - decisions for other inputs.
  - `3`: decisions needed.
- **Contract the merge relies on, stated in the `add` spec.** A second `add` of a member with another target and platform set extends its membership and reuses the reference. `add` never rewrites the platform filter of a build file it reuses. The other two facts the issue asks to document are already contract:
  - a batched `remove` that fails writes nothing (`remove`: "Safety, output and dry run", "One unknown path among three");
  - where new objects go (`pbx-model`: "Primitive mutations place content where Xcode does"). The issue's "appended at section end" holds only for a section that is not in ID order. In a sorted section a new object goes in ID order. The merge does not depend on either placement, because it never merges membership lines as bytes.

## Capabilities

### New Capabilities
- `merge`: the `pbxedit merge` command. It covers the inputs and output, discovery and units, classification and residuals, neutralisation and the line merge, replay, checks A–F, the decisions round trip, the report and the exit codes.

### Modified Capabilities
- `add`: "Idempotence and completion" gains the two scenarios the merge's replay relies on: a second target and platform set extends membership, and a reused build file's filter is never rewritten. Both behaviours ship today and are untested as contract.

## Non-goals

- **git integration.** This covers reading index stages, telling a merge from a rebase or a cherry-pick, criss-cross detection, labelling sides by commit, and `.gitattributes` merge-driver registration. Because of the exit-`3` round trip, `merge` is not a merge driver. A driver mode that treats exit `3` as "leave conflicted" could be a follow-up. The command takes three files, and the caller extracts them.
- **Merging `.pbxedit.yml`.** The configuration is a text file outside pbxedit's write scope ("the tool edits `project.pbxproj` and nothing else"). The caller resolves it first. `merge` reads it only for the check's exemptions.
- **Writing anything but the output file.** No workspace, no report file, no template file. The report and the template go to standard output, which keeps the disk-scope non-negotiable intact.
- **Interaction.** The command never prompts and never chooses a side on the user's behalf.
- **New membership verbs.** There is no verb for build-file `settings`, for placing a file in a group other than its directory's, or for reference attributes. These stay residuals that the user settles with a decision, as `docs/design.md` § Purpose and § Out of scope for v1 keep build settings and the like out of scope.
- **Synchronized-folder exception sets.** They stay out of scope (§ Out of scope for v1). Changes inside a synchronized folder travel as bytes and are covered by check C.
- **Targets that appear or vanish on one side**, other than a target only ours added. These exit `2`, because the merge never creates or deletes a target (§ Out of scope for v1: target creation).
- **A third dependency.** The line diff and the three-way merge are implemented in `PBXOps`. SHA-256 comes from Apple's CryptoKit, a system framework on every supported macOS, not a package.

## Impact

- New: `Sources/PBXOps/Merge/` (snapshot and units, classification, the line diff and three-way merge, neutralisation and replay, checks, decisions), `Sources/pbxedit/Merge.swift` and its renderer, `Tests/PBXOpsTests/Merge*Tests.swift`, `Tests/CLITests/MergeCommandTests.swift`, and merge scenarios in `CLITests.OracleTests`. Fixtures are built in the tests from the Xcode-saved `Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj`, plus committed three-way fixtures under `Tests/Fixtures/merge/` for the command tests.
- Changed:
  - `MovePlanner`: the retained-build-file filter rewrite moves into a helper the replay shares. Behaviour is unchanged.
  - `PbxEdit.swift`: the subcommand list, and exit code `3` in the discussion.
  - `CommandOutcome`: a `decisionsNeeded` case.
- Docs:
  - `docs/design.md`: § Decisions (v1 commands), § 4 CLI (commands table, exit codes), § Testing, the status line;
  - README;
  - `CLAUDE.md` (state of the repository);
  - `TODO.md` § 12;
  - `docs/RELEASING.md` § 2 gains a `merge` step in the open-and-save check.
- Release: `v1.1.0` (a new command, compatible with 1.0).
- Depends on `add-command`, `remove-command`, `move-command`, `integrity-rules-lint` and `conventions-config`, all shipped.
