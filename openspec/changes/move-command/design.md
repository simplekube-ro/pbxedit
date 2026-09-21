# Design

## Context

Everything a move needs exists: directory-to-group resolution and structural `path`/`sourceTree` derivation (add), membership decisions (`Conventions`), detach and group pruning (remove), comment refresh (model). This change is a planner that composes them, plus disk preconditions. See proposal.md for motivation.

## Goals / Non-Goals

**Goals**

- The smallest diff that makes the project true again: two lines for a same-target move between pathful groups.
- One behaviour for the predecessor's "cross-target `git mv`, four manual edits" case.

**Non-Goals**

- Detecting moves from git. The user states `<from>` and `<to>`.

## Decisions

### D1. Move is re-parent + re-path + membership delta

Per file, the planner computes:

1. **Destination group** — add's D5 resolution for `dirname(to)`, creating the chain if needed.
2. **Reference attributes** — add's structural rule gives the new `path`/`sourceTree`; `setAttribute` only where the value changes. A `name` attribute is updated when present, and removed when it would equal `path`.
3. **Parents** — `removeChild` from every current parent, `addChild` to the destination group. A reference with no parent simply gains one.
4. **Membership delta** — `current` = targets from the model; `desired` = `Conventions.targets(for: to)` unless `--keep-membership`. Detach `current − desired` with remove's detach steps; attach `desired − current` with add's build-file steps; for `current ∩ desired`, `setAttribute(platformFilters)` when the desired filters differ.
5. **`refreshAnnotations`** when the basename changed.
6. **Pruning** over the combined plan, from every group that lost a child.

*Alternative considered:* implement as `remove` then `add`. Rejected — new IDs for everything, a diff that hides the rename, and a transient state in which the file is in no target.

### D2. Membership follows the destination by default

The predecessor's documentation shows the failure this avoids: a test moved from the fast to the slow target kept compiling into the fast target because only the path was fixed. Re-deriving membership makes the common intent the default; `--keep-membership` covers reorganizations inside a target where the destination has unusual siblings.

When `current == desired` nothing is emitted for membership, so a plain move stays a two-line diff.

### D3. Ambiguity at the destination is an error naming both exits

Inference ambiguity raises the same `PlanError.ambiguous` as in `add`, with `--keep-membership` added to the suggested remedies, because for a move "leave it as it was" is always a coherent answer.

### D4. Disk preconditions

`DiskReader` (from `integrity-rules-lint`) checks `<to>` exists and `<from>` does not. For a directory move the check runs per member file. These are the only disk reads.

"Both exist" is refused rather than guessed at: it is what a copy looks like, and a copy needs `add`.

### D5. Directory mode is decided by the project, not the disk

`<from>` is a directory move when no reference resolves to it exactly and at least one resolves beneath it. Members are mapped by replacing the `<from>` prefix with `<to>`. Files on disk under `<to>` that are not members are ignored — adding them is `add`'s job — and mentioned in a note with their count.

Groups for the old directory tree are not renamed in place; members are re-parented to groups resolved or created for the new tree, and the old groups fall to pruning. This costs a larger diff for a directory rename than an in-place group rename would, but it is one code path with no special cases for pathless groups, groups holding non-member children, or partial moves.

### D6. Into a synchronized folder

Planned as remove's complete removal for that file, with a note. Out of a synchronized folder has no explicit membership to start from, so it fails the "no reference resolves to `<from>`" validation with a message pointing to `add`.

## Risks / Trade-offs

- [Default membership swap surprises someone reorganizing files] → Every detach and attach is listed in the output and visible in `--dry-run`; `--keep-membership` is named in that output.
- [Directory rename produces a large diff compared with renaming the group in place] → Accepted for v1 (D5). Revisit if users report it; the spec does not forbid an in-place optimisation later since object identity of *groups* is not promised.
- [`name` attribute handling diverges from Xcode's] → Fixture captured from Xcode's own rename of a file in a pathless group pins the expected shape.
