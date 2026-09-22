/// One run of whitespace or one comment.
///
/// Comment cases hold the comment's full text, delimiters included.
public enum TriviaPiece: Sendable, Equatable {
    case whitespace(String)
    case blockComment(String)
    case lineComment(String)
    /// A UTF-8 byte order mark. Only ever the first piece of a file.
    case byteOrderMark

    /// The exact source text of the piece.
    public var text: String {
        switch self {
        case .whitespace(let text), .blockComment(let text), .lineComment(let text):
            return text
        case .byteOrderMark:
            return "\u{FEFF}"
        }
    }
}

/// The whitespace and comments that precede a token.
///
/// Trivia is stored as its exact source text. It can only be built from
/// whitespace and well-formed comments, so a tree that holds it always
/// serializes to text that parses again.
public struct Trivia: Sendable, Equatable {
    /// The exact source text.
    public let text: String

    /// Unchecked: the caller guarantees `text` is whitespace and comments only.
    init(unchecked text: String) {
        self.text = text
    }

    /// Trivia from arbitrary text, or `nil` unless `text` is entirely
    /// whitespace and well-formed comments. A byte order mark is not accepted:
    /// it is only trivia at the start of a file.
    public init?(validating text: String) {
        let bytes = Array(text.utf8)
        let valid = bytes.withUnsafeBufferPointer { buffer in
            if case .success(let end) = TriviaScanner.triviaEnd(in: buffer, from: 0, allowByteOrderMark: false) {
                return end == buffer.count
            }
            return false
        }
        guard valid else { return nil }
        self.text = text
    }

    public static let empty = Trivia(unchecked: "")

    public var isEmpty: Bool { text.utf8.isEmpty }

    /// Byte-exact comparison. `String ==` would equate canonically equivalent
    /// text, and this layer promises bytes.
    public static func == (lhs: Trivia, rhs: Trivia) -> Bool {
        lhs.text.utf8.elementsEqual(rhs.text.utf8)
    }

    /// Whitespace trivia, or `nil` when `text` holds anything else.
    public static func whitespace(_ text: String) -> Trivia? {
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            TriviaScanner.whitespaceEnd(in: buffer, from: 0) == buffer.count ? Trivia(unchecked: text) : nil
        }
    }

    /// A block comment `/* body */`, or `nil` when `body` contains `*/`.
    public static func blockComment(_ body: String) -> Trivia? {
        guard !containsBlockCommentTerminator(body) else { return nil }
        return Trivia(unchecked: "/* " + body + " */")
    }

    public static func + (lhs: Trivia, rhs: Trivia) -> Trivia {
        if lhs.isEmpty { return rhs }
        if rhs.isEmpty { return lhs }
        // A line comment swallows whatever follows it on the same line, so the
        // join needs a line break unless the right side starts with one.
        if case .lineComment? = lhs.pieces.last {
            if let first = rhs.text.utf8.first, first == 0x0A || first == 0x0D {
                return Trivia(unchecked: lhs.text + rhs.text)
            }
            return Trivia(unchecked: lhs.text + "\n" + rhs.text)
        }
        return Trivia(unchecked: lhs.text + rhs.text)
    }

    /// The trivia split into whitespace runs and comments.
    public var pieces: [TriviaPiece] {
        if isEmpty { return [] }
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            var pieces: [TriviaPiece] = []
            var position = 0
            while position < buffer.count {
                guard let (piece, end) = TriviaScanner.nextPiece(in: buffer, from: position, allowByteOrderMark: position == 0),
                      end > position
                else { break }
                pieces.append(piece)
                position = end
            }
            return pieces
        }
    }

    static func containsBlockCommentTerminator(_ body: String) -> Bool {
        var previous: UInt8 = 0
        for byte in body.utf8 {
            if previous == 0x2A, byte == 0x2F { return true }
            previous = byte
        }
        return false
    }
}

/// Byte-level recognition of whitespace and comments, shared by the lexer and
/// by `Trivia.pieces`.
enum TriviaScanner {
    enum Failure: Error {
        case unterminatedBlockComment(at: Int)
    }

    static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    /// The end of the whitespace run starting at `start`. U+2028 and U+2029
    /// count as whitespace, as they do for CoreFoundation's reader.
    static func whitespaceEnd(in buffer: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        var position = start
        while position < buffer.count {
            let byte = buffer[position]
            if isWhitespace(byte) {
                position += 1
            } else if byte == 0xE2, position + 2 < buffer.count, buffer[position + 1] == 0x80,
                      buffer[position + 2] == 0xA8 || buffer[position + 2] == 0xA9 {
                position += 3
            } else {
                break
            }
        }
        return position
    }

    /// The end of the trivia starting at `start`.
    static func triviaEnd(
        in buffer: UnsafeBufferPointer<UInt8>, from start: Int, allowByteOrderMark: Bool
    ) -> Result<Int, Failure> {
        var position = start
        if allowByteOrderMark, hasByteOrderMark(buffer, at: position) { position += 3 }
        while position < buffer.count {
            let afterWhitespace = whitespaceEnd(in: buffer, from: position)
            if afterWhitespace > position {
                position = afterWhitespace
                continue
            }
            guard buffer[position] == 0x2F, position + 1 < buffer.count else { break }
            let next = buffer[position + 1]
            if next == 0x2A {
                guard let end = blockCommentEnd(in: buffer, from: position) else {
                    return .failure(.unterminatedBlockComment(at: position))
                }
                position = end
            } else if next == 0x2F {
                position = lineCommentEnd(in: buffer, from: position)
            } else {
                break
            }
        }
        return .success(position)
    }

    /// The piece starting at `start` and the offset just past it, or `nil`
    /// when no trivia starts there.
    static func nextPiece(
        in buffer: UnsafeBufferPointer<UInt8>, from start: Int, allowByteOrderMark: Bool
    ) -> (TriviaPiece, Int)? {
        guard start < buffer.count else { return nil }
        if allowByteOrderMark, hasByteOrderMark(buffer, at: start) {
            return (.byteOrderMark, start + 3)
        }
        let afterWhitespace = whitespaceEnd(in: buffer, from: start)
        if afterWhitespace > start {
            return (.whitespace(string(buffer, start, afterWhitespace)), afterWhitespace)
        }
        guard buffer[start] == 0x2F, start + 1 < buffer.count else { return nil }
        if buffer[start + 1] == 0x2A {
            guard let end = blockCommentEnd(in: buffer, from: start) else { return nil }
            return (.blockComment(string(buffer, start, end)), end)
        }
        if buffer[start + 1] == 0x2F {
            let end = lineCommentEnd(in: buffer, from: start)
            return (.lineComment(string(buffer, start, end)), end)
        }
        return nil
    }

    private static func hasByteOrderMark(_ buffer: UnsafeBufferPointer<UInt8>, at position: Int) -> Bool {
        position + 2 < buffer.count && buffer[position] == 0xEF && buffer[position + 1] == 0xBB
            && buffer[position + 2] == 0xBF
    }

    /// `start` is at `/*`. Returns the offset just past `*/`.
    private static func blockCommentEnd(in buffer: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        var position = start + 2
        while position + 1 < buffer.count {
            if buffer[position] == 0x2A, buffer[position + 1] == 0x2F { return position + 2 }
            position += 1
        }
        return nil
    }

    /// `start` is at `//`. Returns the offset of the line break, or the end.
    private static func lineCommentEnd(in buffer: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        var position = start + 2
        while position < buffer.count, buffer[position] != 0x0A, buffer[position] != 0x0D { position += 1 }
        return position
    }

    static func string(_ buffer: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> String {
        guard start < end, end <= buffer.count else { return "" }
        return String(decoding: UnsafeBufferPointer(rebasing: buffer[start..<end]), as: UTF8.self)
    }
}
