# pbxedit

A Swift command-line tool that manages **file membership** in an Xcode
`project.pbxproj`: `add`, `move`, `remove`, `query`, and `lint [--fix]`.
It edits the project file losslessly — untouched bytes are never rewritten —
and checks the result against a rule set before anything is written.

```sh
pbxedit add App/Views/Settings.swift            # infers target, phase and group from siblings
pbxedit move App/Old.swift App/Legacy/Old.swift  # after you moved the file on disk
pbxedit remove App/Legacy/Old.swift
pbxedit query App/Views/Settings.swift --json
pbxedit lint --fix --dry-run                     # repairs orphans and dangling entries
```

Every command takes `--project`, `--json` and, for mutations, `--dry-run`
(prints the plan and a unified diff). Conventions can be pinned in a
`.pbxedit.yml`; see `docs/design.md` § Config.

## Install

Homebrew (prebuilt universal binary, no Swift toolchain needed):

```sh
brew install simplekube-ro/tap/pbxedit
pbxedit --version
```

A release archive: every release on
<https://github.com/simplekube-ro/pbxedit/releases> ships
`pbxedit-<version>-macos-universal.tar.gz` and a `.sha256` file; see
Pinning below.

From source (Swift 6, macOS 13+):

```sh
swift run pbxedit --help
```

A development build reports `<next>-dev`, plus `+<hash>` when
`PBXEDIT_BUILD_HASH` (for example `$(git rev-parse --short=7 HEAD)`) is set
in its environment.

## Pinning

To pin an exact version in a project or in CI, by URL and checksum, with no
package manager:

```sh
V=1.0.0; SUM=<sha256 from the release's .sha256 file>
curl -fsSL -o pbxedit.tgz "https://github.com/simplekube-ro/pbxedit/releases/download/v$V/pbxedit-$V-macos-universal.tar.gz"
echo "$SUM  pbxedit.tgz" | shasum -a 256 -c - && mkdir -p .tools && tar -xzf pbxedit.tgz -C .tools
.tools/pbxedit --version   # prints 1.0.0
```

A wrong `SUM` makes `shasum` fail and nothing is extracted. Consumers pinned
this way are unaffected by any later release.

## Supported platforms

- macOS 13 (Ventura) or later — the minimum declared in `Package.swift` and
  asserted on every released binary's load commands.
- Apple silicon and Intel: one universal binary (`lipo -archs` lists
  `x86_64 arm64`).
- The binary is not notarized. `curl` and Homebrew set no quarantine
  attribute, so there is no Gatekeeper prompt; if a browser download shows
  one, please report it.
- No Linux or Windows builds.

## Development

```sh
swift build
swift test                                        # read the summary, not the exit code
swift test -c release --filter PerformanceTests   # the release-build performance checks
swift test --filter CLITests.OracleTests          # xcodebuild -list reads every post-operation fixture
```

The design is in `docs/design.md`; the work is organised as OpenSpec changes
under `openspec/`. Releases follow `docs/RELEASING.md`.

## Licence

MIT — see `LICENSE`. The test corpus under `Tests/Fixtures/corpus/` is
third-party material, each file MIT-licensed by its upstream project;
provenance and licence texts are recorded in `Tests/Fixtures/NOTICE`.
