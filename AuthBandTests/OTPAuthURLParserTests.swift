import Foundation
import Testing

@testable import AuthBand

struct OTPAuthURLParserTests {
    private func parse(_ url: String) throws -> OTPAccount {
        guard let components = URLComponents(string: url) else {
            Issue.record("URLComponents could not parse \(url)")
            throw OTPImportError.invalidURL
        }
        return try OTPAuthURLParser.parse(components)
    }

    // MARK: - Happy paths

    @Test("Issuer query + label 'Issuer:Account' produces both fields")
    func issuerQueryAndLabel() throws {
        let account = try parse("otpauth://totp/Google:alice@gmail.com?secret=JBSWY3DPEHPK3PXP&issuer=Google")
        #expect(account.issuer == "Google")
        #expect(account.name == "alice@gmail.com")
        #expect(account.secret == "JBSWY3DPEHPK3PXP")
        #expect(account.digits == 6)
        #expect(account.period == 30)
    }

    @Test("Label 'Issuer:Account' without issuer query — issuer comes from label")
    func labelWithoutIssuerQuery() throws {
        let account = try parse("otpauth://totp/GitHub:bob?secret=JBSWY3DPEHPK3PXP")
        #expect(account.issuer == "GitHub")
        #expect(account.name == "bob")
    }

    @Test("Label without colon — issuer is the whole label, name is empty")
    func issuerOnlyLabel() throws {
        let account = try parse("otpauth://totp/Dropbox?secret=JBSWY3DPEHPK3PXP")
        #expect(account.issuer == "Dropbox")
        #expect(account.name == "")
    }

    @Test("Issuer query overrides issuer from label, name still comes from label")
    func issuerQueryOverridesLabel() throws {
        let account = try parse("otpauth://totp/WrongIssuer:alice?secret=JBSWY3DPEHPK3PXP&issuer=RightIssuer")
        #expect(account.issuer == "RightIssuer")
        #expect(account.name == "alice")
    }

    @Test("Custom digits=8 is respected")
    func customDigits() throws {
        let account = try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&digits=8")
        #expect(account.digits == 8)
    }

    @Test("Custom period=60 is respected")
    func customPeriod() throws {
        let account = try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&period=60")
        #expect(account.period == 60)
    }

    @Test("Algorithm=SHA1 is accepted in any case", arguments: ["SHA1", "sha1", "Sha1"])
    func algorithmSHA1Accepted(value: String) throws {
        let account = try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&algorithm=\(value)")
        #expect(account.issuer == "X")
    }

    @Test("Scheme and host are case-insensitive")
    func schemeCaseInsensitive() throws {
        let account = try parse("OTPAUTH://TOTP/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X")
        #expect(account.issuer == "X")
        #expect(account.name == "y")
    }

    @Test("Percent-encoded label characters are decoded")
    func urlEncodedLabel() throws {
        let account = try parse("otpauth://totp/My%20Service:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=My%20Service")
        #expect(account.issuer == "My Service")
        #expect(account.name == "alice@example.com")
    }

    @Test("Lowercase Base32 secret is normalized to uppercase")
    func secretLowercaseNormalized() throws {
        let account = try parse("otpauth://totp/X:y?secret=jbswy3dpehpk3pxp&issuer=X")
        #expect(account.secret == "JBSWY3DPEHPK3PXP")
    }

    // MARK: - Errors

    @Test("Wrong host (hotp) throws invalidURL")
    func wrongHostFails() {
        #expect(throws: OTPImportError.invalidURL) {
            try parse("otpauth://hotp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X")
        }
    }

    @Test("Missing secret query throws missingSecret")
    func missingSecretFails() {
        #expect(throws: OTPImportError.missingSecret) {
            try parse("otpauth://totp/X:y?issuer=X")
        }
    }

    @Test("Empty secret value throws invalidSecret")
    func emptySecretFails() {
        #expect(throws: OTPImportError.invalidSecret) {
            try parse("otpauth://totp/X:y?secret=&issuer=X")
        }
    }

    @Test("Non-Base32 secret throws invalidSecret")
    func invalidBase32Fails() {
        #expect(throws: OTPImportError.invalidSecret) {
            try parse("otpauth://totp/X:y?secret=NOTBASE32!!!&issuer=X")
        }
    }

    @Test("Algorithm=SHA256 throws unsupportedAlgorithm")
    func unsupportedAlgorithmFails() {
        #expect(throws: OTPImportError.unsupportedAlgorithm) {
            try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&algorithm=SHA256")
        }
    }

    @Test("Empty path with no issuer query throws missingIssuer")
    func emptyIssuerFails() {
        #expect(throws: OTPImportError.missingIssuer) {
            try parse("otpauth://totp/?secret=JBSWY3DPEHPK3PXP")
        }
    }

    @Test("Whitespace-only label and no issuer query throws missingIssuer")
    func whitespaceIssuerFails() {
        #expect(throws: OTPImportError.missingIssuer) {
            try parse("otpauth://totp/%20%20?secret=JBSWY3DPEHPK3PXP")
        }
    }

    @Test("Out-of-range digits values throw invalidDigits", arguments: ["0", "1", "5", "9", "10", "32", "-1", "abc"])
    func invalidDigitsFails(value: String) {
        #expect(throws: OTPImportError.invalidDigits) {
            try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&digits=\(value)")
        }
    }

    @Test("digits=7 is accepted (HOTP/RFC 4226 allows 6–8)")
    func sevenDigitsAccepted() throws {
        let account = try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&digits=7")
        #expect(account.digits == 7)
    }

    @Test("Out-of-range period values throw invalidPeriod", arguments: ["0", "-1", "5", "14", "301", "999999", "abc"])
    func invalidPeriodFails(value: String) {
        #expect(throws: OTPImportError.invalidPeriod) {
            try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&period=\(value)")
        }
    }

    @Test("Boundary periods (15s and 300s) are accepted", arguments: [15, 300])
    func boundaryPeriodsAccepted(value: Int) throws {
        let account = try parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X&period=\(value)")
        #expect(account.period == TimeInterval(value))
    }
}

@Suite("OTPQRCodeParser dispatch")
struct OTPQRCodeParserTests {
    @Test("otpauth:// dispatches to singleAccount")
    func otpauthDispatch() throws {
        let result = try OTPQRCodeParser.parse("otpauth://totp/X:y?secret=JBSWY3DPEHPK3PXP&issuer=X")
        guard case .singleAccount(let account) = result else {
            Issue.record("Expected singleAccount, got \(result)")
            return
        }
        #expect(account.issuer == "X")
    }

    @Test("Unknown scheme throws invalidURL")
    func unknownSchemeFails() {
        #expect(throws: OTPImportError.invalidURL) {
            try OTPQRCodeParser.parse("https://example.com/?secret=JBSWY3DPEHPK3PXP")
        }
    }

    @Test("Malformed URL string (raw space) throws invalidURL")
    func malformedURLFails() {
        #expect(throws: OTPImportError.invalidURL) {
            try OTPQRCodeParser.parse("not a url")
        }
    }
}
