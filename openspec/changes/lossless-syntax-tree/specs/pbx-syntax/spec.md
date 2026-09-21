# Spec Delta

## Purpose

Read old-style property-list text into a tree that remembers every byte, allow surgical edits to that tree, and write it back so that only the edited parts differ from the input.

## ADDED Requirements

### Requirement: Byte-exact round trip
Serializing the tree parsed from any input that parses SHALL reproduce the input byte for byte (rule S1).

#### Scenario: Real project file
- **WHEN** a `project.pbxproj` written by Xcode, including its `// !$*UTF8*$!` header and section comments, is parsed and serialized without edits
- **THEN** the output is identical to the input

#### Scenario: Mixed formatting
- **WHEN** the input mixes indentation depths between blocks, uses CRLF on some lines, and has no trailing newline
- **THEN** the output is identical to the input

### Requirement: Grammar coverage
The parser SHALL accept dictionaries, arrays, quoted strings with escape sequences, bare strings, data literals, block comments and line comments, wherever the old-style property-list grammar allows them. A bare string SHALL consist only of ASCII letters, digits and the characters `_ $ / : . -`.

#### Scenario: Escapes in a quoted string
- **WHEN** the input contains `name = "a \"quoted\" \U00e9\n";`
- **THEN** it parses, the decoded value is `a "quoted" é` followed by a newline, and the raw text is preserved for serialization

#### Scenario: Single-line dictionary
- **WHEN** the input contains `A1 /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = B2 /* Foo.swift */; };`
- **THEN** it parses to a dictionary entry whose key is `A1`, whose value has the keys `isa` and `fileRef` in that order, and whose comments are attached as trivia

#### Scenario: Array with trailing comma
- **WHEN** the input contains `children = (\n\tA1 /* x */,\n\tB2 /* y */,\n);`
- **THEN** it parses to an array of two elements in that order

### Requirement: Located errors, never a crash
Input that does not parse SHALL produce an error carrying a 1-based line and column and a description of what was expected. No input SHALL cause a crash, a hang, or unbounded memory growth.

#### Scenario: Character not allowed in a bare string
- **WHEN** line 12 of the input is `path = Foo+Bar.swift;`
- **THEN** parsing fails with an error at line 12, at the column of `+`, naming the unexpected character

#### Scenario: Unterminated comment
- **WHEN** the input ends inside `/* Begin PBXGroup`
- **THEN** parsing fails with an error located at the comment's opening

#### Scenario: Not an old-style property list
- **WHEN** the input begins with `<?xml` or with `bplist`
- **THEN** parsing fails with an error saying the format is XML or binary and is not supported

#### Scenario: Fuzzed input
- **WHEN** a valid file has random bytes inserted, deleted or replaced
- **THEN** the result either parses and round-trips byte for byte, or fails with a located error

### Requirement: Edits leave other bytes untouched
Inserting, removing or replacing a dictionary entry or an array element SHALL change only the bytes of that entry or element and its own separators and trivia.

#### Scenario: Insert into an array
- **WHEN** an element is inserted into a twelve-element array in a 9,000-line file
- **THEN** the serialized output differs from the input by exactly one added line

#### Scenario: Remove from an array
- **WHEN** the third of five elements, which has a trailing comment, is removed
- **THEN** the output differs from the input by exactly that element's line, comment included

#### Scenario: Replace a value
- **WHEN** the value of `path` in one dictionary is replaced
- **THEN** only the bytes of that value change; the key, the `=`, the `;` and surrounding trivia are unchanged

### Requirement: New content is formatted like its neighbours
An inserted entry or element SHALL take its indentation, line-ending style and separator layout from an existing sibling in the same container. When the container is empty, it SHALL derive them from the container's own opening and closing lines.

#### Scenario: Two indentation styles in one file
- **WHEN** an element is inserted into an array whose elements are indented with four tabs, and another into an array whose elements are indented with two tabs
- **THEN** each new line uses the indentation of its own array

#### Scenario: Single-line siblings
- **WHEN** an entry is inserted into a dictionary whose existing entries are each a single-line dictionary
- **THEN** the new entry is written on a single line in the same layout

#### Scenario: Empty array
- **WHEN** an element is inserted into `children = (\n\t\t\t);`
- **THEN** the element is written on its own line, indented one level deeper than the closing parenthesis, followed by a comma

### Requirement: Caller controls position
An insertion SHALL be placed at the index the caller gives: first, last, or before or after a named sibling.

#### Scenario: Insert after a sibling
- **WHEN** an element is inserted after the element `B2`
- **THEN** it appears on the line following `B2`'s line and all other elements keep their order

### Requirement: Written strings are quoted canonically
A string written by this layer SHALL be left bare only if it is non-empty, consists solely of ASCII letters, digits and `_ $ / .`, and contains neither `//` nor `___`. Otherwise it SHALL be quoted with `"`, `\` and control characters escaped. Strings already in the input SHALL keep their original quoting.

#### Scenario: Hyphen and plus are quoted on write
- **WHEN** the values `My-File.swift` and `AppState+Scope.swift` are written
- **THEN** both are written quoted

#### Scenario: Existing quoting is preserved
- **WHEN** the input contains the bare value `My-File.swift` and an unrelated edit is made elsewhere
- **THEN** `My-File.swift` is still bare in the output

### Requirement: UTF-8 only
The input SHALL be decoded as UTF-8. Input that is not valid UTF-8 SHALL fail with an error giving the byte offset.

#### Scenario: Invalid byte sequence
- **WHEN** the input contains the byte `0xFF` inside a quoted string
- **THEN** parsing fails with an error naming the byte offset
