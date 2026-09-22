# Spec Delta

## Purpose

Give every pbxedit command one shared understanding of an Xcode project file: which objects exist, how they refer to each other, where each file lives on disk and which targets build it — without disturbing any byte a command did not ask to change.

## ADDED Requirements

### Requirement: Exact-ID lookup
Objects SHALL be looked up by their complete ID. An ID that is a prefix, suffix or case variant of another SHALL NOT match it.

#### Scenario: One ID is a prefix of another
- **WHEN** the project contains a file reference `TVOSTEST0002` and a group `TVOSTEST00020`, and the object `TVOSTEST00020` is requested
- **THEN** the group is returned

#### Scenario: Unknown ID
- **WHEN** the object `TVOSTEST000` is requested and no object has exactly that ID
- **THEN** the lookup reports that no such object exists

### Requirement: IDs are opaque
Any string used as a key of the `objects` dictionary SHALL be a valid ID, whatever its length or alphabet.

#### Scenario: Synthetic IDs
- **WHEN** a project uses the IDs `SPLASH00000001` and `5L0WTSTSP000000000000SRC`
- **THEN** both objects load, are typed by their `isa`, and can be referenced by other objects

### Requirement: Unknown kinds pass through
An object whose `isa` the model does not know SHALL be preserved unchanged and SHALL be enumerable as an opaque object with its ID and `isa`.

#### Scenario: Newer project format
- **WHEN** a project with an unrecognized `objectVersion` and an object of kind `PBXSomethingNew` is loaded, one unrelated group child is added, and the project is serialized
- **THEN** the output differs from the input only by the added child line

### Requirement: Broken projects load
A project with dangling references, orphaned objects or duplicate array entries SHALL load, and the defects SHALL be observable through the model. Only a missing `objects` dictionary or a missing or unresolvable `rootObject` SHALL prevent loading, with an error naming the problem.

#### Scenario: Dangling file reference
- **WHEN** a build file's `fileRef` names an ID that does not exist
- **THEN** the project loads, and the build file reports its `fileRef` ID together with the fact that it does not resolve

#### Scenario: No root object
- **WHEN** `rootObject` names an ID that does not exist
- **THEN** loading fails with an error saying the root object cannot be found

### Requirement: Path resolution
Every group and file reference SHALL resolve to a path relative to the source root, computed from its `path`, its `sourceTree` and its chain of parent groups. A group with no `path` SHALL contribute nothing to the chain. References whose `sourceTree` is neither `<group>`, `SOURCE_ROOT` nor `<absolute>` SHALL be reported as not project-relative and excluded from path lookup.

#### Scenario: Group-relative reference
- **WHEN** the file reference `path = Foo.swift; sourceTree = "<group>"` sits in group `Views` (`path = Views`) inside group `App` (`path = App`) under the main group
- **THEN** it resolves to `App/Views/Foo.swift`

#### Scenario: Source-root reference in a pathless group
- **WHEN** the file reference `path = AppTests/Views/FooTests.swift; sourceTree = SOURCE_ROOT` sits in a group that has a `name` and no `path`
- **THEN** it resolves to `AppTests/Views/FooTests.swift`

#### Scenario: Reference with no parent group
- **WHEN** the file reference `path = Foo.swift; sourceTree = "<group>"` is a child of no group
- **THEN** it resolves to `Foo.swift` relative to the source root, and its list of parent groups is empty

#### Scenario: SDK reference
- **WHEN** a file reference has `sourceTree = SDKROOT`
- **THEN** it is reported as not project-relative and no path lookup returns it

### Requirement: Lookup by resolved path
File references SHALL be found by resolved path. A basename alone SHALL NOT identify a file.

#### Scenario: Same basename in two targets
- **WHEN** the project references `AppTests/Foo/Bar.swift` and the path `AppSlowTests/Foo/Bar.swift` is looked up
- **THEN** the lookup reports no match

#### Scenario: Equivalent spellings
- **WHEN** `./App/Views/../Views/Foo.swift` is looked up and the project references `App/Views/Foo.swift`
- **THEN** that reference is returned

### Requirement: Membership indexes
For any file reference the model SHALL report every build file that refers to it, the build phase each build file is listed in (none, one or several), the target owning each phase, each build file's `platformFilters`, and every group listing the reference as a child (none, one or several).

#### Scenario: Build file listed in no phase
- **WHEN** a build file exists for `Foo.swift` and no phase lists it
- **THEN** the membership report for `Foo.swift` shows that build file with no phase and no target

#### Scenario: Shared source
- **WHEN** `Shared.swift` has two build files, in the Sources phases of targets `App` and `AppExtension`
- **THEN** the membership report lists both targets with their respective build file IDs

### Requirement: Synchronized root groups are visible
The model SHALL expose each `PBXFileSystemSynchronizedRootGroup` with its resolved folder path and the targets it belongs to, and SHALL answer whether a given path lies inside one.

#### Scenario: Path inside a synchronized folder
- **WHEN** the project has a synchronized root group at `App/Generated` and the path `App/Generated/Models/User.swift` is tested
- **THEN** the answer is that the path is covered, naming that group

### Requirement: Minted IDs are well-formed and unique
A newly minted ID SHALL be 24 uppercase hexadecimal characters and SHALL differ from every ID in the project, including IDs minted earlier in the same session. The source of randomness SHALL be replaceable so tests can fix the sequence.

#### Scenario: Collision
- **WHEN** the ID source yields an ID already present in the project, then a fresh one
- **THEN** the first is discarded and the fresh one is returned

### Requirement: Primitive mutations place content where Xcode does
Creating an object SHALL place it inside the `/* Begin <isa> section */ … /* End <isa> section */` block for its kind, in ID order when the block is already in ID order and last otherwise, creating the block in alphabetical position among blocks when the kind has none. When the file has no section markers, the object SHALL be appended to `objects`.

#### Scenario: New build file in a sorted section
- **WHEN** a build file with ID `5A…` is created and the `PBXBuildFile` section is sorted by ID
- **THEN** its line is inserted between the neighbouring IDs and no other line changes

#### Scenario: First object of a kind
- **WHEN** a `PBXVariantGroup` is created in a project that has none
- **THEN** a `PBXVariantGroup` section with Begin and End markers is created after the alphabetically preceding section

#### Scenario: Last object of a kind
- **WHEN** the only `PBXVariantGroup` in a project is deleted
- **THEN** the `PBXVariantGroup` section's Begin and End markers are removed with it and the neighbouring sections are unchanged

### Requirement: Annotation comments match Xcode
References written by the model SHALL carry the comments Xcode writes: `/* <name> */` after a reference to a file or group, `/* <name> in <phase name> */` after a reference to a build file, and the same comment on the object's own definition line. Changing a file reference's name SHALL update every such comment that refers to it or to its build files.

#### Scenario: Rename
- **WHEN** the file reference `Old.swift`, which has one build file in a Sources phase, is renamed to `New.swift`
- **THEN** the reference's definition, its entry in its parent group, the build file's definition and the build file's entry in the phase all carry `New.swift`, and no comment anywhere still says `Old.swift`

### Requirement: Mutations change only what they name
Each primitive mutation — create object, delete object, add child, remove child, add phase entry, remove phase entry, set attribute — SHALL change only the bytes belonging to that object, entry or attribute.

#### Scenario: Add a child to a group
- **WHEN** a child is added to a group with forty children
- **THEN** the serialized project differs from the input by one added line inside that group's `children`
