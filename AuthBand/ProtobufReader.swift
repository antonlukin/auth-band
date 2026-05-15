import Foundation

struct ProtobufReader {
    enum WireType: Int {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    struct Field {
        let number: Int
        let wireType: WireType
    }

    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        bytes = Array(data)
    }

    var isAtEnd: Bool {
        offset >= bytes.count
    }

    mutating func readField() throws -> Field {
        let key = try readVarint()
        let number = Int(key >> 3)
        let wireValue = Int(key & 0x07)

        guard number > 0, let wireType = WireType(rawValue: wireValue) else {
            throw OTPImportError.invalidMigrationData
        }

        return Field(number: number, wireType: wireType)
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while shift < 64 {
            guard offset < bytes.count else {
                throw OTPImportError.invalidMigrationData
            }

            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift

            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
        }

        throw OTPImportError.invalidMigrationData
    }

    mutating func readLengthDelimitedData() throws -> Data {
        let length = Int(try readVarint())
        guard length >= 0, offset + length <= bytes.count else {
            throw OTPImportError.invalidMigrationData
        }

        let value = Data(bytes[offset..<offset + length])
        offset += length
        return value
    }

    mutating func readLengthDelimitedString() throws -> String {
        let data = try readLengthDelimitedData()

        guard let value = String(data: data, encoding: .utf8) else {
            throw OTPImportError.invalidMigrationData
        }

        return value
    }

    mutating func skipField(wireType: WireType) throws {
        switch wireType {
        case .varint:
            _ = try readVarint()
        case .fixed64:
            try skipBytes(8)
        case .lengthDelimited:
            _ = try readLengthDelimitedData()
        case .fixed32:
            try skipBytes(4)
        }
    }

    private mutating func skipBytes(_ count: Int) throws {
        guard count >= 0, offset + count <= bytes.count else {
            throw OTPImportError.invalidMigrationData
        }

        offset += count
    }
}
