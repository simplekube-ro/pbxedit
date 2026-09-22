# README section drafts (task 6.1; gated on the public name, task 1.1)

Replace `<org>/<name>`, `simplekube-ro/tap` and `pbxedit` once decided.

## Install

Homebrew (prebuilt universal binary, no Swift toolchain needed):

```sh
brew install simplekube-ro/tap/pbxedit
pbxedit --version
```

A release archive: every release on
<https://github.com/<org>/<name>/releases> ships
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
curl -fsSL -o pbxedit.tgz "https://github.com/<org>/<name>/releases/download/v$V/pbxedit-$V-macos-universal.tar.gz"
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
