/// Byte-level lexer (design D4). Every structural character is ASCII, so
/// multi-byte UTF-8 passes through strings and comments untouched and every
/// offset is exact.
struct Lexer {
    struct Output {
        var tokens: [Token]
        /// The byte offset at which each token's text starts.
        var offsets: [Int]
    }

    /// Tokenizes `bytes`. The result always ends with an `.endOfFile` token,
    /// and concatenating every token's trivia and text reproduces `bytes`.
    static func tokenize(_ bytes: [UInt8]) -> Result<[Token], ParseError> {
        bytes.withUnsafeBufferPointer { lex($0).map(\.tokens) }
    }

    static func lex(_ buffer: UnsafeBufferPointer<UInt8>) -> Result<Output, ParseError> {
        var lexer = Lexer(buffer: buffer)
        return lexer.run()
    }

    private let buffer: UnsafeBufferPointer<UInt8>
    private var position = 0

    private init(buffer: UnsafeBufferPointer<UInt8>) {
        self.buffer = buffer
    }

    private mutating func run() -> Result<Output, ParseError> {
        if let error = InputChecks.firstProblem(in: buffer) { return .failure(error) }
        var tokens: [Token] = []
        var offsets: [Int] = []
        tokens.reserveCapacity(buffer.count / 8 + 1)
        offsets.reserveCapacity(buffer.count / 8 + 1)
        while true {
            let triviaStart = position
            switch TriviaScanner.triviaEnd(in: buffer, from: position, allowByteOrderMark: position == 0) {
            case .success(let end):
                position = end
            case .failure(.unterminatedBlockComment(let offset)):
                return .failure(
                    ParseError(
                        kind: .unterminatedComment, at: offset, in: buffer,
                        expected: "'*/' to close the comment opened here", found: "end of input"))
            }
            let trivia = triviaStart == position
                ? Trivia.empty : Trivia(unchecked: TriviaScanner.string(buffer, triviaStart, position))
            guard position < buffer.count else {
                tokens.append(Token(kind: .endOfFile, text: "", leadingTrivia: trivia))
                offsets.append(position)
                return .success(Output(tokens: tokens, offsets: offsets))
            }
            let tokenStart = position
            switch nextToken(leadingTrivia: trivia) {
            case .success(let token):
                tokens.append(token)
                offsets.append(tokenStart)
            case .failure(let error): return .failure(error)
            }
        }
    }

    private mutating func nextToken(leadingTrivia: Trivia) -> Result<Token, ParseError> {
        let start = position
        let byte = buffer[position]
        let punctuation: TokenKind?
        switch byte {
        case 0x7B: punctuation = .leftBrace
        case 0x7D: punctuation = .rightBrace
        case 0x28: punctuation = .leftParen
        case 0x29: punctuation = .rightParen
        case 0x3D: punctuation = .equals
        case 0x3B: punctuation = .semicolon
        case 0x2C: punctuation = .comma
        default: punctuation = nil
        }
        if let punctuation {
            position += 1
            return .success(.punctuation(punctuation, leadingTrivia: leadingTrivia))
        }
        if byte == 0x22 || byte == 0x27 { return quotedString(leadingTrivia: leadingTrivia) }
        if byte == 0x3C { return dataLiteral(leadingTrivia: leadingTrivia) }
        if Lexer.isBareStringByte(byte) {
            while position < buffer.count, Lexer.isBareStringByte(buffer[position]) { position += 1 }
            let text = TriviaScanner.string(buffer, start, position)
            return .success(Token(kind: .bareString, text: text, leadingTrivia: leadingTrivia))
        }
        return .failure(
            ParseError(
                kind: .unexpectedCharacter, at: position, in: buffer,
                expected: "a string, '{', '(', '<' or punctuation; an unquoted string may hold only letters, digits and _ $ / : . -"
            ))
    }

    /// CoreFoundation's old-style set (design D5, read side).
    static func isBareStringByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true  // 0-9 A-Z a-z
        case 0x5F, 0x24, 0x2F, 0x3A, 0x2E, 0x2D: return true  // _ $ / : . -
        default: return false
        }
    }

    private mutating func quotedString(leadingTrivia: Trivia) -> Result<Token, ParseError> {
        let start = position
        let quote = buffer[position]
        position += 1
        while position < buffer.count {
            let byte = buffer[position]
            if byte == quote {
                position += 1
                let text = TriviaScanner.string(buffer, start, position)
                return .success(Token(kind: .quotedString, text: text, leadingTrivia: leadingTrivia))
            }
            // A backslash escapes the next byte, whatever it is.
            position += byte == 0x5C ? 2 : 1
        }
        position = buffer.count
        let quoteText = quote == 0x22 ? "'\"'" : "\"'\""
        return .failure(
            ParseError(
                kind: .unterminatedString, at: start, in: buffer,
                expected: "\(quoteText) to close the string opened here", found: "end of input"))
    }

    private mutating func dataLiteral(leadingTrivia: Trivia) -> Result<Token, ParseError> {
        let start = position
        position += 1
        var digits = 0
        while position < buffer.count {
            let byte = buffer[position]
            if byte == 0x3E {
                position += 1
                guard digits % 2 == 0 else {
                    return .failure(
                        ParseError(
                            kind: .malformedData, at: start, in: buffer,
                            expected: "an even number of hexadecimal digits in the data literal opened here",
                            found: "\(digits) digits"))
                }
                let text = TriviaScanner.string(buffer, start, position)
                return .success(Token(kind: .data, text: text, leadingTrivia: leadingTrivia))
            }
            if Lexer.isHexDigit(byte) {
                digits += 1
            } else if !TriviaScanner.isWhitespace(byte) {
                return .failure(
                    ParseError(
                        kind: .malformedData, at: position, in: buffer,
                        expected: "a hexadecimal digit or '>' in a data literal"))
            }
            position += 1
        }
        return .failure(
            ParseError(
                kind: .malformedData, at: start, in: buffer,
                expected: "'>' to close the data literal opened here", found: "end of input"))
    }

    static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x46, 0x61...0x66: return true
        default: return false
        }
    }
}

/// Checks made once, before lexing (design D4): the input is not another
/// property-list format, and it is valid UTF-8.
enum InputChecks {
    static func firstProblem(in buffer: UnsafeBufferPointer<UInt8>) -> ParseError? {
        // The format check comes first: a binary property list is usually
        // not valid UTF-8, and "binary" is the more useful thing to say.
        if let format = unsupportedFormat(in: buffer) { return format }
        if let offset = firstInvalidUTF8Offset(in: buffer) {
            return ParseError(
                kind: .invalidUTF8, at: offset, in: buffer, expected: "valid UTF-8",
                found: "byte 0x" + ParseError.hex(UInt32(buffer[offset]), width: 2))
        }
        return nil
    }

    private static func unsupportedFormat(in buffer: UnsafeBufferPointer<UInt8>) -> ParseError? {
        if hasPrefix("bplist", in: buffer, at: 0) {
            return ParseError(
                kind: .unsupportedFormat(.binary), at: 0, in: buffer,
                expected: "an old-style ASCII property list",
                found: "a binary property list, which is not supported")
        }
        var start = 0
        if hasPrefix("\u{FEFF}", in: buffer, at: 0) { start = 3 }
        start = TriviaScanner.whitespaceEnd(in: buffer, from: start)
        for marker in ["<?xml", "<!DOCTYPE", "<plist"] where hasPrefix(marker, in: buffer, at: start) {
            return ParseError(
                kind: .unsupportedFormat(.xml), at: start, in: buffer,
                expected: "an old-style ASCII property list",
                found: "an XML property list, which is not supported")
        }
        return nil
    }

    private static func hasPrefix(_ prefix: String, in buffer: UnsafeBufferPointer<UInt8>, at start: Int) -> Bool {
        var position = start
        for byte in prefix.utf8 {
            guard position < buffer.count, buffer[position] == byte else { return false }
            position += 1
        }
        return true
    }

    /// The offset of the first byte that is not part of a well-formed UTF-8
    /// sequence (Unicode 15, table 3-7), or `nil` when the input is valid.
    static func firstInvalidUTF8Offset(in buffer: UnsafeBufferPointer<UInt8>) -> Int? {
        var position = 0
        let count = buffer.count
        while position < count {
            let first = buffer[position]
            if first < 0x80 {
                position += 1
                continue
            }
            let length: Int
            var secondRange: ClosedRange<UInt8> = 0x80...0xBF
            switch first {
            case 0xC2...0xDF: length = 2
            case 0xE0: length = 3; secondRange = 0xA0...0xBF
            case 0xE1...0xEC, 0xEE...0xEF: length = 3
            case 0xED: length = 3; secondRange = 0x80...0x9F
            case 0xF0: length = 4; secondRange = 0x90...0xBF
            case 0xF1...0xF3: length = 4
            case 0xF4: length = 4; secondRange = 0x80...0x8F
            default: return position
            }
            guard position + length <= count, secondRange.contains(buffer[position + 1]) else { return position }
            var index = 2
            while index < length {
                guard buffer[position + index] & 0xC0 == 0x80 else { return position }
                index += 1
            }
            position += length
        }
        return nil
    }
}
