import Foundation
import Testing

@testable import AuthBand

struct TOTPGeneratorTests {
    // RFC 6238 Appendix B test vectors with the 20-byte ASCII secret "12345678901234567890".
    private static let rfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    @Test("RFC 6238 — 6-digit codes", arguments: [
        (TimeInterval(59),          "287082"),
        (TimeInterval(1111111109),  "081804"),
        (TimeInterval(1111111111),  "050471"),
        (TimeInterval(1234567890),  "005924"),
        (TimeInterval(2000000000),  "279037"),
    ])
    func rfc6238SixDigit(time: TimeInterval, expected: String) {
        let account = OTPAccount(
            issuer: "RFC",
            name: "test",
            secret: Self.rfcSecret,
            digits: 6,
            period: 30
        )
        let code = TOTPGenerator().code(for: account, at: Date(timeIntervalSince1970: time))
        #expect(code == expected)
    }

    @Test("RFC 6238 — 8-digit codes", arguments: [
        (TimeInterval(59),          "94287082"),
        (TimeInterval(1111111109),  "07081804"),
        (TimeInterval(1111111111),  "14050471"),
        (TimeInterval(1234567890),  "89005924"),
        (TimeInterval(2000000000),  "69279037"),
    ])
    func rfc6238EightDigit(time: TimeInterval, expected: String) {
        let account = OTPAccount(
            issuer: "RFC",
            name: "test",
            secret: Self.rfcSecret,
            digits: 8,
            period: 30
        )
        let code = TOTPGenerator().code(for: account, at: Date(timeIntervalSince1970: time))
        #expect(code == expected)
    }

    @Test("Code is stable across the same 30-second window")
    func codeStableInsideWindow() {
        let account = OTPAccount(issuer: "X", name: "y", secret: Self.rfcSecret)
        let generator = TOTPGenerator()

        let start = Date(timeIntervalSince1970: 60)
        let middle = Date(timeIntervalSince1970: 75)
        let end = Date(timeIntervalSince1970: 89.999)

        let codeStart = generator.code(for: account, at: start)
        #expect(generator.code(for: account, at: middle) == codeStart)
        #expect(generator.code(for: account, at: end) == codeStart)
    }

    @Test("Code rolls over at the next 30-second boundary")
    func codeRollsOver() {
        let account = OTPAccount(issuer: "X", name: "y", secret: Self.rfcSecret)
        let generator = TOTPGenerator()

        let before = generator.code(for: account, at: Date(timeIntervalSince1970: 89.999))
        let after = generator.code(for: account, at: Date(timeIntervalSince1970: 90))

        #expect(before != after)
    }

    @Test("Custom period (60s) produces a different code than the 30s default")
    func customPeriodIsRespected() {
        let secret = Self.rfcSecret
        let date = Date(timeIntervalSince1970: 1111111111)
        let generator = TOTPGenerator()

        let standard = generator.code(for: OTPAccount(issuer: "X", name: "y", secret: secret, digits: 6, period: 30), at: date)
        let longer = generator.code(for: OTPAccount(issuer: "X", name: "y", secret: secret, digits: 6, period: 60), at: date)

        #expect(standard != longer)
    }

    @Test("Invalid secret produces dashes of the right length")
    func invalidSecretReturnsDashes() {
        let account = OTPAccount(issuer: "X", name: "y", secret: "not-base32!!!", digits: 6)
        let code = TOTPGenerator().code(for: account, at: Date(timeIntervalSince1970: 0))
        #expect(code == "------")
    }

    @Test("normalizedSecret strips whitespace and padding, uppercases input")
    func normalizedSecretCleansInput() {
        let normalized = TOTPGenerator.normalizedSecret(" gezd gnbv  gy3t qojq===\n")
        #expect(normalized == "GEZDGNBVGY3TQOJQ")
    }

    @Test("isValidSecret accepts valid Base32, rejects invalid characters")
    func isValidSecretChecksAlphabet() {
        #expect(TOTPGenerator.isValidSecret("GEZDGNBVGY3TQOJQ"))
        #expect(TOTPGenerator.isValidSecret(TOTPGenerator.normalizedSecret("gezd gnbv gy3t qojq")))
        #expect(!TOTPGenerator.isValidSecret("not-base32"))
        #expect(!TOTPGenerator.isValidSecret(""))
    }

    @Test("base32EncodedSecret roundtrips through the RFC secret bytes")
    func base32RoundtripMatchesRFCSecret() {
        let asciiSecret = Data("12345678901234567890".utf8)
        let encoded = TOTPGenerator.base32EncodedSecret(asciiSecret)
        #expect(encoded == Self.rfcSecret)
    }
}
