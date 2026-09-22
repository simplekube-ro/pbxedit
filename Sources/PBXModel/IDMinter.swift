/// Mints object IDs (design D7): 24 uppercase hexadecimal characters, drawn
/// from a random number generator and checked against the project and
/// against everything minted earlier by the same minter.
public struct IDMinter {
    private var generator: any RandomNumberGenerator
    private var minted: Set<ObjectID> = []

    /// Mints from the system generator.
    public init() {
        self.init(generator: SystemRandomNumberGenerator())
    }

    /// Mints from `generator`; tests pass a seeded or scripted one. The
    /// generator must eventually yield fresh values, as any real one does.
    public init(generator: some RandomNumberGenerator) {
        self.generator = generator
    }

    /// Everything minted so far, so a caller can tell a fresh ID from an old one.
    public var mintedIDs: Set<ObjectID> { minted }

    /// A new ID that is in neither `project` nor this minter's history.
    public mutating func mint(for project: Project) -> ObjectID {
        while true {
            let id = ObjectID(IDMinter.hex(high: generator.next(), low: generator.next()))
            if !project.contains(id), !minted.contains(id) {
                minted.insert(id)
                return id
            }
        }
    }

    /// Twelve bytes as uppercase hex: all of `high`, then the low four bytes of `low`.
    static func hex(high: UInt64, low: UInt64) -> String {
        let digits = Array("0123456789ABCDEF".utf8)
        var text: [UInt8] = []
        text.reserveCapacity(24)
        func append(_ byte: UInt64) {
            text.append(digits[Int((byte >> 4) & 0xF)])
            text.append(digits[Int(byte & 0xF)])
        }
        for shift in stride(from: 56, through: 0, by: -8) { append(high >> UInt64(shift)) }
        for shift in stride(from: 24, through: 0, by: -8) { append(low >> UInt64(shift)) }
        return String(decoding: text, as: UTF8.self)
    }
}
