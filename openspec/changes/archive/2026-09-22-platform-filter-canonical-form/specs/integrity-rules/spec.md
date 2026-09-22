# Spec Delta

## MODIFIED Requirements

### Requirement: Structural rules
The rule set SHALL report as errors: a file that does not parse, does not round-trip, or does not load as a project because it has no `objects` dictionary or no resolvable `rootObject` (S1); a reference to an ID that does not exist, in `fileRef`, `productRef`, `children`, `files`, `buildPhases`, `targets`, `mainGroup`, `productRefGroup`, `productReference`, `dependencies`, `target`, `targetProxy`, `containerPortal`, `buildConfigurationList`, `buildConfigurations`, `baseConfigurationReference`, `baseConfigurationReferenceAnchor`, `buildRules`, `currentVersion`, `package`, `packageProductDependencies`, `packageReferences`, `fileSystemSynchronizedGroups`, `exceptions`, `remoteRef`, `ProductGroup`, `ProjectRef`, `buildPhase` or `TestTargetID` (S2); an object ID defined twice, or an ID listed twice in one `children` or `files` array (S3); a `platformFilters` value that is not a property-list array of known platform names, or a `platformFilter` value that is not the string `ios` or `maccatalyst` (S4; `platform-filters`: Rule S4 checks both keys). It SHALL report as a warning a string whose quoting differs from the canonical form (S5).

#### Scenario: S1 on unparseable input
- **WHEN** the project file has an unterminated comment
- **THEN** exactly one finding is reported, rule `S1`, with the parser's line and column in its message, and no other rule is evaluated

#### Scenario: S1 on a file that is not a project
- **WHEN** the project file parses but its `rootObject` names an ID that is not in `objects`
- **THEN** exactly one finding is reported, rule `S1`, saying the root object cannot be found, and no other rule is evaluated

#### Scenario: S2 on a dangling child
- **WHEN** a group's `children` lists `DEAD0001` and no such object exists
- **THEN** an `S2` error is reported on the group, naming `DEAD0001` and the key `children`

#### Scenario: S3 on a repeated child
- **WHEN** a group's `children` lists `AB12` twice
- **THEN** an `S3` error is reported on the group, naming `AB12`

#### Scenario: S4 on JSON-style filters
- **WHEN** a build file has `platformFilters = ["ios"];` or `platformFilters = (iphone, );`
- **THEN** the first is reported as `S1` because it does not parse, and the second as an `S4` error naming `iphone` and listing the known platform names

#### Scenario: S4 on the singular key
- **WHEN** a build file has `platformFilter = tvos;` and another has `platformFilter = (ios, );`
- **THEN** the first is reported as an `S4` error naming `tvos` and listing `ios, maccatalyst`, the second as an `S4` error saying the value is not a string, while `platformFilter = ios;` and `platformFilter = maccatalyst;` are not reported

#### Scenario: S5 on a bare hyphen
- **WHEN** a file reference has `path = My-File.swift;` unquoted
- **THEN** an `S5` warning is reported on that reference
