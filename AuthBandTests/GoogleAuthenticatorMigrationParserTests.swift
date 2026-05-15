import Foundation
import Testing

@testable import AuthBand

// Wire format reminder for Google Authenticator's MigrationPayload protobuf:
// MigrationPayload { repeated OtpParameters otp_parameters = 1; }
// OtpParameters {
//     bytes  secret    = 1;
//     string name      = 2;
//     string issuer    = 3;
//     int32  algorithm = 4;  // 1 = SHA1
//     int32  digits    = 5;  // 1 = SIX, 2 = EIGHT
//     int32  type      = 6;  // 1 = HOTP, 2 = TOTP
// }

struct GoogleAuthenticatorMigrationParserTests {
    // MARK: - URL-level errors

    @Test("Wrong scheme throws invalidURL")
    func wrongScheme() {
        #expect(throws: OTPImportError.invalidURL) {
            try GoogleAuthenticatorMigrationParser.parse(URLComponents(string: "otpauth://totp/X")!)
        }
    }

    @Test("Wrong host throws invalidURL")
    func wrongHost() {
        #expect(throws: OTPImportError.invalidURL) {
            try GoogleAuthenticatorMigrationParser.parse(URLComponents(string: "otpauth-migration://online?data=AA")!)
        }
    }

    @Test("Missing data query throws missingMigrationData")
    func missingDataParam() {
        #expect(throws: OTPImportError.missingMigrationData) {
            try GoogleAuthenticatorMigrationParser.parse(URLComponents(string: "otpauth-migration://offline")!)
        }
    }

    @Test("Garbage data param (not base64) throws invalidMigrationData")
    func garbageData() {
        #expect(throws: OTPImportError.invalidMigrationData) {
            try parseURL(rawData: "!!!not_base64!!!")
        }
    }

    @Test("Truncated protobuf payload throws invalidMigrationData")
    func truncatedPayload() {
        // Tag for field 1 length-delimited (0x0A), claims 100 bytes, gives only 1
        let data = Data([0x0A, 0x64, 0x01])
        #expect(throws: OTPImportError.invalidMigrationData) {
            try parseURL(payload: data)
        }
    }

    @Test("Empty (well-formed) payload with no accounts throws noSupportedAccounts")
    func emptyPayloadFails() {
        #expect(throws: OTPImportError.noSupportedAccounts) {
            try parseURL(payload: Data())
        }
    }

    // MARK: - Happy paths

    @Test("Single TOTP/SHA1/6-digit account is parsed")
    func singleAccount() throws {
        let params = otpParameters(
            secret: rfcSecretBytes,
            label: "Google:alice@gmail.com",
            issuer: "Google"
        )
        let accounts = try parseURL(payload: migrationPayload(params))

        #expect(accounts.count == 1)
        let account = try #require(accounts.first)
        #expect(account.issuer == "Google")
        #expect(account.name == "alice@gmail.com")
        #expect(account.secret == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        #expect(account.digits == 6)
        #expect(account.period == 30)
    }

    @Test("Two accounts in one payload are both returned")
    func twoAccounts() throws {
        let a = otpParameters(secret: rfcSecretBytes, label: "Google:alice", issuer: "Google")
        let b = otpParameters(secret: rfcSecretBytes, label: "GitHub:bob",  issuer: "GitHub")
        let accounts = try parseURL(payload: migrationPayload(a, b))

        #expect(accounts.count == 2)
        #expect(accounts.map(\.issuer) == ["Google", "GitHub"])
        #expect(accounts.map(\.name)   == ["alice", "bob"])
    }

    @Test("digits=2 produces an 8-digit account")
    func eightDigitAccount() throws {
        let params = otpParameters(secret: rfcSecretBytes, label: "X:y", issuer: "X", digits: 2)
        let accounts = try parseURL(payload: migrationPayload(params))
        let account = try #require(accounts.first)
        #expect(account.digits == 8)
    }

    @Test("Issuer field overrides label-issuer")
    func issuerFieldWins() throws {
        let params = otpParameters(secret: rfcSecretBytes, label: "WrongName:alice", issuer: "RightName")
        let accounts = try parseURL(payload: migrationPayload(params))
        let account = try #require(accounts.first)
        #expect(account.issuer == "RightName")
        #expect(account.name == "alice")
    }

    @Test("Empty issuer field falls back to label issuer")
    func issuerFromLabel() throws {
        let params = otpParameters(secret: rfcSecretBytes, label: "Google:alice", issuer: "")
        let accounts = try parseURL(payload: migrationPayload(params))
        let account = try #require(accounts.first)
        #expect(account.issuer == "Google")
        #expect(account.name == "alice")
    }

    @Test("Single-token label with no issuer field becomes issuer with empty name")
    func singleTokenLabel() throws {
        let params = otpParameters(secret: rfcSecretBytes, label: "Dropbox", issuer: "")
        let accounts = try parseURL(payload: migrationPayload(params))
        let account = try #require(accounts.first)
        #expect(account.issuer == "Dropbox")
        #expect(account.name == "")
    }

    @Test("Base64URL chars in encoded data (- and _) round-trip")
    func base64URLChars() throws {
        // Pick bytes whose standard base64 contains '+' and '/' so the URL-safe form uses '-' and '_'.
        // 0xFB 0xEF has standard base64 "++8=" → URL-safe "--8".
        let secret = Data([0xFB, 0xEF, 0xFF, 0xFC, 0x00, 0xFF, 0xFB, 0xEF, 0xFF, 0xFC])
        let params = otpParameters(secret: secret, label: "X", issuer: "X")
        let accounts = try parseURL(payload: migrationPayload(params))
        let account = try #require(accounts.first)
        #expect(account.issuer == "X")
        // Verify the secret round-trips through Base32 encode/decode unchanged
        #expect(account.secret == TOTPGenerator.base32EncodedSecret(secret))
    }

    // MARK: - Filtering (these are silently skipped, not errors)

    @Test("HOTP account (type=1) is filtered out")
    func hotpFiltered() {
        let params = otpParameters(secret: rfcSecretBytes, label: "X:y", issuer: "X", type: 1)
        #expect(throws: OTPImportError.noSupportedAccounts) {
            try parseURL(payload: migrationPayload(params))
        }
    }

    @Test("SHA256 account (algorithm=2) is filtered out")
    func sha256Filtered() {
        let params = otpParameters(secret: rfcSecretBytes, label: "X:y", issuer: "X", algorithm: 2)
        #expect(throws: OTPImportError.noSupportedAccounts) {
            try parseURL(payload: migrationPayload(params))
        }
    }

    @Test("Account with empty secret is filtered out")
    func emptySecretFiltered() {
        let params = otpParameters(secret: Data(), label: "X:y", issuer: "X")
        #expect(throws: OTPImportError.noSupportedAccounts) {
            try parseURL(payload: migrationPayload(params))
        }
    }

    @Test("Account with empty issuer and empty label is filtered out")
    func emptyIssuerFiltered() {
        let params = otpParameters(secret: rfcSecretBytes, label: "", issuer: "")
        #expect(throws: OTPImportError.noSupportedAccounts) {
            try parseURL(payload: migrationPayload(params))
        }
    }

    @Test("Mixed payload — bad accounts are skipped, good ones are kept")
    func mixedPayloadSkipsBadAccounts() throws {
        let bad = otpParameters(secret: rfcSecretBytes, label: "X:y", issuer: "X", type: 1) // HOTP
        let good = otpParameters(secret: rfcSecretBytes, label: "Good:z", issuer: "Good")
        let accounts = try parseURL(payload: migrationPayload(bad, good))

        #expect(accounts.count == 1)
        #expect(accounts.first?.issuer == "Good")
    }

    @Test("Unknown outer protobuf field is skipped without error")
    func unknownOuterFieldIsSkipped() throws {
        // A proper otp_parameters at field 1 + an unknown varint at field 99
        let params = otpParameters(secret: rfcSecretBytes, label: "X:y", issuer: "X")

        var bytes: [UInt8] = []
        appendLengthDelimited(field: 1, value: params, into: &bytes)
        // Field 99, wire type 0 (varint): tag = (99 << 3) | 0 = 792 → varint 0x98 0x06
        bytes.append(contentsOf: [0x98, 0x06, 0x2A])

        let accounts = try parseURL(payload: Data(bytes))
        #expect(accounts.count == 1)
    }

    // MARK: - Helpers

    private let rfcSecretBytes = Data("12345678901234567890".utf8)

    private func parseURL(payload: Data) throws -> [OTPAccount] {
        try parseURL(rawData: base64URLEncode(payload))
    }

    private func parseURL(rawData: String) throws -> [OTPAccount] {
        var components = URLComponents()
        components.scheme = "otpauth-migration"
        components.host = "offline"
        components.queryItems = [URLQueryItem(name: "data", value: rawData)]
        return try GoogleAuthenticatorMigrationParser.parse(components)
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // Builds an OtpParameters submessage payload (field 1: secret, 2: name, 3: issuer, 4-6: varints).
    private func otpParameters(
        secret: Data,
        label: String,
        issuer: String,
        algorithm: Int = 1,
        digits: Int = 1,
        type: Int = 2
    ) -> Data {
        var bytes: [UInt8] = []
        appendLengthDelimited(field: 1, value: secret, into: &bytes)
        appendLengthDelimited(field: 2, value: Data(label.utf8), into: &bytes)
        appendLengthDelimited(field: 3, value: Data(issuer.utf8), into: &bytes)
        appendVarintField(field: 4, value: UInt64(algorithm), into: &bytes)
        appendVarintField(field: 5, value: UInt64(digits), into: &bytes)
        appendVarintField(field: 6, value: UInt64(type), into: &bytes)
        return Data(bytes)
    }

    // Builds the outer MigrationPayload by concatenating each OtpParameters at field 1.
    private func migrationPayload(_ otpParameters: Data...) -> Data {
        var bytes: [UInt8] = []
        for params in otpParameters {
            appendLengthDelimited(field: 1, value: params, into: &bytes)
        }
        return Data(bytes)
    }

    // MARK: - Low-level wire-format helpers

    private func appendLengthDelimited(field: Int, value: Data, into bytes: inout [UInt8]) {
        appendTag(field: field, wireType: 2, into: &bytes)
        appendVarint(UInt64(value.count), into: &bytes)
        bytes.append(contentsOf: value)
    }

    private func appendVarintField(field: Int, value: UInt64, into bytes: inout [UInt8]) {
        appendTag(field: field, wireType: 0, into: &bytes)
        appendVarint(value, into: &bytes)
    }

    private func appendTag(field: Int, wireType: Int, into bytes: inout [UInt8]) {
        appendVarint(UInt64((field << 3) | wireType), into: &bytes)
    }

    private func appendVarint(_ value: UInt64, into bytes: inout [UInt8]) {
        var v = value
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7f) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }
}
