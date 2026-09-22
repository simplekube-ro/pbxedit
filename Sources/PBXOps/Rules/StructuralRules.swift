import PBXSyntax
import PBXModel

/// S2: every referenced ID exists. The keys are the ones the corpus shows
/// holding object IDs (task 3.3's test keeps the list honest); every other
/// key is passed through as data.
struct S2Rule: Rule {
    let id = RuleID.S2

    /// Attribute keys whose value, or whose array elements, are object IDs.
    static let referenceKeys: [String] = [
        "fileRef", "productRef", "children", "files", "buildPhases", "targets", "mainGroup",
        "productRefGroup", "productReference", "dependencies", "target", "targetProxy", "containerPortal",
        "buildConfigurationList", "buildConfigurations", "baseConfigurationReference",
        "baseConfigurationReferenceAnchor", "buildRules", "currentVersion", "package",
        "packageProductDependencies", "packageReferences", "fileSystemSynchronizedGroups", "exceptions",
        "remoteRef", "ProductGroup", "ProjectRef", "buildPhase", "TestTargetID",
    ]

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        var seen: Set<ObjectID> = []
        for object in project.objects where seen.insert(object.id).inserted {
            guard let attributes = object.attributes else { continue }
            S2Rule.visit(attributes) { key, value in
                let target = ObjectID(value)
                guard !project.contains(target) else { return }
                findings.append(Finding(
                    rule: .S2, object: object.id, path: project.pathString(of: object.id), related: [target],
                    message: "\(project.describe(object)) refers to \(target) in '\(key)', which does not exist"))
            }
        }
        return findings
    }

    /// Calls `body` for every string that a reference key holds, directly or
    /// as an array element, at any depth (`projectReferences` nests
    /// `ProductGroup` and `ProjectRef` inside dictionaries).
    static func visit(_ dictionary: DictionaryNode, _ body: (String, String) -> Void) {
        for entry in dictionary.entries {
            let key = entry.key.value
            if referenceKeys.contains(key) {
                switch entry.value {
                case .string(let string):
                    body(key, string.value)
                case .array(let array):
                    for element in array.elements {
                        if let value = element.value.stringValue { body(key, value) }
                    }
                default:
                    break
                }
            }
            switch entry.value {
            case .dictionary(let nested):
                visit(nested, body)
            case .array(let array):
                for element in array.elements {
                    if let nested = element.value.dictionary { visit(nested, body) }
                }
            default:
                break
            }
        }
    }
}

/// S3: no duplicate object IDs; no ID twice in one `children` or `files` array.
struct S3Rule: Rule {
    let id = RuleID.S3

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        for duplicate in project.duplicateIDs {
            findings.append(Finding(
                rule: .S3, object: duplicate, message: "the ID \(duplicate) is defined more than once in 'objects'"))
        }
        var seen: Set<ObjectID> = []
        for object in project.objects where seen.insert(object.id).inserted {
            for key in ["children", "files"] {
                guard let ids = object.ids(key) else { continue }
                var listed: Set<ObjectID> = []
                var reported: Set<ObjectID> = []
                for id in ids where !listed.insert(id).inserted && reported.insert(id).inserted {
                    findings.append(Finding(
                        rule: .S3, object: object.id, path: project.pathString(of: object.id), related: [id],
                        message: "\(project.describe(object)) lists \(id) twice in '\(key)'"))
                }
            }
        }
        return findings
    }
}

/// S4: `platformFilters` is a property-list array of known platform names.
struct S4Rule: Rule {
    let id = RuleID.S4

    /// The names Xcode writes, in the order Xcode's target editor lists them.
    static let knownPlatforms = PlatformFilters.known

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        let known = S4Rule.knownPlatforms.joined(separator: ", ")
        var seen: Set<ObjectID> = []
        for object in project.objects where seen.insert(object.id).inserted {
            guard let value = object.attributes?["platformFilters"] else { continue }
            let path = object.isa == Kind.buildFile
                ? object.id("fileRef").flatMap(project.pathString) : project.pathString(of: object.id)
            guard let array = value.array else {
                findings.append(Finding(
                    rule: .S4, object: object.id, path: path,
                    message: "\(project.describe(object)) has a 'platformFilters' that is not an array; known platform names: \(known)"))
                continue
            }
            let names = array.elements.map { $0.value.stringValue }
            let unknown = names.filter { $0.map { !S4Rule.knownPlatforms.contains($0) } ?? true }
            guard !unknown.isEmpty else { continue }
            let listed = unknown.map { $0.map { "'\($0)'" } ?? "a non-string value" }.joined(separator: ", ")
            findings.append(Finding(
                rule: .S4, object: object.id, path: path,
                message: "\(project.describe(object)) has unknown platform names in 'platformFilters': \(listed); known platform names: \(known)"))
        }
        return findings
    }
}

/// S5: every string is quoted as Xcode would quote it (design D3). Keys and
/// values, inside and outside `objects`.
struct S5Rule: Rule {
    let id = RuleID.S5

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        guard let root = project.tree.root.dictionary else { return findings }
        for entry in root.entries {
            let key = entry.key.value
            if key == Project.objectsKey, let objects = entry.value.dictionary {
                S5Rule.check(entry.key, object: nil, path: key, project: project, into: &findings)
                var seen: Set<ObjectID> = []
                for objectEntry in objects.entries {
                    let id = ObjectID(objectEntry.key.value)
                    guard seen.insert(id).inserted else { continue }
                    let path = project.pathString(of: id)
                    S5Rule.check(objectEntry.key, object: id, path: path, project: project, into: &findings)
                    S5Rule.walk(objectEntry.value, object: id, path: path, project: project, into: &findings)
                }
            } else {
                S5Rule.check(entry.key, object: nil, path: key, project: project, into: &findings)
                S5Rule.walk(entry.value, object: nil, path: key, project: project, into: &findings)
            }
        }
        return findings
    }

    private static func walk(_ node: Node, object: ObjectID?, path: String?, project: Project, into findings: inout [Finding]) {
        switch node {
        case .string(let string):
            check(string, object: object, path: path, project: project, into: &findings)
        case .dictionary(let dictionary):
            for entry in dictionary.entries {
                check(entry.key, object: object, path: path, project: project, into: &findings)
                walk(entry.value, object: object, path: path, project: project, into: &findings)
            }
        case .array(let array):
            for element in array.elements { walk(element.value, object: object, path: path, project: project, into: &findings) }
        case .data:
            break
        }
    }

    private static func check(_ string: StringNode, object: ObjectID?, path: String?, project: Project, into findings: inout [Finding]) {
        guard !string.isCanonicallyQuoted else { return }
        findings.append(Finding(
            rule: .S5, object: object, path: path,
            message: "the string \(string.rawText) is not quoted canonically: Xcode would "
                + (string.isQuoted ? "leave it bare" : "quote it")))
    }
}

extension Project {
    /// `<kind> <id> (<name or path>)` for messages.
    func describe(_ object: Object) -> String {
        let kind: String
        switch object.isa {
        case Kind.fileReference?: kind = "file reference"
        case Kind.buildFile?: kind = "build file"
        case Kind.project?: kind = "project"
        case let isa? where Kind.groups.contains(isa): kind = "group"
        case let isa? where Kind.targets.contains(isa): kind = "target"
        case let isa? where Kind.buildPhases.contains(isa): kind = "build phase"
        case let isa?: kind = isa
        case nil: kind = "object"
        }
        let name: String?
        switch object.isa {
        case Kind.buildFile?:
            name = object.id("fileRef").map { displayPath(of: $0) } ?? object.id("productRef")?.rawValue
        case let isa? where Kind.buildPhases.contains(isa):
            name = buildPhase(object.id)?.displayName
        default:
            name = pathString(of: object.id) ?? object.string("name") ?? object.string("path")
        }
        return name.map { "\(kind) \(object.id) (\($0))" } ?? "\(kind) \(object.id)"
    }
}
