# Tasks

## 1. Owner decisions (blocking)

*Status (2026-09-22): 2.1, 2.2, 3.1 and 6.2 are applied on the `release-distribution` branch. Every other task needs the owner: the three decisions below, pushes (branches, tags, the tap), repository settings (branch protection, the `TAP_TOKEN` secret), or files under `.github/` that a teammate session cannot write. The workflow YAML, the `oracle` job, the formula and the README sections are drafted under `docs/release/`.*

- [ ] 1.1 (pending-user) Decide the public name given the collision with `ZehMatt/PBXEdit`; if it changes, rename the repository, the executable target and every occurrence in `README.md`, `docs/` and `openspec/`; verify a search for the old name finds only historical mentions
- [ ] 1.2 (pending-user) Choose the licence; add `LICENSE` and the licence line in `README.md`; verify `Tests/Fixtures/NOTICE` is compatible with it
- [ ] 1.3 (pending-user) Create the Homebrew tap repository and a fine-grained token with contents-write on it only, stored as the `TAP_TOKEN` secret; verify the secret is visible to the release workflow

## 2. Version

- [x] 2.1 Write failing CLI tests (`CLITests.VersionTests`): `--version` exits `0` with one line on standard output; the output matches `^\d+\.\d+\.\d+(-dev(\+[0-9a-f]{7})?)?$`; with `PBXEDIT_BUILD_HASH` set to a hash the `+` and first seven characters appear; unset, empty or non-hex it does not
- [x] 2.2 Add `Version.swift` and wire `--version` per design D1; verify 2.1 passes

## 3. Oracle lane

- [x] 3.1 The `OracleTests` suite already exists (design Context). Write the failing unit test of the gate decision (`OracleTests.gate(xcodebuildAvailable:required:)` → run, skip or fail), then make the suite fail, rather than skip, when `xcodebuild` is missing and `ORACLE_REQUIRED` is set to a non-empty value; verify the suite passes locally and record the manual no-Xcode check in design.md Evidence
- [ ] 3.2 Add the `oracle` job to `ci.yml` with Xcode selected explicitly and its version printed; verify the job is green and then mark it required in branch protection — *owner: job drafted in the report; needs a push and branch protection*
- [ ] 3.3 Prove the lane bites: on a throwaway branch make `add` emit `platformFilters = ["ios"]`, confirm the `oracle` job fails, and record the run URL in this change's design.md; delete the branch — *owner: needs a pushed branch and a CI run*

## 4. Release workflow

- [ ] 4.1 Add `release.yml` triggered by `v*.*.*` tags: `needs` `test` and `oracle`, checks tag against `Version.swift`, builds universal per design D2, asserts `lipo -archs` and the minimum OS load command, packages the archive and `.sha256`, publishes the release — *owner: workflow drafted in the report (`.github/` cannot be written here); the universal build, `lipo` and `LC_BUILD_VERSION` checks are proven locally in design.md Evidence*
- [ ] 4.2 Rehearse with a pre-release tag `v0.0.1-rc1` on a fork or with `draft: true`; verify the archive name, checksum file contents and both architectures, then delete the rehearsal release and tag — *owner: needs a tag push*
- [ ] 4.3 Add a workflow test pushing a tag whose version disagrees with `Version.swift` in the rehearsal setting; verify the workflow fails before publishing — *owner: needs a tag push*

## 5. Homebrew

- [ ] 5.1 Write the formula with a `test do` block running `--version`; add the release-workflow step that commits the new `url`, `sha256` and `version` to the tap; verify `brew install` from the tap and `brew test` succeed against the rehearsal release — *owner: formula and tap step drafted in the report; needs the tap repository (1.3) and a rehearsal release (4.2)*

## 6. Documentation

- [ ] 6.1 Add Install, Pinning (design D5 snippet) and Supported platforms sections to `README.md`; add a CI step that runs the pinning snippet against the latest release with both a right and a wrong checksum; verify the step passes after the first real release — *owner: README is gated on the public name (1.1); the three sections are drafted in the report*
- [x] 6.2 Write the failing `CLITests.ReleasingDocumentTests` (the Release checklist scenario's four items as section headings), then `docs/RELEASING.md` with the version bump, the manual Xcode open-and-save check with a field for the Xcode version, the tag command, and the post-release Homebrew verification; verify the test passes and the document satisfies the scenario line by line

## 7. First releases

- [ ] 7.1 Follow `docs/RELEASING.md` to cut `v0.1.0`; verify the release assets, `brew install`, and that the pinning snippet fetches and verifies it — *owner: needs 1.x–5.1 and a tag push*
- [ ] 7.2 After `lint-fix` has shipped, cut `v1.0.0` by the same procedure; verify as in 7.1 and record the Xcode version used for the manual check — *owner: `lint-fix` has shipped; needs 7.1, the manual open-and-save check (RELEASING.md § 2) and a tag push*
