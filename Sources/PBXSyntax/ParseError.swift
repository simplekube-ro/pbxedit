/// Why and where input failed to parse (design D7). Errors are values: the
/// parser never traps.
public struct ParseError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Kind: Sendable, Equatable {
        /// The input is not valid UTF-8. `byteOffset` is the first bad byte.
        case invalidUTF8
        /// The input is an XML or binary property list.
        case unsupportedFormat(UnsupportedFormat)
        /// A byte that cannot start or continue any token.
        case unexpectedCharacter
        case unterminatedComment
        case unterminatedString
        case malformedData
        /// A well-formed token in a place the grammar does not allow it.
        case unexpectedToken
        case unexpectedEndOfInput
        /// Containers nested deeper than `SyntaxTree.maximumNestingDepth`.
        case nestingTooDeep
    }

    public enum UnsupportedFormat: Sendable, Equatable {
        case xml
        case binary
    }

    public let kind: Kind
    /// 1-based line. Lines end at LF, CRLF or a lone CR.
    public let line: Int
    /// 1-based column, counted in Unicode scalars; a tab counts as one.
    public let column: Int
    /// 0-based offset into the input bytes.
    public let byteOffset: Int
    public let expected: String
    public let found: String

    public var description: String {
        "\(line):\(column): expected \(expected), found \(found) (byte offset \(byteOffset))"
    }

    init(kind: Kind, at byteOffset: Int, in buffer: UnsafeBufferPointer<UInt8>, expected: String, found: String? = nil) {
        let offset = max(0, min(byteOffset, buffer.count))
        var line = 1
        var lineStart = 0
        var position = 0
        while position < offset {
            let byte = buffer[position]
            if byte == 0x0A {
                line += 1
                lineStart = position + 1
            } else if byte == 0x0D {
                // CRLF is one line break; the LF is counted on the next turn.
                if !(position + 1 < buffer.count && buffer[position + 1] == 0x0A) {
                    line += 1
                    lineStart = position + 1
                }
            }
            position += 1
        }
        var column = 1
        position = lineStart
        while position < offset {
            // Count every byte that is not a UTF-8 continuation byte.
            if buffer[position] & 0xC0 != 0x80 { column += 1 }
            position += 1
        }
        self.kind = kind
        self.line = line
        self.column = column
        self.byteOffset = offset
        self.expected = expected
        self.found = found ?? ParseError.describe(buffer, at: offset)
    }

    /// A printable description of whatever starts at `offset`.
    static func describe(_ buffer: UnsafeBufferPointer<UInt8>, at offset: Int) -> String {
        guard offset < buffer.count else { return "end of input" }
        let first = buffer[offset]
        let length: Int
        switch first {
        case 0x00...0x7F: length = 1
        case 0xC0...0xDF: length = 2
        case 0xE0...0xEF: length = 3
        case 0xF0...0xF7: length = 4
        default: length = 1
        }
        let end = min(buffer.count, offset + length)
        let decoded = String(decoding: UnsafeBufferPointer(rebasing: buffer[offset..<end]), as: UTF8.self)
        if let scalar = decoded.unicodeScalars.first, decoded.unicodeScalars.count == 1,
           scalar != "\u{FFFD}" || (length == 3 && end - offset == 3) {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return "control character U+" + hex(scalar.value, width: 4)
            }
            return "'\(decoded)'"
        }
        return "byte 0x" + hex(UInt32(first), width: 2)
    }

    static func hex(_ value: UInt32, width: Int) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
