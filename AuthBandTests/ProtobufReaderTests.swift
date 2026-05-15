import Foundation
import Testing

@testable import AuthBand

struct ProtobufReaderTests {
    @Test("Single-byte varint (< 128) reads as-is", arguments: [UInt64(0), 1, 42, 127])
    func readSingleByteVarint(value: UInt64) throws {
        var reader = ProtobufReader(data: Data([UInt8(value)]))
        #expect(try reader.readVarint() == value)
        #expect(reader.isAtEnd)
    }

    @Test("Multi-byte varint decodes 128 from [0x80, 0x01]")
    func readMultiByteVarint128() throws {
        var reader = ProtobufReader(data: Data([0x80, 0x01]))
        #expect(try reader.readVarint() == 128)
    }

    @Test("Multi-byte varint decodes 300 from [0xAC, 0x02]")
    func readMultiByteVarint300() throws {
        var reader = ProtobufReader(data: Data([0xAC, 0x02]))
        #expect(try reader.readVarint() == 300)
    }

    @Test("readField parses (field number, wire type) from a tag byte")
    func readFieldParsesTag() throws {
        // Field 3, wire type 2 (length-delimited) → tag byte = (3 << 3) | 2 = 26 = 0x1A
        var reader = ProtobufReader(data: Data([0x1A]))
        let field = try reader.readField()
        #expect(field.number == 3)
        #expect(field.wireType == .lengthDelimited)
    }

    @Test("Field number 0 in tag throws invalidMigrationData")
    func fieldNumberZeroFails() {
        var reader = ProtobufReader(data: Data([0x00]))
        #expect(throws: OTPImportError.invalidMigrationData) {
            _ = try reader.readField()
        }
    }

    @Test("Invalid wire type (3 = StartGroup, deprecated/unsupported here) throws")
    func invalidWireTypeFails() {
        // Field 1, wire type 3 → 0x0B
        var reader = ProtobufReader(data: Data([0x0B]))
        #expect(throws: OTPImportError.invalidMigrationData) {
            _ = try reader.readField()
        }
    }

    @Test("Truncated varint (continuation bit set, no more bytes) throws")
    func truncatedVarintFails() {
        var reader = ProtobufReader(data: Data([0x80])) // continuation bit set, no follow-up
        #expect(throws: OTPImportError.invalidMigrationData) {
            _ = try reader.readVarint()
        }
    }

    @Test("Length-delimited read past end throws")
    func truncatedLengthDelimitedFails() {
        // length=10, but only 3 bytes follow
        var reader = ProtobufReader(data: Data([0x0A, 0x01, 0x02]))
        #expect(throws: OTPImportError.invalidMigrationData) {
            _ = try reader.readLengthDelimitedData()
        }
    }

    @Test("Length-delimited string with invalid UTF-8 throws")
    func invalidUTF8StringFails() {
        // length=2, then bytes 0xC3 0x28 (invalid UTF-8 sequence)
        var reader = ProtobufReader(data: Data([0x02, 0xC3, 0x28]))
        #expect(throws: OTPImportError.invalidMigrationData) {
            _ = try reader.readLengthDelimitedString()
        }
    }

    @Test("Length-delimited string roundtrips UTF-8")
    func lengthDelimitedStringRoundtrips() throws {
        let s = "héllo"
        let bytes = Array(s.utf8)
        var reader = ProtobufReader(data: Data([UInt8(bytes.count)] + bytes))
        #expect(try reader.readLengthDelimitedString() == s)
    }

    @Test("skipField skips a varint")
    func skipFieldVarint() throws {
        // varint 300 (2 bytes) followed by varint 7
        var reader = ProtobufReader(data: Data([0xAC, 0x02, 0x07]))
        try reader.skipField(wireType: .varint)
        #expect(try reader.readVarint() == 7)
    }

    @Test("skipField skips a length-delimited block")
    func skipFieldLengthDelimited() throws {
        // length=3, "abc", then varint 9
        var reader = ProtobufReader(data: Data([0x03, 0x61, 0x62, 0x63, 0x09]))
        try reader.skipField(wireType: .lengthDelimited)
        #expect(try reader.readVarint() == 9)
    }

    @Test("skipField skips fixed64 (8 bytes)")
    func skipFieldFixed64() throws {
        var reader = ProtobufReader(data: Data([0, 0, 0, 0, 0, 0, 0, 0, 0x05]))
        try reader.skipField(wireType: .fixed64)
        #expect(try reader.readVarint() == 5)
    }

    @Test("skipField skips fixed32 (4 bytes)")
    func skipFieldFixed32() throws {
        var reader = ProtobufReader(data: Data([0, 0, 0, 0, 0x05]))
        try reader.skipField(wireType: .fixed32)
        #expect(try reader.readVarint() == 5)
    }

    @Test("isAtEnd transitions from false to true after consuming all bytes")
    func isAtEndTransitions() throws {
        var reader = ProtobufReader(data: Data([0x05]))
        #expect(!reader.isAtEnd)
        _ = try reader.readVarint()
        #expect(reader.isAtEnd)
    }

    @Test("Empty data is at end immediately")
    func emptyIsAtEnd() {
        let reader = ProtobufReader(data: Data())
        #expect(reader.isAtEnd)
    }
}
