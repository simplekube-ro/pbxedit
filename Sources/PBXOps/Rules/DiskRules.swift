import PBXModel

/// D1: a file reference's resolved path exists. Products and references that
/// are not project-relative are skipped: they never live under the source root.
struct D1Rule: DiskRule {
    let id = RuleID.D1

    func evaluate(_ project: Project, disk: any DiskReader) -> [Finding] {
        let products = project.productReferences
        var findings: [Finding] = []
        var seen: Set<ObjectID> = []
        for reference in project.fileReferences where !products.contains(reference.id) && seen.insert(reference.id).inserted {
            guard let path = project.pathString(of: reference.id), !disk.exists(path) else { continue }
            findings.append(Finding(
                rule: .D1, object: reference.id, path: path,
                message: "file reference \(reference.id) resolves to \(path), which does not exist"))
        }
        return findings
    }
}

/// D2: a source or resource directly inside a directory some group resolves
/// to is referenced, unless a synchronized root group covers it.
struct D2Rule: DiskRule {
    let id = RuleID.D2

    /// The extensions D2 reports. Sources, then the resources Xcode's
    /// templates create; `plist`, `json` and text files are left out because
    /// they are as often configuration as content.
    static let extensions: Set<String> = [
        "swift", "m", "mm", "c", "cc", "cpp", "cxx", "h", "hh", "hpp", "s", "metal",
        "xib", "storyboard", "strings", "stringsdict", "xcassets", "xcdatamodeld", "intentdefinition",
        "png", "jpg", "jpeg", "heic", "pdf", "svg", "ttf", "otf", "mp3", "mp4", "wav", "caf",
    ]

    func evaluate(_ project: Project, disk: any DiskReader) -> [Finding] {
        var findings: [Finding] = []
        var directories: Set<String> = []
        for group in project.groups {
            guard case .relative(let directory)? = project.resolvedPath(of: group.id), directories.insert(directory).inserted else {
                continue
            }
            let owner = project.groups(at: directory).first ?? group
            for name in disk.files(in: directory) {
                guard let dot = name.lastIndex(of: "."), D2Rule.extensions.contains(name[name.index(after: dot)...].lowercased()) else {
                    continue
                }
                let path = directory.isEmpty ? name : directory + "/" + name
                guard project.fileReferences(at: path).isEmpty, project.synchronizedRootGroup(covering: path) == nil else { continue }
                let label = directory.isEmpty ? "the source root" : directory
                findings.append(Finding(
                    rule: .D2, object: nil, path: path, related: [owner.id],
                    message: "\(path) is on disk in the directory of group \(owner.id) (\(label)) but no file reference resolves to it"))
            }
        }
        return findings
    }
}
