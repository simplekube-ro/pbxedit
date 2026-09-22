# Proposal

## Why

`lint` can tell a project it has 655 file references in no group; nobody will fix 655 entries by hand, and the predecessor's guidance for the other common defect — a build file in no phase — was "repair by hand with the existing UUID, and never re-run the add script, which mints a second one". Repairs are mechanical, they are exactly the planner steps the tool already has, and the rule set can prove each one. A project should be able to go from damaged to clean in one reviewed commit.

## What Changes

- Add `pbxedit lint --fix`: build one plan that repairs every fixable finding and run it through the shared operation pipeline.
  - **M1** — a build file in no phase is listed in the right phase of the right target, when that target is unambiguous; one whose `fileRef` and `productRef` both fail to resolve is deleted, as M2 deletes one in a phase.
  - **M2** — a phase entry that names nothing, or a build file whose file does not resolve, is removed.
  - **M3** — a file reference in no group is made a child of the group for its directory, creating groups as needed, when that leaves it resolving to the same path.
- Existing objects are always reused. The only IDs minted are for new groups.
- Findings that cannot be repaired safely stay reported, with the reason.
- The check is stronger than an ordinary operation's: the complete finding set before and after, not the touched scope.
- `--fix --dry-run` shows the plan and diff without writing.

## Capabilities

### New Capabilities
- `integrity-repair`: automatic, verifiable repair of the membership defects `lint` reports.

### Modified Capabilities

None.

## Non-goals

- Repairing structural findings S1–S5, or M4–M6. Each needs a human decision: which duplicate to keep, which target is right.
- Repairing disk findings D1–D2. `remove` and `add` do that, with intent.
- Rewriting a repaired reference's `path` or `sourceTree`. Repairs change membership, not spelling; an orphan whose spelling cannot survive grouping is reported, with `remove` then `add` as the way to re-spell it.
- Updating the baseline file automatically.

## Impact

- New: `Sources/PBXOps/Repair/` (`RepairPlanner`, the three fixers, `RepairPlan`); `lint` gains `--fix` and `--dry-run`; `OperationRunner` gains a `verification` parameter, `.scoped` by default so every shipped command is unchanged.
- Reuses add's group resolution, remove's step shapes and the operation pipeline. No batch invalidation scope exists in `PBXModel` and none is needed: `typed-project-model` measured 700 create-and-add-child repairs with a query after each at 0.20 s in a release build (its archived design, Risks); this change measures the repair itself.
- This is the change that enables the originating project's one-commit orphan repair.
- Depends on `add-command`; honours exemptions when `conventions-config` is present.
