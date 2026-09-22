/// What a file is to a target: the phase its build file goes in, or none.
public enum FileKind: String, Equatable, Sendable {
    case source, resource, header, projectOnly
}

/// The build phase a file goes to; `--phase` names one of these. The case
/// for "no phase" is `notBuilt`, spelled `none` on the command line, because
/// a case named `none` is read as `Optional.none` wherever the choice is
/// optional — which `Conventions.Flags.phase` is.
public enum PhaseChoice: String, Equatable, Sendable, CaseIterable {
    case sources, resources, headers
    case notBuilt = "none"

    public init(kind: FileKind) {
        switch kind {
        case .source: self = .sources
        case .resource: self = .resources
        case .header: self = .headers
        case .projectOnly: self = .notBuilt
        }
    }

    /// The kind a phase choice stands for when the extension is unknown.
    public var kind: FileKind {
        switch self {
        case .sources: return .source
        case .resources: return .resource
        case .headers: return .header
        case .notBuilt: return .projectOnly
        }
    }

    /// The `isa` of the phase, or `nil` for `none`.
    public var isa: String? {
        switch self {
        case .sources: return "PBXSourcesBuildPhase"
        case .resources: return "PBXResourcesBuildPhase"
        case .headers: return "PBXHeadersBuildPhase"
        case .notBuilt: return nil
        }
    }

    /// The name Xcode gives the phase.
    public var displayName: String {
        switch self {
        case .sources: return "Sources"
        case .resources: return "Resources"
        case .headers: return "Headers"
        case .notBuilt: return "none"
        }
    }
}

public struct FileType: Equatable, Sendable {
    public let kind: FileKind
    public let lastKnownFileType: String

    public init(kind: FileKind, lastKnownFileType: String) {
        self.kind = kind
        self.lastKnownFileType = lastKnownFileType
    }
}

/// The static table of design D6: extension → kind and `lastKnownFileType`,
/// as Xcode writes them. An extension that is not here is unknown, never
/// defaulted.
public enum FileTypes {
    /// What Xcode writes for a file it does not recognise, used only when
    /// `--phase` says where an unknown file goes.
    public static let unknownLastKnownFileType = "file"

    static let table: [String: FileType] = {
        var table: [String: FileType] = [:]
        func add(_ kind: FileKind, _ type: String, _ extensions: String...) {
            for ext in extensions { table[ext] = FileType(kind: kind, lastKnownFileType: type) }
        }
        // Sources: what Xcode's new-file templates produce.
        add(.source, "sourcecode.swift", "swift")
        add(.source, "sourcecode.c.objc", "m")
        add(.source, "sourcecode.cpp.objcpp", "mm")
        add(.source, "sourcecode.c.c", "c")
        add(.source, "sourcecode.cpp.cpp", "cpp", "cc", "cxx")
        add(.source, "sourcecode.metal", "metal")
        add(.source, "sourcecode.asm", "s")
        add(.source, "file.intentdefinition", "intentdefinition")
        add(.source, "file.mlmodel", "mlmodel")
        add(.source, "wrapper.xcdatamodel", "xcdatamodeld")
        add(.source, "wrapper.xcmappingmodel", "xcmappingmodel")
        // Headers.
        add(.header, "sourcecode.c.h", "h")
        add(.header, "sourcecode.cpp.h", "hpp", "hh", "hxx")
        // Resources.
        add(.resource, "folder.assetcatalog", "xcassets")
        add(.resource, "text.json.xcstrings", "xcstrings")
        add(.resource, "text.plist.strings", "strings")
        add(.resource, "text.plist.stringsdict", "stringsdict")
        add(.resource, "file.storyboard", "storyboard")
        add(.resource, "file.xib", "xib")
        add(.resource, "text.json", "json")
        add(.resource, "image.png", "png")
        add(.resource, "image.jpeg", "jpg", "jpeg")
        add(.resource, "image.gif", "gif")
        add(.resource, "image.pdf", "pdf")
        add(.resource, "image.heic", "heic")
        add(.resource, "audio.mp3", "mp3")
        add(.resource, "audio.wav", "wav")
        add(.resource, "audio.aiff", "aiff", "aif")
        add(.resource, "video.quicktime", "mov")
        add(.resource, "file", "mp4", "ttf", "otf")
        add(.resource, "text.html", "html")
        add(.resource, "text.css", "css")
        add(.resource, "text", "txt")
        add(.resource, "text.rtf", "rtf")
        add(.resource, "wrapper.scnassets", "scnassets")
        add(.resource, "file.sks", "sks")
        add(.resource, "file.usdz", "usdz")
        add(.resource, "wrapper.plug-in", "bundle")
        add(.resource, "text.xml", "xml")
        add(.resource, "file.rcproject", "rcproject")
        // Project-only: referenced, never built.
        add(.projectOnly, "text.plist.xml", "plist")
        add(.projectOnly, "text.plist.entitlements", "entitlements")
        add(.projectOnly, "text.xcconfig", "xcconfig")
        add(.projectOnly, "net.daringfireball.markdown", "md", "markdown")
        add(.projectOnly, "sourcecode.module-map", "modulemap")
        add(.projectOnly, "sourcecode.c.h", "pch")
        add(.projectOnly, "text.yaml", "yml", "yaml")
        add(.projectOnly, "wrapper.docc", "docc")
        add(.projectOnly, "text.script.sh", "sh")
        add(.projectOnly, "text.script.python", "py")
        add(.projectOnly, "text.script.ruby", "rb")
        return table
    }()

    /// The type for an extension, matched case-insensitively; `nil` when unknown.
    public static func type(forExtension ext: String) -> FileType? {
        table[ext.lowercased()]
    }

    /// The type of the file at `path`, by its extension: the text after the
    /// last dot of the last component, when that dot is not the first
    /// character (`.hidden` has no extension).
    public static func type(of path: String) -> FileType? {
        let name = path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        return type(forExtension: String(name[name.index(after: dot)...]))
    }
}
