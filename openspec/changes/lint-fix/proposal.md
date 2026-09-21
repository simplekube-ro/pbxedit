# Proposal

## Why

`lint` can tell a project it has 655 file references in no group; nobody will fix 655 entries by hand, and the predecessor's guidance for the other common defect — a build file in no phase — was "repair by hand with the existing UUID, and never re-run the add script, which mints a second one". Repairs are mechanical, they are exactly the planner steps the tool already has, and the scoped rule check can prove each one. A project should be able to go from damaged to clean in one reviewed commit.

## What Changes

- Add `pbxedit lint --fix`: build one plan that repairs every fixable finding and run it through the shared operation pipeline.
  - **M1** — a build file in no phase is listed in the right phase of the right target, when that target is unambiguous.
  - **M2** — a phase entry that names nothing, or a build file whose file does not resolve, is removed.
  - **M3** — a file reference in no group is made a child of the group for its directory, creating groups as needed.
- Existing objects are always reused. The only IDs minted are for new groups.
- Findings that cannot be repaired safely stay reported, with the reason.
- `--fix --dry-run` shows the plan and diff without writing.

## Capabilities

### New Capabilities
- `integrity-repair`: automatic, verifiable repair of the membership defects `lint` reports.

### Modified Capabilities

None.

## Non-goals

- Repairing structural findings S1–S5, or M4–M6. Each needs a human decision: which duplicate to keep, which target is right.
- Repairing disk findings D1–D2. `remove` and `add` do that, with intent.
- Rewriting a repaired reference's `path` or `sourceTree`. Repairs change membership, not spelling.
- Updating the baseline file automatically.

## Impact

- New: `Sources/PBXOps/Repair/`; `lint` gains `--fix` and `--dry-run`.
- Reuses add's group resolution and the operation pipeline. May require the batch invalidation scope noted as a risk in `typed-project-model`.
- This is the change that enables the originating project's one-commit orphan repair.
- Depends on `add-command`; honours exemptions when `conventions-config` is present.
