# Design

## Context

CI (`.github/workflows/ci.yml`, one `test` job on `macos-latest`) has run `swift build`, `swift test` and the release-mode `PerformanceTests` since `lossless-syntax-tree`. The mutating commands' oracle tests grew into one suite, `CLITests.OracleTests` (`Tests/CLITests/OracleTests.swift`): 33 scenarios over the `add`, `remove`, `move` and `repair` fixtures plus the repaired workload substitute, each run through the built binary and then read by `xcodebuild -list -json -project`; `ci.yml` runs the suite as a named step of `test`, and the suite skips with `XCTSkip` where `xcodebuild` is absent or no developer directory is selected. Nothing is versioned or published: the root command has no `--version`. See proposal.md for motivation and `docs/design.md` §§ Testing, Distribution.

## Goals / Non-Goals

**Goals**

- A consumer can pin an exact version by URL and checksum with ten lines of shell and no package manager.
- No release without Xcode having read the tool's output.

**Non-Goals**

- Reproducible builds bit-for-bit.
- Automated changelog generation.

## Decisions

### D1. Version from a checked-in source file

`Sources/pbxedit/Version.swift` holds `enum Version { static let base = "0.1.0-dev" … }`, the next version to be tagged with a `-dev` suffix. The root command passes `Version.current` to `CommandConfiguration(version:)`, so `swift-argument-parser` provides `--version` (exit `0`, one line on standard output). The release workflow rewrites the `base` line from the tag before building and fails if the working tree's base version (without `-dev`) does not equal the tag — that is the "tag and version disagree" guard.

A development build (one whose `base` ends in `-dev`) appends `+<hash>` when the environment variable `PBXEDIT_BUILD_HASH` holds a lowercase hex string of at least seven characters, using its first seven (`git rev-parse --short=7 HEAD`); any other value is ignored and the suffix is just `-dev`. The variable is read **at run time**, by development builds only: a release build's version is the literal in the file and cannot be changed by the environment. CI and the `swift run` wrapper set the variable from `git`.

*Alternatives considered:* a SwiftPM build-tool plugin invoking `git describe` — rejected, plugins run sandboxed and the tool must build from a source tarball with no `.git`; baking the hash in at build time through the environment — there is no SwiftPM mechanism for it (`-D` flags carry no value and the manifest cannot generate sources), so "build time" would have meant the plugin. Reading the variable at run time in development builds only keeps the promise that matters, a fixed version in released binaries, and costs one `getenv`.

### D2. Universal binary in one build, asserted with `lipo`

`swift build -c release --arch arm64 --arch x86_64` produces a universal product directly on current toolchains; the workflow uses it and asserts `lipo -archs` lists both, so a toolchain change that silently drops one fails the release. The product directory is whatever `swift build … --show-bin-path` prints (`.build/out/Products/Release` under Swift 6.4's build system, `.build/apple/Products/Release` under older ones); the workflow never hardcodes it. See Evidence.

### D3. Oracle lane: the existing suite under one required check

`CLITests.OracleTests` already exists (Context). This change gives it an `ORACLE_REQUIRED` mode: the gate that today throws `XCTSkip` when `xcodebuild` is missing or no developer directory is selected instead records a failure when the variable is set to a non-empty value, so a runner image without Xcode turns the job red rather than green. The decision is a pure function of two facts (is `xcodebuild` usable, is the variable set), `OracleTests.gate(xcodebuildAvailable:required:)`, unit-tested on every machine; the skip-or-fail behaviour itself can only be observed on a machine without Xcode (the manual check is in Evidence). A separate CI job `oracle` runs only that suite with Xcode selected explicitly (`sudo xcode-select -s`, version printed) and `ORACLE_REQUIRED=1`, and is marked required in branch protection. The release workflow `needs:` both `test` and `oracle`.

### D4. Tap formula installs the prebuilt binary

The formula downloads the release archive and installs the binary; no build from source, so users do not need a matching Swift toolchain. The release workflow commits the new `url` and `sha256` to the tap (the version is the one in the `url`; Homebrew derives it, and `brew audit` flags an explicit `version` line as redundant), using a fine-scoped token stored as a secret, after installing the formula from the checkout and running its test block against the just-published release.

### D5. Pinning snippet in the README

```sh
V=1.2.0; SUM=<sha256>
curl -fsSL -o pbxedit.tgz "https://github.com/simplekube-ro/pbxedit/releases/download/v$V/pbxedit-$V-macos-universal.tar.gz"
echo "$SUM  pbxedit.tgz" | shasum -a 256 -c - && tar -xzf pbxedit.tgz -C .tools
```

Tested in CI against the most recent release so the documented procedure cannot rot.

### D6. Minimum macOS 13

Already declared in `Package.swift` since `lossless-syntax-tree`. It covers every macOS that runs an Xcode capable of opening the project formats in the corpus. The workflow checks the built binary's `LC_BUILD_VERSION` against it: every slice's `minos` line must read `13.0` (Evidence shows both do).

## Risks / Trade-offs

- [The public name changes after release artifacts exist] → Blocked on the owner's decision (task 1.1) precisely so archive names, the formula name and README URLs are written once.
- [GitHub's hosted runner Xcode lags the newest project format] → The oracle job pins `xcode-select` to the newest Xcode on the image and prints its version; fixtures generated by a newer Xcode than the runner has are excluded by an explicit list with a comment, not skipped silently.
- [Unsigned binary triggers Gatekeeper for browser downloads] → Documented; `curl` and Homebrew do not set the quarantine attribute. Notarization is a follow-up if reported.
- [Tap token scope] → Fine-grained token limited to contents write on the tap repository only.
- [`xcodebuild -list` validates less than the name "oracle" suggests] → Measured on Xcode 27.0 (see Evidence, "What the oracle can and cannot see"): `-list` refuses a project only for top-level damage — an `objectVersion` it does not know, a dangling `rootObject` or `mainGroup` — and accepts every object-level corruption tried (an unknown `isa`, a dangling `fileRef`, `platformFilters`, `children` or `buildPhases` written as strings). `-showBuildSettings` and `-resolvePackageDependencies` are no stricter, and `build -dry-run` no longer exists. Object-level correctness therefore rests on the rule set (S1–S5, M1–M6, which already refuse each of those writes before they reach disk) and on the manual open-and-save check in `docs/RELEASING.md` § 2; the lane's own contribution is "Xcode still opens what pbxedit wrote", proven to bite on exactly that (task 3.3). A stronger oracle — a real `xcodebuild build` of a small compilable fixture — is a candidate follow-up change, not part of v1.

## Migration Plan

1. Owner decides name and licence; creates the tap repository and the token secret.
2. Merge this change; verify `oracle` is a required check.
3. Follow `docs/RELEASING.md` to cut `v0.1.0` as a rehearsal of the procedure, then `v1.0.0` (every v1 command has shipped; `Version.swift` starts at `0.1.0-dev` and the bump to `1.0.0-dev` is the first step of the second release).

Rollback: delete the release and tag, revert the tap commit. Consumers pinned by checksum are unaffected by a withdrawn later release.

## Open Questions

- Whether to notarize. Deferrable: affects neither archive layout nor install procedure.

## Evidence

Recorded on the `release-distribution` branch with tasks 2.1, 2.2, 3.1 and 6.2 applied (Xcode 27.0, 27A266a; Apple Swift 6.4; macOS 26.6). Tasks 1.x, 3.2, 3.3, 4.x, 5.1, 6.1 and 7.x remain with the owner (see tasks.md).

### `--version` (tasks 2.1, 2.2; D1)

```
$ .build/debug/pbxedit --version
0.1.0-dev
$ echo $?
0
$ .build/debug/pbxedit --help | grep -- --version
  --version               Show the version.
```

`CLITests.VersionTests` (4 tests) pins: exit `0`, exactly one line on standard output and nothing on standard error, the shape `^\d+\.\d+\.\d+(-dev(\+[0-9a-f]{7})?)?$`; `PBXEDIT_BUILD_HASH=0123abcdef0123abcdef0123abcdef0123abcdef` → `0.1.0-dev+0123abc`, `fedcba9` → `0.1.0-dev+fedcba9`; empty, `HEAD`, upper-case hex, six characters, a trailing newline and `v0.1.0` are ignored. The `pbxedit()` test helper gained an `environment:` parameter for this.

### Universal build (D2, D6)

```
$ swift build -c release --arch arm64 --arch x86_64 --product pbxedit
Build complete! (17,71 sec)
$ swift build -c release --arch arm64 --arch x86_64 --product pbxedit --show-bin-path
/Users/…/pbxedit/.build/out/Products/Release
$ lipo -archs .build/out/Products/Release/pbxedit
x86_64 arm64
$ otool -l .build/out/Products/Release/pbxedit | grep -A4 LC_BUILD_VERSION
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform 1
    minos 13.0
      sdk 13.0
--
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform 1
    minos 13.0
      sdk 13.0
$ file .build/out/Products/Release/pbxedit
…: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64]
```

Two `LC_BUILD_VERSION` commands, one per slice, both `platform 1` (macOS) and `minos 13.0` = `Package.swift`'s `.macOS(.v13)`. The binary is 9.8 MB. The workflow's assertion is therefore: `lipo -archs` output, sorted, equals `arm64 x86_64`, and every `minos` line under `LC_BUILD_VERSION` reads `13.0`.

### Oracle gate (task 3.1; D3)

`CLITests.OracleGateTests` (4 tests, run on every machine) pins `OracleTests.gate(xcodebuildAvailable:required:)`: available → `.run` whatever the variable says; unavailable and `ORACLE_REQUIRED` unset or empty → `.skip`; unavailable and any non-empty value (`1`, `true`, `0`, `yes`) → `.fail`. With Xcode present the oracle suite itself ran green here (2 tests, 33 scenarios plus the repaired substitute, 39.7 s).

The skip-versus-fail behaviour needs a machine without Xcode and could not be observed in this session (environment variables cannot be set here). Manual check, on a Mac with only the Command Line Tools selected (`sudo xcode-select -s /Library/Developer/CommandLineTools`):

```
$ swift test --filter CLITests.OracleTests                  # expect: 2 tests skipped, suite passed
$ ORACLE_REQUIRED=1 swift test --filter CLITests.OracleTests   # expect: 2 failures, each
    "xcodebuild is not available and ORACLE_REQUIRED is set; the oracle lane must run on macOS with Xcode installed"
```

The `oracle` job in `ci.yml` sets `ORACLE_REQUIRED: "1"` (task 3.2). First run on the hosted runner, PR #2 (`https://github.com/simplekube-ro/pbxedit/pull/2`): `oracle (xcodebuild -list on post-operation fixtures)` and `swift test (macOS)` both green; both are required checks in the `main` ruleset (strict, linear history).

### What the oracle can and cannot see (task 3.3)

Probed by hand on `Tests/Fixtures/move/app.pbxproj` with Xcode 27.0 (27A266a), one corruption at a time, `xcodebuild -list -json -project`:

| Corruption | `-list` | pbxedit's rule set |
|---|---|---|
| `platformFilters = "[\"ios\"]"` (string, the write task 3.3 proposed) | accepts, exit 0 | S4 refuses before the write |
| unknown `isa` on a build file or file reference | accepts | M rules refuse |
| dangling `fileRef` | accepts | S2 refuses |
| `children` / `buildPhases` / `files` written as a string | accepts | S-rules refuse |
| `objectVersion = 999` | **refuses**, exit 74, "written by a different version of Xcode" | accepted (not a rule) |
| dangling `rootObject` or `mainGroup` | **refuses**, exit 74 | S2 refuses |

`-showBuildSettings` and `-resolvePackageDependencies` behaved exactly like `-list`; `xcodebuild build -dry-run` is "no longer supported". So the only write pbxedit can make that its own checks accept and Xcode refuses is editing a project whose `objectVersion` Xcode does not know, and that is what the lane was shown to catch: the throwaway branch `oracle-bites` (PR #3, `https://github.com/simplekube-ro/pbxedit/pull/3`) sets `objectVersion = 999` on the move fixture; locally the eight unit tests over that fixture stay green while `CLITests.OracleTests` fails on every scenario with the message above. On the hosted runner (`macos-latest`, newest image Xcode selected: **Xcode 26.6, build 17F113** — the runner lags the local Xcode 27.0, as the Risks foresaw) the `oracle` job went red as required: `https://github.com/simplekube-ro/pbxedit/actions/runs/35723868593/job/106732758212` — `Executed 2 tests, with 2 failures`, first failure `move: within a target: xcodebuild -list failed: … xcodebuild: error: Unable to read project 'App.xcodeproj'` (exit 74); `OracleGateTests` 4/4 passed. The `test` job failed too, on the same suite. Branch and PR deleted afterwards.

### Release checklist (task 6.2)

`docs/RELEASING.md` has the four scenario items as sections 1–4 (`Bump the version`, `Manual Xcode open-and-save check` with the `Xcode version used:` field, `Tag`, `Verify the Homebrew formula`), pinned by `CLITests.ReleasingDocumentTests` (3 tests), which also checks that the manual check exercises `add`, `move`, `remove` and `lint --fix` and ends in `git diff --exit-code`.

### Test summary

`swift build`: Build complete. `swift test`: 111 syntax + 64 model + 206 ops + 99 CLI tests, 0 failures, none skipped (CLI was 88; +4 `VersionTests`, +4 `OracleGateTests`, +3 `ReleasingDocumentTests`). `swift test -c release --filter PerformanceTests`: green. `openspec validate release-distribution --strict`: valid.
