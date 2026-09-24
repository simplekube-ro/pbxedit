# Releasing pbxedit

The procedure for cutting a release. Every step before the tag is manual;
everything after it is `.github/workflows/release.yml`. Do the steps in
order; do not tag until step 2 is recorded.

Names used throughout: the public name `pbxedit`, the repository
`simplekube-ro/pbxedit` and the tap `simplekube-ro/homebrew-tap` (installed
as `simplekube-ro/tap/pbxedit`). The release workflow and the formula use
the same names.

## 0. Preconditions

- `main` is green: the `test` and `oracle` checks passed on the commit you
  will tag (`oracle` is a required check; it runs `CLITests.OracleTests`
  with `ORACLE_REQUIRED=1`, so it cannot pass without Xcode).
- Locally, on that commit: `swift build`, `swift test`, and
  `swift test -c release --filter PerformanceTests` — read the summaries.
- The repository secret `TAP_TOKEN` exists (fine-grained, contents write on
  the tap repository only).

## 1. Bump the version

`Sources/pbxedit/Version.swift` holds the next version with a `-dev` suffix:

```swift
static let base = "0.1.0-dev"
```

1. Set it to the version you are releasing, keeping the suffix
   (`"1.0.0-dev"` for `v1.0.0`). The release workflow strips the suffix
   itself; it refuses to run when the tag and this line disagree.
2. Commit it (`chore: bump version to 1.0.0`) and merge to `main` through
   the usual pull request, so the tagged commit has been through CI.
3. Check the development build agrees: `swift run pbxedit --version` prints
   `1.0.0-dev` (with `PBXEDIT_BUILD_HASH=$(git rev-parse --short=7 HEAD)`
   in the environment it prints `1.0.0-dev+<hash>`).

## 2. Manual Xcode open-and-save check

`docs/design.md` § Testing: open a post-operation project in Xcode, save,
expect no diff. `xcodebuild -list` (the oracle lane) proves Xcode can *read*
what pbxedit writes; only this check proves Xcode leaves it *alone*. It
covers the one gap the automated tests record (a rename in a name-only group
has no Xcode-captured fixture; see the archived `move-command` design).

Run it once per release, on the commit to be tagged, with the newest Xcode
you have. The starting projects must be files Xcode itself last saved, so
that the only bytes Xcode could want to change are the ones pbxedit wrote;
and the `lint --fix` project must carry only damage `--fix` repairs, since
Xcode silently deletes whatever damage is left (dangling children, unphased
build files, unreachable references) and that would show as a diff:

```sh
xcodebuild -version                       # record below
swift build && P="$PWD/.build/debug/pbxedit"
B=Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj
W=$(mktemp -d) && mkdir -p "$W/ops/App.xcodeproj" "$W/repair/App.xcodeproj" "$W/sides/ours/App.xcodeproj" "$W/sides/theirs/App.xcodeproj"
cp "$B" "$W/ops/App.xcodeproj/project.pbxproj"
cp "$B" "$W/sides/base.pbxproj" && cp "$B" "$W/sides/ours/App.xcodeproj/project.pbxproj" && cp "$B" "$W/sides/theirs/App.xcodeproj/project.pbxproj"
cp Tests/Fixtures/xcode27/repair-fixable.pbxproj "$W/repair/App.xcodeproj/project.pbxproj"
cd "$W" && echo sides/ > .gitignore && git init -q && git add -A && git commit -qm base
mkdir -p ops/App/Features ops/App/Views sides/ours/App/Views sides/theirs/App/Features
touch ops/App/Views/Bar.swift ops/App/Features/Foo.swift sides/ours/App/Views/Bar.swift sides/theirs/App/Features/Foo.swift
cd sides/ours
"$P" add App/Views/Bar.swift --project App.xcodeproj                          # pbxedit add, on one branch
cd ../theirs
"$P" move App/Views/Foo.swift App/Features/Foo.swift --project App.xcodeproj  # pbxedit move, on the other
cd ../../ops
"$P" merge ../sides/base.pbxproj ../sides/ours/App.xcodeproj/project.pbxproj \
  ../sides/theirs/App.xcodeproj/project.pbxproj --project App.xcodeproj       # pbxedit merge, into ops/
"$P" remove App/Services/Rate.swift --project App.xcodeproj                   # pbxedit remove
cd ../repair
"$P" lint --fix --project App.xcodeproj                                       # pbxedit lint --fix
cd .. && git add -A && git commit -qm "pbxedit add, move, merge, remove, lint --fix"
open ops/App.xcodeproj repair/App.xcodeproj
```

(`Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj` is the
`move` fixture as Xcode 27 saved it — every platform-filter spelling, a
synchronized folder, five targets; `repair-fixable.pbxproj` is the same file
with one group child removed, an M3 orphan `lint --fix` restores byte for
byte. Both projects are named `App.xcodeproj`, as the file's own comments
say; a different name makes Xcode rewrite those comments. `add` and `move`
run on two copies outside the repository, as two branches would, and
`merge` combines them into `ops/` — the rename replayed as one unit, every
check passed — before `remove` runs on the merge. Each command prints
`project.pbxproj: modified`; `merge` exits `0`.)

In each Xcode window: wait for indexing, touch the project (rename a file
in the navigator and rename it back, or change and revert a build setting)
so Xcode rewrites `project.pbxproj`, then **File → Save** and quit. Then:

```sh
git diff --exit-code -- '*.pbxproj'
```

A clean exit is the check passing. Any diff is a release blocker: file it
against the command whose objects Xcode rewrote, with the diff.

Record the result here, in the release commit or the pull request that
follows it, and in TODO.md § 10 for `v1.0.0`:

```
Xcode version used: ______________________ (xcodebuild -version, both lines)
Commit checked:     ______________________
Result:             no diff / diff filed as #____
```

Recorded checks:

| Release | Xcode version used | Commit checked | Result |
|---|---|---|---|
| `v1.0.0` (first attempt) | Xcode 27.0, Build version 27A266a | `64b9fe7` | diff — filed as #6 (platform-filter spelling), fixed by `platform-filter-canonical-form`; the rest was the procedure, rewritten above |
| `v1.0.0` | Xcode 27.0, Build version 27A266a | `e418e90` | no diff |
| `v1.1.0` | Xcode 27.0, Build version 27A266a | `ae99bf9` (`347abad` on `main` after the rebase merge, identical tree) | no diff — the first run covering `merge` |
| `v1.1.1` | Xcode 27.0, Build version 27A266a | `bf77b60` | no diff |
| `v1.1.2` | Xcode 27.0, Build version 27A266a | `1179d34` | no diff |
| `v1.4.0` | — | `392244d` | **not run** — skipped by the release owner's decision (2026-09-24); the oracle lane (`xcodebuild -list`, `merge` of the `reordered-array` fixture decided `theirs` among them) passed on the merged commit, so Xcode can read the result, but nothing was measured about Xcode leaving the written bytes alone |
| `v1.3.0` | — | `d1353c5` | **not run** — skipped by the release owner's decision (2026-09-24); the oracle lane (`xcodebuild -list`, `merge` of the `settings-conflict` fixture among them) passed on the tagged commit, so Xcode can read the result, but nothing was measured about Xcode leaving the written bytes alone |
| `v1.2.0` | — | `5bd8f05` | **not run** — skipped by the release owner's decision (2026-09-24); the oracle lane (`xcodebuild -list`) passed on the tagged commit, so Xcode can read the result, but nothing was measured about Xcode leaving the written bytes alone |

## 3. Tag

The tag is the release; the workflow builds, checks and publishes from it.

```sh
git checkout main && git pull --ff-only
git tag -a v1.0.0 -m "pbxedit 1.0.0"
git push origin v1.0.0
```

`release.yml` then, in order: runs `test` and `oracle` again on the tagged
commit; fails if the tag is not `v` + the `base` line of `Version.swift`
without `-dev`; rewrites that line, builds
`swift build -c release --arch arm64 --arch x86_64`, asserts `lipo -archs`
lists `x86_64 arm64` and every slice's `LC_BUILD_VERSION` has `minos 13.0`;
packages `pbxedit-1.0.0-macos-universal.tar.gz` and its `.sha256`; creates
the GitHub Release with both files and the tag's notes; and commits the new
`url`, `sha256` and `version` to the tap formula.

If any step fails, nothing is published: fix on `main`, delete the tag
(`git push origin :refs/tags/v1.0.0` and `git tag -d v1.0.0`), and start
again at step 1. Never move a tag that a release was published from.

## 4. Verify the Homebrew formula

On a machine (or a fresh shell) that has never installed pbxedit:

```sh
brew update
brew install simplekube-ro/tap/pbxedit
pbxedit --version                          # prints 1.0.0, exit 0
brew test pbxedit                          # runs the formula's test block
```

And the pinning procedure from the README, with the checksum from the
release's `.sha256` file:

```sh
V=1.0.0; SUM=<sha256 from the release>
curl -fsSL -o pbxedit.tgz "https://github.com/simplekube-ro/pbxedit/releases/download/v$V/pbxedit-$V-macos-universal.tar.gz"
echo "$SUM  pbxedit.tgz" | shasum -a 256 -c - && mkdir -p .tools && tar -xzf pbxedit.tgz -C .tools
.tools/pbxedit --version                   # prints 1.0.0
```

Try it once more with a wrong `SUM`: `shasum` must fail and nothing may be
extracted.

## 5. Afterwards

- Bump `Version.swift` to the next `-dev` version (`"1.0.1-dev"` or
  `"1.1.0-dev"`) in a follow-up commit, so development builds report a
  version greater than the release.
- Tick the release box in TODO.md § 10 with the evidence: the release URL,
  the tap commit, and the Xcode version from step 2.

## Rollback

Delete the GitHub Release and the tag, and revert the tap commit. Consumers
pinned by URL and checksum are unaffected by a withdrawn later release;
Homebrew users get the previous version on `brew upgrade` once the tap is
reverted.
