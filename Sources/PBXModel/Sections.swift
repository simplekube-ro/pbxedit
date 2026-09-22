import PBXSyntax

/// Where each `/* Begin <isa> section */ … /* End <isa> section */` block
/// lies among the entries of `objects` (design D5). The markers are comments
/// in the leading trivia of the block's first entry and of the entry after
/// the block — or of the closing brace for the last block.
struct SectionMap: Equatable {
    struct Section: Equatable {
        let isa: String
        /// Entry indices of the block's objects.
        var range: Range<Int>
    }

    struct Marker: Equatable {
        let isa: String
        let isBegin: Bool
    }

    /// In file order.
    private(set) var sections: [Section] = []
    /// The IDs of the entries, in order, so that placement can name siblings.
    private(set) var keys: [String]

    var hasMarkers: Bool { !sections.isEmpty }

    /// Patches the map after the entry `key` of kind `isa` was inserted at
    /// `position`, which `placement(for:id:)` chose: inside or at an edge of
    /// its kind's block, or where a new block for its kind now starts.
    mutating func inserted(_ key: String, at position: Int, isa: String) {
        keys.insert(key, at: position)
        var placed = false
        for index in sections.indices {
            let range = sections[index].range
            if !placed, sections[index].isa == isa, range.lowerBound <= position, position <= range.upperBound {
                sections[index].range = range.lowerBound..<(range.upperBound + 1)
                placed = true
            } else if range.lowerBound >= position {
                sections[index].range = (range.lowerBound + 1)..<(range.upperBound + 1)
            }
        }
        if !placed, hasMarkers {
            let section = Section(isa: isa, range: position..<(position + 1))
            sections.insert(section, at: sections.firstIndex { $0.range.lowerBound > position } ?? sections.count)
        }
    }

    /// Patches the map after the entry at `position` was removed; a block
    /// left empty is gone with its markers.
    mutating func removed(at position: Int) {
        guard keys.indices.contains(position) else { return }
        keys.remove(at: position)
        for index in sections.indices {
            let range = sections[index].range
            if range.contains(position) {
                sections[index].range = range.lowerBound..<(range.upperBound - 1)
            } else if range.lowerBound > position {
                sections[index].range = (range.lowerBound - 1)..<(range.upperBound - 1)
            }
        }
        sections.removeAll { $0.range.isEmpty }
    }

    init(_ tree: SyntaxTree) {
        let entries = tree.node(at: [.key(Project.objectsKey)])?.dictionary?.entries ?? []
        keys = entries.map(\.key.value)
        var open: (isa: String, start: Int)?
        func close(at index: Int) {
            if let open { sections.append(Section(isa: open.isa, range: open.start..<index)) }
            open = nil
        }
        for (index, entry) in entries.enumerated() {
            for marker in SectionMap.markers(in: entry.key.token.leadingTrivia) {
                if marker.isBegin {
                    close(at: index)
                    open = (marker.isa, index)
                } else if open?.isa == marker.isa {
                    close(at: index)
                }
            }
        }
        for marker in SectionMap.markers(in: tree.closingTrivia(at: [.key(Project.objectsKey)]) ?? .empty)
        where !marker.isBegin && open?.isa == marker.isa {
            close(at: entries.count)
        }
        close(at: entries.count)
    }

    func section(for isa: String) -> Section? { sections.first { $0.isa == isa } }

    /// Whether the block's IDs are in strictly ascending byte order.
    func isSorted(_ section: Section) -> Bool {
        let ids = keys[section.range]
        return zip(ids, ids.dropFirst()).allSatisfy { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    /// Where a new object of kind `isa` with ID `id` goes.
    enum Placement: Equatable {
        /// Into an existing block, at this position among `objects`' entries.
        case inSection(InsertPosition)
        /// A new block directly above the entry with this key, which starts
        /// the alphabetically following block.
        case newSection(beforeFirstOf: String)
        /// A new block after every existing one.
        case newSectionLast
        /// The file has no markers: append to `objects`.
        case append
    }

    func placement(for isa: String, id: ObjectID) -> Placement {
        guard hasMarkers else { return .append }
        if let section = section(for: isa), !section.range.isEmpty {
            let ids = keys[section.range]
            if isSorted(section), let next = ids.first(where: { id.rawValue.utf8.lexicographicallyPrecedes($0.utf8) }) {
                return .inSection(.before(next))
            }
            return .inSection(.after(ids[ids.index(before: ids.endIndex)]))
        }
        if let next = sections.first(where: { isa.utf8.lexicographicallyPrecedes($0.isa.utf8) && !$0.range.isEmpty }) {
            return .newSection(beforeFirstOf: keys[next.range.lowerBound])
        }
        return .newSectionLast
    }

    // MARK: Marker text

    static func markers(in trivia: Trivia) -> [Marker] {
        trivia.pieces.compactMap { piece in
            guard case .blockComment(let text) = piece else { return nil }
            return marker(fromCommentBody: Trivia.commentBody(text))
        }
    }

    static func marker(fromCommentBody body: String) -> Marker? {
        guard body.hasSuffix(" section") else { return nil }
        let isa = body.dropLast(" section".count)
        if isa.hasPrefix("Begin ") { return Marker(isa: String(isa.dropFirst("Begin ".count)), isBegin: true) }
        if isa.hasPrefix("End ") { return Marker(isa: String(isa.dropFirst("End ".count)), isBegin: false) }
        return nil
    }

    static func markerComment(_ isa: String, begin: Bool) -> String {
        "/* \(begin ? "Begin" : "End") \(isa) section */"
    }

    /// `trivia` with its first Begin (or End) marker replaced by the marker of
    /// `isa`; when it has none, the marker is put in front on its own line.
    static func replacingMarker(in trivia: Trivia, begin: Bool, with isa: String, newline: String) throws -> Trivia {
        var text = ""
        var replaced = false
        for piece in trivia.pieces {
            if !replaced, case .blockComment(let comment) = piece,
               let marker = marker(fromCommentBody: Trivia.commentBody(comment)), marker.isBegin == begin {
                text += markerComment(isa, begin: begin)
                replaced = true
            } else {
                text += piece.text
            }
        }
        if !replaced { text = newline + markerComment(isa, begin: begin) + trivia.text }
        guard let result = Trivia(validating: text) else { throw MutationError.malformedTrivia(text) }
        return result
    }

    /// `trivia` with the empty block of `isa` — its Begin marker, the
    /// whitespace before it, and its End marker — removed. Unchanged when the
    /// block is not there.
    static func removingEmptySection(_ isa: String, from trivia: Trivia) -> Trivia {
        let pieces = trivia.pieces
        guard let begin = pieces.firstIndex(where: { SectionMap.isMarker($0, isa: isa, begin: true) }),
              let end = pieces[begin...].firstIndex(where: { SectionMap.isMarker($0, isa: isa, begin: false) })
        else { return trivia }
        var start = begin
        if begin > 0, case .whitespace = pieces[begin - 1] { start = begin - 1 }
        let text = (pieces[..<start] + pieces[(end + 1)...]).map(\.text).joined()
        return Trivia(validating: text) ?? trivia
    }

    private static func isMarker(_ piece: TriviaPiece, isa: String, begin: Bool) -> Bool {
        guard case .blockComment(let text) = piece else { return false }
        return marker(fromCommentBody: Trivia.commentBody(text)) == Marker(isa: isa, isBegin: begin)
    }
}

extension Trivia {
    /// The body of `/* body */`, with one space of padding on each side removed.
    static func commentBody(_ text: String) -> String {
        var bytes = Array(text.utf8)
        guard bytes.count >= 4 else { return "" }
        bytes = Array(bytes[2..<(bytes.count - 2)])
        if bytes.first == 0x20 { bytes.removeFirst() }
        if bytes.last == 0x20 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The line break used before the last line of the trivia: `\r\n` when
    /// present, else `\n`.
    var lineBreak: String {
        let bytes = Array(text.utf8)
        if let last = bytes.lastIndex(of: 0x0A), last > 0, bytes[last - 1] == 0x0D { return "\r\n" }
        return "\n"
    }
}
