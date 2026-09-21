# Spec Delta

## Purpose

Make a given version of pbxedit obtainable, verifiable and pinnable on any supported Mac and in CI, and ensure no version is released whose output Xcode's own tooling cannot read.

## ADDED Requirements

### Requirement: The binary reports its version
`pbxedit --version` SHALL print the semantic version of the release it was built from and exit `0`. A binary built from an untagged commit SHALL print the next version with a `-dev` suffix and the short commit hash.

#### Scenario: Release build
- **WHEN** the binary from release `v1.2.0` runs `pbxedit --version`
- **THEN** it prints `1.2.0`

#### Scenario: Development build
- **WHEN** a binary built from a commit after `v1.2.0` runs `pbxedit --version`
- **THEN** the output starts with a version greater than `1.2.0`, contains `-dev`, and ends with the commit's short hash

### Requirement: Releases are built from tags
Pushing a tag of the form `vMAJOR.MINOR.PATCH` SHALL produce a GitHub Release of that name containing an archive of a universal binary for arm64 and x86_64, and a file with the archive's SHA-256 checksum. The release SHALL NOT be published unless the full test suite and the oracle lane pass on the tagged commit.

#### Scenario: Tag push
- **WHEN** `v1.2.0` is pushed and all checks pass
- **THEN** the release `v1.2.0` exists with `pbxedit-1.2.0-macos-universal.tar.gz` and `pbxedit-1.2.0-macos-universal.tar.gz.sha256`, and `lipo -archs` on the extracted binary prints both architectures

#### Scenario: Failing check
- **WHEN** a tag is pushed and the oracle lane fails
- **THEN** no release is published

#### Scenario: Tag and version disagree
- **WHEN** the tag is `v1.2.0` and the built binary would report another version
- **THEN** the workflow fails before publishing

### Requirement: Downloads are verifiable
The published checksum SHALL match the published archive, and the documented installation procedure for pinned use SHALL verify it before executing the binary.

#### Scenario: Pinned fetch
- **WHEN** the documented pinning snippet runs with version `1.2.0` and the expected checksum
- **THEN** it downloads the archive, verifies the checksum, and extracts `pbxedit`; with a wrong expected checksum it fails without extracting

### Requirement: Homebrew installation
The tap SHALL provide a formula that installs the released binary and whose test block runs `pbxedit --version`. Publishing a release SHALL update the formula's URL and checksum to that release.

#### Scenario: Install from the tap
- **WHEN** `brew install <tap>/pbxedit` runs after release `v1.2.0`
- **THEN** `pbxedit --version` prints `1.2.0`

### Requirement: Oracle lane
Continuous integration SHALL include a job, required for merging and for releasing, that applies every mutating command's test scenarios to fixture projects and runs `xcodebuild -list` on each result, failing if any result cannot be read.

#### Scenario: A change that writes something Xcode rejects
- **WHEN** a change makes `add` emit `platformFilters` in a form Xcode cannot parse
- **THEN** the oracle job fails on the post-add fixture and the pull request cannot merge

### Requirement: Supported platforms are stated and enforced
The package SHALL declare its minimum macOS version, the README SHALL state it, and the released binary SHALL run on that version.

#### Scenario: Declared minimum
- **WHEN** the released binary's load commands are inspected
- **THEN** its minimum OS version equals the one declared in `Package.swift` and stated in `README.md`

### Requirement: Release checklist
The repository SHALL contain a release procedure that includes, before tagging, the manual check that a fixture project modified by each mutating command can be opened and saved in the current Xcode with no resulting diff, and records the Xcode version used.

#### Scenario: Procedure present
- **WHEN** `docs/RELEASING.md` is read
- **THEN** it lists the version bump, the manual Xcode check with a place to record the Xcode version, the tag command, and the post-release verification of the Homebrew formula
