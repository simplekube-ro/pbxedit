# Tasks

## 1. Owner decisions (blocking)

- [ ] 1.1 (pending-user) Decide the public name given the collision with `ZehMatt/PBXEdit`; if it changes, rename the repository, the executable target and every occurrence in `README.md`, `docs/` and `openspec/`; verify a search for the old name finds only historical mentions
- [ ] 1.2 (pending-user) Choose the licence; add `LICENSE` and the licence line in `README.md`; verify `Tests/Fixtures/NOTICE` is compatible with it
- [ ] 1.3 (pending-user) Create the Homebrew tap repository and a fine-grained token with contents-write on it only, stored as the `TAP_TOKEN` secret; verify the secret is visible to the release workflow

## 2. Version

- [ ] 2.1 Write failing CLI tests: `--version` exits `0`; output matches `^\d+\.\d+\.\d+(-dev(\+[0-9a-f]{7})?)?$`; with the build-hash environment variable set the hash appears
- [ ] 2.2 Add `Version.swift` and wire `--version` per design D1; verify 2.1 passes

## 3. Oracle lane

- [ ] 3.1 Gather the existing per-command `xcodebuild -list` tests into an `OracleTests` suite that fails, rather than skips, when `xcodebuild` is missing and an `ORACLE_REQUIRED` variable is set; verify the suite passes locally
- [ ] 3.2 Add the `oracle` job to `ci.yml` with Xcode selected explicitly and its version printed; verify the job is green and then mark it required in branch protection
- [ ] 3.3 Prove the lane bites: on a throwaway branch make `add` emit `platformFilters = ["ios"]`, confirm the `oracle` job fails, and record the run URL in this change's design.md; delete the branch

## 4. Release workflow

- [ ] 4.1 Add `release.yml` triggered by `v*.*.*` tags: `needs` `test` and `oracle`, checks tag against `Version.swift`, builds universal per design D2, asserts `lipo -archs` and the minimum OS load command, packages the archive and `.sha256`, publishes the release
- [ ] 4.2 Rehearse with a pre-release tag `v0.0.1-rc1` on a fork or with `draft: true`; verify the archive name, checksum file contents and both architectures, then delete the rehearsal release and tag
- [ ] 4.3 Add a workflow test pushing a tag whose version disagrees with `Version.swift` in the rehearsal setting; verify the workflow fails before publishing

## 5. Homebrew

- [ ] 5.1 Write the formula with a `test do` block running `--version`; add the release-workflow step that commits the new `url`, `sha256` and `version` to the tap; verify `brew install` from the tap and `brew test` succeed against the rehearsal release

## 6. Documentation

- [ ] 6.1 Add Install, Pinning (design D5 snippet) and Supported platforms sections to `README.md`; add a CI step that runs the pinning snippet against the latest release with both a right and a wrong checksum; verify the step passes after the first real release
- [ ] 6.2 Write `docs/RELEASING.md` with the version bump, the manual Xcode open-and-save check with a field for the Xcode version, the tag command, and the post-release Homebrew verification; verify it satisfies the Release checklist scenario line by line

## 7. First releases

- [ ] 7.1 Follow `docs/RELEASING.md` to cut `v0.1.0`; verify the release assets, `brew install`, and that the pinning snippet fetches and verifies it
- [ ] 7.2 After `lint-fix` has shipped, cut `v1.0.0` by the same procedure; verify as in 7.1 and record the Xcode version used for the manual check
