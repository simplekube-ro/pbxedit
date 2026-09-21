# Proposal

## Why

The failures that motivated pbxedit — an ID matched by prefix, a file found by basename, a build file with no phase entry — are all failures to know what the project file *means*. `PBXSyntax` gives bytes and structure; this change adds the meaning: objects, IDs, groups, paths and target membership, as a typed view that every command shares.

## What Changes

- Add the `PBXModel` library target, depending on `PBXSyntax`.
- Object table keyed by exact ID; IDs are opaque strings.
- Typed read access for the kinds the tool works with: file references, build files, groups, variant groups, build phases, native targets, synchronized root groups. Every other kind passes through untouched.
- Resolve every group and file reference to a disk path relative to the source root; look files up by that path, never by basename.
- Derived indexes: file reference → build files → phases → targets, and file reference → parent groups.
- Primitive mutations — create and delete objects, add and remove group children and phase entries, set attributes — placed where Xcode would place them, with Xcode's annotation comments.
- Collision-checked ID minting, injectable for deterministic tests.

## Capabilities

### New Capabilities
- `pbx-model`: a typed, exact-ID, path-aware view of an Xcode project file with primitive mutations that preserve all unrelated bytes.

### Modified Capabilities

None.

## Non-goals

- Judging whether a project is *correct*. The model represents broken projects (dangling IDs, orphaned references) faithfully so that `integrity-rules-lint` can report them.
- Multi-step operations such as "add a file". Those are plans built from these primitives, in `add-command` and later.
- Build settings, configurations, schemes, package references: readable as opaque objects only.
- Editing synchronized-group exception sets (out of scope for v1 per `docs/design.md`).

## Impact

- New: `Sources/PBXModel/`, `Tests/PBXModelTests/`, fixtures under `Tests/Fixtures/model/`.
- `Package.swift` gains one library target and one test target. No new dependencies.
- Depends on `lossless-syntax-tree` being merged.
