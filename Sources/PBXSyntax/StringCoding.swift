/// Decoding of quoted strings, and canonical quoting on write (design D5).
enum StringCoding {
    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }

    /// Decodes the raw text of a quoted-string token, quotes included.
    ///
    /// Follows CoreFoundation's old-style reader: `\a \b \f \n \r \t \v`, a
    /// backslash before a line break, `\U` with four hexadecimal digits as one
    /// UTF-16 unit, up to three octal digits, and any other escaped character
    /// standing for itself. One divergence: CoreFoundation maps octal escapes
    /// of 0o200 and above through the NeXTSTEP encoding; here they decode to
    /// the scalar with that value.
    static func decodeQuoted(_ raw: String) -> String {
        let bytes = Array(raw.utf8)
        guard bytes.count >= 2 else { return "" }
        var units: [UInt16] = []
        var plain: [UInt8] = []
        func flushPlain() {
            if plain.isEmpty { return }
            units.append(contentsOf: String(decoding: plain, as: UTF8.self).utf16)
            plain.removeAll(keepingCapacity: true)
        }
        var position = 1
        let end = bytes.count - 1
        while position < end {
            let byte = bytes[position]
            guard byte == 0x5C, position + 1 < end else {
                plain.append(byte)
                position += 1
                continue
            }
            flushPlain()
            let escaped = bytes[position + 1]
            position += 2
            switch escaped {
            case 0x61: units.append(0x07)  // \a
            case 0x62: units.append(0x08)  // \b
            case 0x66: units.append(0x0C)  // \f
            case 0x6E: units.append(0x0A)  // \n
            case 0x72: units.append(0x0D)  // \r
            case 0x74: units.append(0x09)  // \t
            case 0x76: units.append(0x0B)  // \v
            case 0x55:  // \Uxxxx
                var value: UInt16 = 0
                var digits = 0
                while digits < 4, position + digits < end, let nibble = hexValue(bytes[position + digits]) {
                    value = value << 4 | UInt16(nibble)
                    digits += 1
                }
                if digits == 4 {
                    units.append(value)
                    position += 4
                } else {
                    units.append(0x55)
                }
            case 0x30...0x37:  // up to three octal digits
                var value = UInt16(escaped - 0x30)
                var digits = 1
                while digits < 3, position < end, bytes[position] >= 0x30, bytes[position] <= 0x37 {
                    value = value << 3 | UInt16(bytes[position] - 0x30)
                    position += 1
                    digits += 1
                }
                units.append(value)
            default:
                // Any other character stands for itself; keep multi-byte
                // sequences whole by handing the byte back to the plain run.
                plain.append(escaped)
            }
        }
        flushPlain()
        return String(decoding: units, as: UTF16.self)
    }

    /// Design D5, write side: a string stays bare only if it is non-empty,
    /// holds nothing but ASCII letters, digits and `_ $ / .`, and contains
    /// neither `//` nor `___`.
    static func needsQuoting(_ value: String) -> Bool {
        if value.utf8.isEmpty { return true }
        var slashes = 0
        var underscores = 0
        for byte in value.utf8 {
            switch byte {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x24, 0x2E:
                slashes = 0
                underscores = 0
            case 0x2F:
                slashes += 1
                underscores = 0
                if slashes == 2 { return true }
            case 0x5F:
                underscores += 1
                slashes = 0
                if underscores == 3 { return true }
            default:
                return true
            }
        }
        return false
    }

    /// The token that writes `value` with canonical quoting.
    static func token(for value: String, leadingTrivia: Trivia) -> Token {
        guard needsQuoting(value) else {
            return Token(kind: .bareString, text: value, leadingTrivia: leadingTrivia)
        }
        var text: [UInt8] = [0x22]
        for byte in value.utf8 {
            switch byte {
            case 0x22: text.append(contentsOf: [0x5C, 0x22])
            case 0x5C: text.append(contentsOf: [0x5C, 0x5C])
            case 0x0A: text.append(contentsOf: [0x5C, 0x6E])
            case 0x09: text.append(contentsOf: [0x5C, 0x74])
            case 0x0D: text.append(contentsOf: [0x5C, 0x72])
            case 0x00...0x1F, 0x7F:
                text.append(contentsOf: Array(("\\U" + ParseError.hex(UInt32(byte), width: 4).lowercased()).utf8))
            default:
                // Multi-byte UTF-8 is written as it is, as Xcode does.
                text.append(byte)
            }
        }
        text.append(0x22)
        return Token(kind: .quotedString, text: String(decoding: text, as: UTF8.self), leadingTrivia: leadingTrivia)
    }
}

extension StringNode {
    /// `value` as the write side of design D5 spells it: bare when it may
    /// be, else quoted with escapes. For reports that print values.
    public static func canonicalText(_ value: String) -> String {
        StringCoding.token(for: value, leadingTrivia: .empty).text
    }
}
