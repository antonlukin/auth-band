import CryptoKit
import Foundation

struct TOTPGenerator {
    static func normalizedSecret(_ value: String) -> String {
        value.uppercased().filter { !$0.isWhitespace && $0 != "=" }
    }

    static func isValidSecret(_ value: String) -> Bool {
        Base32.decode(value) != nil
    }

    static func base32EncodedSecret(_ data: Data) -> String {
        Base32.encode(data)
    }

    func code(for account: OTPAccount, at date: Date) -> String {
        guard let secretData = Base32.decode(account.secret) else {
            return String(repeating: "-", count: account.digits)
        }

        let counter = UInt64(date.timeIntervalSince1970 / account.period)
        var bigEndianCounter = counter.bigEndian
        let counterData = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)
        let key = SymmetricKey(data: secretData)
        let hash = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hashBytes = Array(hash)
        let offset = Int(hashBytes[hashBytes.count - 1] & 0x0f)

        let truncatedHash =
            (UInt32(hashBytes[offset] & 0x7f) << 24) |
            (UInt32(hashBytes[offset + 1]) << 16) |
            (UInt32(hashBytes[offset + 2]) << 8) |
            UInt32(hashBytes[offset + 3])

        let divisor = UInt32(pow(10.0, Double(account.digits)))
        let otp = truncatedHash % divisor

        return String(format: "%0\(account.digits)d", otp)
    }
}

private enum Base32 {
    static func encode(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let bytes = Array(data)
        var buffer = 0
        var bitsLeft = 0
        var output = ""

        for byte in bytes {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8

            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 0x1f
                output.append(alphabet[index])
                bitsLeft -= 5
            }
        }

        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 0x1f
            output.append(alphabet[index])
        }

        return output
    }

    static func decode(_ value: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let table = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, UInt8($0)) })
        let characters = TOTPGenerator.normalizedSecret(value)
        var buffer = 0
        var bitsLeft = 0
        var bytes: [UInt8] = []

        for character in characters {
            guard let encodedValue = table[character] else {
                return nil
            }

            buffer = (buffer << 5) | Int(encodedValue)
            bitsLeft += 5

            if bitsLeft >= 8 {
                bytes.append(UInt8((buffer >> (bitsLeft - 8)) & 0xff))
                bitsLeft -= 8
            }
        }

        guard !bytes.isEmpty else {
            return nil
        }

        return Data(bytes)
    }
}
