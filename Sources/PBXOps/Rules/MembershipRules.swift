import PBXModel

/// Shared vocabulary of the membership rules.
extension Project {
    /// The `productReference` of every target: references M3 and D1 exempt,
    /// because they are products, not files of the project.
    var productReferences: Set<ObjectID> {
        Set(targets.compactMap(\.productReference))
    }

    /// The resolved path of `id` as a string, when it is project-relative or absolute.
    func pathString(of id: ObjectID) -> String? {
        switch resolvedPath(of: id) {
        case .relative(let path)?, .absolute(let path)?: return path
        default: return nil
        }
    }

    /// The path of a file reference for a message: resolved, else its `path`, else its ID.
    func displayPath(of id: ObjectID) -> String {
        pathString(of: id) ?? fileReference(id)?.path ?? id.rawValue
    }

    /// `<id> (<name>)` for a target or phase in a message.
    func label(_ id: ObjectID) -> String {
        if let target = target(id), let name = target.name { return "\(id) (\(name))" }
        if let phase = buildPhase(id) { return "\(id) (\(phase.displayName))" }
        return id.rawValue
    }

    /// The distinct phases listing `buildFile`, in object order.
    func distinctPhases(of buildFile: ObjectID) -> [BuildPhase] {
        var result: [BuildPhase] = []
        for phase in phases(of: buildFile) where !result.contains(where: { $0.id == phase.id }) { result.append(phase) }
        return result
    }
}

/// M1: every build file is listed in exactly one build phase.
struct M1Rule: Rule {
    let id = RuleID.M1

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        // Each ID once: a duplicate ID is S3's finding, and its first entry is the one lookups return.
        var seen: Set<ObjectID> = []
        for buildFile in project.buildFiles where seen.insert(buildFile.id).inserted {
            let phases = project.distinctPhases(of: buildFile.id)
            guard phases.count != 1 else { continue }
            let file = buildFile.fileRef ?? buildFile.productRef
            let path = buildFile.fileRef.flatMap(project.pathString)
            let subject = "build file \(buildFile.id)" + (file.map { " (\(project.displayPath(of: $0)))" } ?? "")
            if phases.isEmpty {
                findings.append(Finding(
                    rule: .M1, object: buildFile.id, path: path, related: file.map { [$0] } ?? [],
                    message: "\(subject) is listed in no build phase"))
            } else {
                findings.append(Finding(
                    rule: .M1, object: buildFile.id, path: path, related: (file.map { [$0] } ?? []) + phases.map(\.id),
                    message: "\(subject) is listed in \(phases.count) build phases: " + phases.map(\.id.rawValue).joined(separator: ", ")))
            }
        }
        return findings
    }
}

/// M2: every build-phase entry names a build file whose `fileRef` or
/// `productRef` resolves.
struct M2Rule: Rule {
    let id = RuleID.M2

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        var reportedBuildFiles: Set<ObjectID> = []
        var seenPhases: Set<ObjectID> = []
        for phase in project.buildPhases where seenPhases.insert(phase.id).inserted {
            var seen: Set<ObjectID> = []
            for entry in phase.files where seen.insert(entry).inserted {
                guard let buildFile = project.buildFile(entry) else {
                    findings.append(Finding(
                        rule: .M2, object: phase.id, related: [entry],
                        message: "build phase \(project.label(phase.id)) lists \(entry), which is not a build file"))
                    continue
                }
                guard reportedBuildFiles.insert(entry).inserted else { continue }
                if let fileRef = buildFile.fileRef {
                    guard !project.contains(fileRef) else { continue }
                    findings.append(Finding(
                        rule: .M2, object: entry, related: [fileRef, phase.id],
                        message: "build file \(entry) in build phase \(project.label(phase.id)) has a 'fileRef' \(fileRef) that does not resolve"))
                } else if let productRef = buildFile.productRef {
                    guard !project.contains(productRef) else { continue }
                    findings.append(Finding(
                        rule: .M2, object: entry, related: [productRef, phase.id],
                        message: "build file \(entry) in build phase \(project.label(phase.id)) has a 'productRef' \(productRef) that does not resolve"))
                } else {
                    findings.append(Finding(
                        rule: .M2, object: entry, related: [phase.id],
                        message: "build file \(entry) in build phase \(project.label(phase.id)) has neither a 'fileRef' nor a 'productRef'"))
                }
            }
        }
        return findings
    }
}

/// M3: every file reference has exactly one parent group; products exempt.
struct M3Rule: Rule {
    let id = RuleID.M3

    func evaluate(_ project: Project) -> [Finding] {
        let products = project.productReferences
        var findings: [Finding] = []
        var seen: Set<ObjectID> = []
        for reference in project.fileReferences where !products.contains(reference.id) && seen.insert(reference.id).inserted {
            // Distinct parents: the same group listing a child twice is S3's finding.
            var parents: [Group] = []
            for parent in project.parents(of: reference.id) where !parents.contains(where: { $0.id == parent.id }) {
                parents.append(parent)
            }
            let path = project.pathString(of: reference.id)
            if parents.isEmpty {
                findings.append(Finding(
                    rule: .M3, object: reference.id, path: path,
                    message: "file reference \(reference.id) (\(project.displayPath(of: reference.id))) has no parent group"))
            } else if parents.count > 1 {
                findings.append(Finding(
                    rule: .M3, object: reference.id, path: path, related: parents.map(\.id),
                    message: "file reference \(reference.id) (\(project.displayPath(of: reference.id))) has \(parents.count) parent groups: "
                        + parents.map(\.id.rawValue).joined(separator: ", ")))
            }
        }
        return findings
    }
}

/// M4: no two project-relative file references resolve to the same path.
struct M4Rule: Rule {
    let id = RuleID.M4

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        var firstAtPath: [String: ObjectID] = [:]
        var seen: Set<ObjectID> = []
        for reference in project.fileReferences where seen.insert(reference.id).inserted {
            guard let path = project.pathString(of: reference.id) else { continue }
            if let first = firstAtPath[path] {
                findings.append(Finding(
                    rule: .M4, object: reference.id, path: path, related: [first],
                    message: "file reference \(reference.id) resolves to \(path), the same path as \(first)"))
            } else {
                firstAtPath[path] = reference.id
            }
        }
        return findings
    }
}

/// M5: no two build files in one phase share a `fileRef` or `productRef`.
struct M5Rule: Rule {
    let id = RuleID.M5

    func evaluate(_ project: Project) -> [Finding] {
        var findings: [Finding] = []
        var seenPhases: Set<ObjectID> = []
        for phase in project.buildPhases where seenPhases.insert(phase.id).inserted {
            var firstForFile: [ObjectID: ObjectID] = [:]
            var seen: Set<ObjectID> = []
            for entry in phase.files where seen.insert(entry).inserted {
                guard let buildFile = project.buildFile(entry) else { continue }
                let key: String
                let file: ObjectID
                if let fileRef = buildFile.fileRef {
                    key = "file reference"
                    file = fileRef
                } else if let productRef = buildFile.productRef {
                    key = "package product"
                    file = productRef
                } else {
                    continue
                }
                if let first = firstForFile[file] {
                    let name = key == "file reference" ? " (\(project.displayPath(of: file)))" : ""
                    findings.append(Finding(
                        rule: .M5, object: entry, path: project.pathString(of: file), related: [first, file, phase.id],
                        message: "build file \(entry) shares \(key) \(file)\(name) with \(first) in build phase \(project.label(phase.id))"))
                } else {
                    firstForFile[file] = entry
                }
            }
        }
        return findings
    }
}

/// M6: a source is built by the target whose directory it lies in (design D4).
struct M6Rule: Rule {
    let id = RuleID.M6

    /// The share of a directory's Sources-phase files a target must build to own it.
    static let rootThreshold = 0.9

    func evaluate(_ project: Project) -> [Finding] {
        // Sources-phase build files by target, and per top-level directory the
        // distinct files each target builds there.
        struct Entry {
            let buildFile: ObjectID
            let fileRef: ObjectID
            let path: String
            let directory: String
            let target: ObjectID
        }
        var entries: [Entry] = []
        var filesByDirectory: [String: Set<ObjectID>] = [:]
        var filesByDirectoryAndTarget: [String: [ObjectID: Set<ObjectID>]] = [:]
        var seenTargets: Set<ObjectID> = []
        for target in project.targets where seenTargets.insert(target.id).inserted {
            for phaseID in target.buildPhases {
                guard let phase = project.buildPhase(phaseID), phase.isa == "PBXSourcesBuildPhase" else { continue }
                for entry in phase.files {
                    guard let buildFile = project.buildFile(entry), let fileRef = buildFile.fileRef,
                          case .relative(let path)? = project.resolvedPath(of: fileRef),
                          let slash = path.firstIndex(of: "/")
                    else { continue }
                    let directory = String(path[..<slash])
                    entries.append(Entry(buildFile: entry, fileRef: fileRef, path: path, directory: directory, target: target.id))
                    filesByDirectory[directory, default: []].insert(fileRef)
                    filesByDirectoryAndTarget[directory, default: [:]][target.id, default: []].insert(fileRef)
                }
            }
        }
        var rootsByDirectory: [String: [ObjectID]] = [:]
        for (directory, files) in filesByDirectory {
            let total = Double(files.count)
            for (target, owned) in filesByDirectoryAndTarget[directory] ?? [:]
            where Double(owned.count) / total >= M6Rule.rootThreshold {
                rootsByDirectory[directory, default: []].append(target)
            }
        }
        var findings: [Finding] = []
        var reported: Set<ObjectID> = []
        for entry in entries where reported.insert(entry.buildFile).inserted {
            let roots = rootsByDirectory[entry.directory] ?? []
            guard !roots.isEmpty, !roots.contains(entry.target) else { continue }
            let owners = roots.sorted().map(project.label).joined(separator: ", ")
            findings.append(Finding(
                rule: .M6, object: entry.buildFile, path: entry.path, related: [entry.fileRef, entry.target] + roots.sorted(),
                message: "\(entry.path) is in the Sources phase of target \(project.label(entry.target)), "
                    + "but \(entry.directory)/ is the root of target \(owners)"))
        }
        return findings
    }
}
