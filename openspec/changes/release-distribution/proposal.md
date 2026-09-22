# Proposal

## Why

A tool that guards a project file has to be the same tool on every machine and in CI. Building from source on each use is slow and unpinned; a project adopting pbxedit needs a versioned binary it can fetch, verify by checksum and pin. Releases also need a gate the unit tests cannot provide: that Xcode's own tooling still reads every file pbxedit writes.

## What Changes

- `pbxedit --version` reports the release version (a development build appends `-dev` and, when `PBXEDIT_BUILD_HASH` is set, the short commit hash).
- A tag-triggered release workflow builds a universal (arm64 + x86_64) macOS binary, packages it with a SHA-256 checksum, and publishes a GitHub Release.
- A Homebrew formula in a tap, updated by the release workflow.
- CI gains a required `oracle` job: the existing `CLITests.OracleTests` suite (33 post-operation scenarios plus the repaired workload substitute, each read by `xcodebuild -list`), run on its own with Xcode selected explicitly, and made to fail rather than skip when `xcodebuild` is missing (`ORACLE_REQUIRED`).
- A release checklist including the manual Xcode open-and-save check from `docs/design.md`.
- `README.md` install and pinning instructions; a `LICENSE` file.

## Capabilities

### New Capabilities
- `distribution`: how pbxedit is versioned, built, verified and delivered to users and CI.

### Modified Capabilities

None.

## Non-goals

- Linux or Windows binaries. The libraries avoid Darwin-only APIs where that is free, but nothing is promised or tested.
- Submitting to `homebrew-core`; a tap is enough for v1.
- A SwiftPM command plugin, a GitHub Action wrapper, or an installer script hosted elsewhere.
- Notarization. The binary is a command-line tool fetched by script or Homebrew, neither of which applies quarantine; revisit if users report Gatekeeper prompts.

## Impact

- New: `.github/workflows/release.yml`, an `oracle` job in `ci.yml`, `docs/RELEASING.md`, `LICENSE`, `README.md` sections, `Sources/pbxedit/Version.swift`, an `ORACLE_REQUIRED` mode in `Tests/CLITests/OracleTests.swift`.
- New repository: the Homebrew tap (`simplekube-ro/homebrew-tap`), and a token allowing the release workflow to push to it. Both need the repository owner.
- Two owner decisions block this change: the **licence** and the **public name** (`docs/design.md` § Open items — `pbxedit` collides with `ZehMatt/PBXEdit`).
- All nine preceding changes have shipped, so `v1.0.0` contains every v1 command; `v0.1.0` is a rehearsal of the procedure, not a feature cut.
