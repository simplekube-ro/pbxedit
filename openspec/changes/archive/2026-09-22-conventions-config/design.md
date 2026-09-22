# Design

## Context

`add-command` introduced `Decision(value, source)`, `Decided<Value>` and a `Conventions` value that planners query (`targets(for:kind:in:)`, `platformFilters(for:kind:target:in:)`, `phase(for:kind:)`); each answer is `flags ?? infer`, and the archived design says "`conventions-config` later adds `.config(rule)` between flag and inference without touching planners; the seam is that planners only ever call `Conventions`". `integrity-rules-lint` introduced baselines and findings that carry a path; `OperationRunner` runs the same `RuleSet.evaluate` before and after the write. This change adds one source and one filter. See proposal.md for motivation and `docs/design.md` § Conventions and § Config.

## Goals / Non-Goals

**Goals**

- Planners do not change for targets and platform filters. Configuration enters through `Conventions` only.
- A configuration error is impossible to miss and impossible to half-apply.

**Non-Goals**

- A schema that anticipates future commands. Keys are added when a command needs them.

## Decisions

### D1. Configuration is a layer inside `Conventions`

```
Conventions.targets(for path) =
    flags.targets ?? config.firstRule(matching: path, setting: \.targets) ?? infer(...)
```

The same shape serves `platformFilters`. `Conventions` gains `config: ConfigConventions?` beside `flags`; the two lookups consult it between the flag and inference. Because lookup short-circuits, a configured attribute never triggers inference for that attribute, so the ambiguity error cannot arise — which is the behaviour the Precedence requirement asks for, obtained structurally rather than by a special case. `Decision.Source` gains `.config(rule: Int, glob: String)`, printed `config, rule 2 "App/Mixed/**"`; the JSON `source` object gains `rule` and `glob`, `null` for the other kinds, as `siblings` and `directory` already are for the non-inferred kinds.

### D2. First match per attribute

*Alternative considered:* last match wins, as in `.gitignore`. Rejected: rules here assign values rather than toggling inclusion, and "the first rule that says anything about targets" is easier to predict and to report ("rule 2"). Per-attribute rather than per-rule matching lets a platform rule (`App/**`) and a target rule (`App/Mixed/**`) coexist without repeating each other.

### D3. Own glob matcher

A small matcher over path segments (`PathGlob`): `*` and `?` within a segment, `**` as a whole segment matching zero or more segments. `fnmatch(3)` does not implement `**`, and adding a dependency for forty lines is against policy. Character classes and brace expansion are not supported; using them, an empty segment (leading, trailing or doubled `/`) or `**` mixed into a segment is a validation error so nobody relies on them by accident.

### D4. Decode by walking the composed YAML node, strictly

Yams' `YAMLDecoder` gives typed decoding but silently ignores unknown keys and loses positions. The file is therefore composed to a `Yams.Node` (`Yams.compose`) and walked by hand: each mapping's keys are compared with the allowed set, throwing `unknown key 'target'; allowed keys: match, targets, platformFilters` with the key's line; each value is checked for its kind (scalar, list of scalars, mapping) and reported with its line when wrong; scalar text is taken verbatim, so a target named `On` or `1` is not reinterpreted as a boolean or number. Platform names are checked against `PlatformFilters.known` (rule S4's list), rule IDs against `RuleID`, exemptible rules against `M3, M6, D1, D2`, globs against D3. Every failure is a `ConfigError(file, line, message)` rendered `<file>:<line>: <message>`; the CLI reports it as a usage error, exit `2`, before anything is planned or written.

Project-dependent validation (target names) runs after the project loads and before any planner, in every command that loads a project; `lint` on a project that does not load reports S1 and skips it.

### D5. Exemption is a filter on findings

`Exemptions.apply(to:)` splits findings into kept and exempt by rule ID and path glob; `RuleSet.evaluate` gains an `exemptions` parameter applied after scope filtering, and `OperationRunner` gains `exemptions`, so the pre-write and post-write checks honour them with the same code. `lint` applies the same filter itself so it can count the exempt findings, before the baseline, and writes a baseline from the kept findings only.

### D6. An M3-exempt add skips the group steps

The add planner's second "ensure" question (is the reference a child of its directory's group) is skipped when the path is M3-exempt: a new reference is written `path = <full path>; name = <basename>; sourceTree = SOURCE_ROOT` with no group child and no group created, and an existing orphan stays one. This is the one place configuration reaches a planner; it cannot go through `Conventions` because the group question is deliberately not a convention (`docs/design.md` § Severity and repair: never inferred from siblings). The change is additive: `AddPlanner.plan(_:in:conventions:exemptions:minter:)` takes `exemptions: Exemptions? = nil`, so every change-5 call and test stands unchanged. The location decision's source is a new `Decision.Source.exemption(rule: .M3, glob:)`, printed `config, exempt M3 "Tools/**"`; in JSON `source.kind` is `exemption` with `glob` set and `rule` `null` (the rule is a finding ID, not a position — `kind` says which).

### D7. Configuration root defines relative paths

`project`, `lint.baseline` and rule globs are relative to the directory containing `.pbxedit.yml`. `ConfigFile.bind(sourceRoot:)` rejects a configuration whose directory is not the project's source root or an ancestor of it, and otherwise records the source root's path relative to that directory as a prefix; globs are matched against `prefix + path`, so a configuration above the source root writes its globs from its own directory (`Sub/App/**`).

## Risks / Trade-offs

- [A broad rule hides a real inference disagreement] → The output attributes the decision to the rule on every run, and `add --dry-run` shows it before anything is written.
- [Exemptions become a way to silence real damage] → Only four rules are exemptible; suppressed findings are counted on every `lint` run, never hidden.
- [Yams is a sizeable dependency for one file] → Accepted in `docs/design.md`; it is linked only into `PBXOps` (its `Config/` module) and the executable.
- [Target-name validation makes the config brittle across branches where a target is being added] → The error lists valid targets and names the rule; fixing it is one line. Silent acceptance would send files to no target.
- [The JSON shapes of `add` (`source.rule`, `source.glob`) and `lint` (`summary.exempt`) grow] → Additive, always-present keys with `null`/`0` defaults; the change-5 and change-3 tests that compare those objects exactly are extended by the new keys, not weakened.

## Evidence

The complete commented example of task 7.1 is `Tests/Fixtures/config/example.pbxedit.yml`, loaded strictly by `ConfigTests.testTheDocumentedExampleLoads`; `docs/design.md` § Config shows the same file. There is no `README.md` yet; the example moves there when the first change creates it.
