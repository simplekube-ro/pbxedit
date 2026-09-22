# Tasks

## 1. Owner decisions (blocking)

*Status (2026-09-22): 1.1, 1.2, 2.1, 2.2, 3.1 and 6.2 are done; the `oracle` job (3.2), `release.yml` (4.1) and the tap formula (5.1) are in place but unverified until the first push and the rehearsal. What remains needs the owner: the `TAP_TOKEN` secret, pushes (branches, tags), branch protection, the rehearsal and the releases.*

- [x] 1.1 Decide the public name given the collision with `ZehMatt/PBXEdit` — decided 2026-09-22: the name stays `pbxedit`; no renames; the `<org>/<name>` placeholders are filled with `simplekube-ro/pbxedit`
- [x] 1.2 Choose the licence; add `LICENSE` and the licence line in `README.md`; verify `Tests/Fixtures/NOTICE` is compatible with it — MIT (2026-09-22); `LICENSE` added, `README.md` created with the Install/Pinning/Supported platforms sections and a Licence section; every corpus file is MIT per `NOTICE`
- [x] 1.3 Create the Homebrew tap repository and a fine-grained token with contents-write on it only, stored as the `TAP_TOKEN` secret; verify the secret is visible to the release workflow — *tap `simplekube-ro/homebrew-tap` with `Formula/pbxedit.rb`; `TAP_TOKEN` is an organization secret shared with the repository; visibility to the workflow is proven by the rehearsal's "Commit and push the tap" step (4.2)*

## 2. Version

- [x] 2.1 Write failing CLI tests (`CLITests.VersionTests`): `--version` exits `0` with one line on standard output; the output matches `^\d+\.\d+\.\d+(-dev(\+[0-9a-f]{7})?)?$`; with `PBXEDIT_BUILD_HASH` set to a hash the `+` and first seven characters appear; unset, empty or non-hex it does not
- [x] 2.2 Add `Version.swift` and wire `--version` per design D1; verify 2.1 passes

## 3. Oracle lane

- [x] 3.1 The `OracleTests` suite already exists (design Context). Write the failing unit test of the gate decision (`OracleTests.gate(xcodebuildAvailable:required:)` → run, skip or fail), then make the suite fail, rather than skip, when `xcodebuild` is missing and `ORACLE_REQUIRED` is set to a non-empty value; verify the suite passes locally and record the manual no-Xcode check in design.md Evidence
- [ ] 3.2 Add the `oracle` job to `ci.yml` with Xcode selected explicitly and its version printed; verify the job is green and then mark it required in branch protection — *job added to `ci.yml` (replacing the named Oracle step in `test`); green on PR #2's first run; required, with `swift test (macOS)`, in the `main` ruleset (strict status checks, linear history, PR required)*
- [x] 3.3 Prove the lane bites: on a throwaway branch make a write Xcode refuses, confirm the `oracle` job fails, and record the run URL in this change's design.md; delete the branch — *the prescribed write (`platformFilters` as a string) is refused by S4 before it reaches disk and is accepted by `xcodebuild -list` anyway (design Evidence, "What the oracle can and cannot see"); the throwaway branch `oracle-bites` (PR #3) used `objectVersion = 999` instead — unit tests green, `oracle` red on run 35723868593 (Xcode 26.6 on the runner); branch and PR deleted*

## 4. Release workflow

- [ ] 4.1 Add `release.yml` triggered by `v*.*.*` tags: `needs` `test` and `oracle`, checks tag against `Version.swift`, builds universal per design D2, asserts `lipo -archs` and the minimum OS load command, packages the archive and `.sha256`, publishes the release — *`.github/workflows/release.yml`; verified end to end by the rehearsal (4.2). One fix came out of the first rehearsal run (35726242503): Homebrew refuses `brew install --formula <file>` outside a tap, so the formula is now committed in the tap checkout, the checkout is tapped from its local clone and the formula is installed by its tap name before the push*
- [x] 4.2 Rehearse with a release tag; verify the archive name, checksum file contents and both architectures, then delete the rehearsal release and tag — *an `-rc1` tag can never pass the tag check, because D1's version grammar has no pre-release component and the release job needs `test` green on the same commit, so the rehearsal used a plain `v0.0.1` on an unpushed commit with `Version.swift` at `0.0.1-dev`. Run 35727447271: every step green — `lipo -archs: arm64 x86_64`, both slices `minos 13.0`, `--version` → `0.0.1`, release `v0.0.1` with `pbxedit-0.0.1-macos-universal.tar.gz` and `.sha256`, tap commit `0827010` with the new `url`/`sha256`; the assets were downloaded and re-verified locally (`shasum -c` OK, `lipo`, `otool`, `--version`). Release, tag and the tap commit (reverted as `b4a1973`) deleted afterwards; see design.md Evidence*
- [x] 4.3 Add a workflow test pushing a tag whose version disagrees with `Version.swift` in the rehearsal setting; verify the workflow fails before publishing — *tag `v0.0.1-rc1` on `main` (`Version.swift` = `0.1.0-dev`), run 35726212331: `test` and `oracle` green, then "Check the tag against Version.swift" failed with `Version.swift says '0.1.0-dev' but the tag is 'v0.0.1-rc1'`; every later step skipped, no release created; tag deleted*

## 5. Homebrew

- [x] 5.1 Write the formula with a `test do` block running `--version`; add the release-workflow step that commits the new `url` and `sha256` to the tap; verify `brew install` from the tap and `brew test` succeed against the rehearsal release — *`simplekube-ro/homebrew-tap` `Formula/pbxedit.rb`; on run 35727447271 the workflow tapped its local clone, `brew install simplekube-ro/tap/pbxedit` poured `0.0.1`, the installed binary printed `0.0.1`, `brew test` passed and the tap received commit `0827010` (reverted after the rehearsal)*

## 6. Documentation

- [ ] 6.1 Add Install, Pinning (design D5 snippet) and Supported platforms sections to `README.md`; add a CI step that runs the pinning snippet against the latest release with both a right and a wrong checksum; verify the step passes after the first real release — *owner: README is gated on the public name (1.1); the three sections are drafted in the report*
- [x] 6.2 Write the failing `CLITests.ReleasingDocumentTests` (the Release checklist scenario's four items as section headings), then `docs/RELEASING.md` with the version bump, the manual Xcode open-and-save check with a field for the Xcode version, the tag command, and the post-release Homebrew verification; verify the test passes and the document satisfies the scenario line by line

## 7. First releases

- [x] 7.1 Follow `docs/RELEASING.md` to cut `v0.1.0`; verify the release assets, `brew install`, and that the pinning snippet fetches and verifies it — *tag on `main` `029a8eb`; run 35736053201 green (test, oracle, build/assert/publish, tap install+test, tap push `fdc2a9a`); assets and `.sha256` verified through the README pinning snippet, right and wrong checksum; `brew install simplekube-ro/tap/pbxedit`, `brew test` and `brew audit --strict` pass on a Mac with current Homebrew after a one-time formula fix in the tap (`bb39d62`: `depends_on macos: :ventura` moved inside `on_macos`, which current Homebrew requires next to `depends_on :macos`; the runner's older Homebrew had accepted the flat form). `Version.swift` bumped to `1.0.0-dev` (RELEASING § 1) in the same follow-up*
- [ ] 7.2 After `lint-fix` has shipped, cut `v1.0.0` by the same procedure; verify as in 7.1 and record the Xcode version used for the manual check — *first manual check (Xcode 27.0, `main` `64b9fe7`) produced a diff: one pbxedit defect (issue #6, platform-filter spelling; fixed by change `platform-filter-canonical-form`) plus procedure flaws now corrected in § 2 (start from Xcode-saved fixtures under `Tests/Fixtures/xcode27/`, fully repairable `lint --fix` project, no renamed `.xcodeproj`). Blocked until the fix is merged and the check re-run clean*
