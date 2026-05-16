import Foundation

enum OTPQRCodeParser {
    enum Result {
        case singleAccount(OTPAccount)
        case accountBundle([OTPAccount])
    }

    static func parse(_ value: String) throws -> Result {
        guard let components = URLComponents(string: value) else {
            throw OTPImportError.invalidURL
        }

        switch components.scheme?.lowercased() {
        case "otpauth":
            return .singleAccount(try OTPAuthURLParser.parse(components))
        case "otpauth-migration":
            return .accountBundle(try GoogleAuthenticatorMigrationParser.parse(components))
        default:
            throw OTPImportError.invalidURL
        }
    }
}

enum OTPAuthURLParser {
    static let allowedDigits: Set<Int> = [6, 7, 8]
    static let allowedPeriodRange: ClosedRange<Int> = 15...300

    static func parse(_ components: URLComponents) throws -> OTPAccount {
        guard components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp"
        else {
            throw OTPImportError.invalidURL
        }

        let queryItems = components.queryItems ?? []

        guard let secret = queryItems.value(named: "secret") else {
            throw OTPImportError.missingSecret
        }

        let normalizedSecret = TOTPGenerator.normalizedSecret(secret)
        guard TOTPGenerator.isValidSecret(normalizedSecret) else {
            throw OTPImportError.invalidSecret
        }

        let algorithm = queryItems.value(named: "algorithm")?.uppercased()
        guard algorithm == nil || algorithm == "SHA1" else {
            throw OTPImportError.unsupportedAlgorithm
        }

        let label = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding ?? ""
        let labelParts = splitLabel(label)
        let issuer = queryItems.value(named: "issuer") ?? labelParts.issuer
        let accountName = labelParts.accountName

        guard !issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OTPImportError.missingIssuer
        }

        let digits = try parseDigits(queryItems.value(named: "digits"))
        let period = try parsePeriod(queryItems.value(named: "period"))

        return OTPAccount(
            issuer: issuer,
            name: accountName,
            secret: normalizedSecret,
            digits: digits,
            period: period
        )
    }

    private static func parseDigits(_ raw: String?) throws -> Int {
        guard let raw, !raw.isEmpty else {
            return 6
        }
        guard let value = Int(raw), allowedDigits.contains(value) else {
            throw OTPImportError.invalidDigits
        }
        return value
    }

    private static func parsePeriod(_ raw: String?) throws -> TimeInterval {
        guard let raw, !raw.isEmpty else {
            return 30
        }
        guard let value = Int(raw), allowedPeriodRange.contains(value) else {
            throw OTPImportError.invalidPeriod
        }
        return TimeInterval(value)
    }

    private static func splitLabel(_ label: String) -> (issuer: String, accountName: String) {
        let parts = label.split(separator: ":", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return (label, "")
        }

        return (parts[0], parts[1])
    }
}

enum GoogleAuthenticatorMigrationParser {
    static func parse(_ components: URLComponents) throws -> [OTPAccount] {
        guard components.scheme?.lowercased() == "otpauth-migration",
              components.host?.lowercased() == "offline"
        else {
            throw OTPImportError.invalidURL
        }

        guard let encodedPayload = components.queryItems?.value(named: "data") else {
            throw OTPImportError.missingMigrationData
        }

        guard let payload = base64URLDecodedData(encodedPayload) else {
            throw OTPImportError.invalidMigrationData
        }

        var reader = ProtobufReader(data: payload)
        var accounts: [OTPAccount] = []

        while !reader.isAtEnd {
            let field = try reader.readField()

            switch (field.number, field.wireType) {
            case (1, .lengthDelimited):
                let parameterData = try reader.readLengthDelimitedData()

                if let account = try parseOTPParameters(parameterData) {
                    accounts.append(account)
                }
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        guard !accounts.isEmpty else {
            throw OTPImportError.noSupportedAccounts
        }

        return accounts
    }

    private static func parseOTPParameters(_ data: Data) throws -> OTPAccount? {
        var reader = ProtobufReader(data: data)
        var secretData: Data?
        var label = ""
        var issuer = ""
        var algorithm = 1
        var digitsValue = 1
        var type = 2

        while !reader.isAtEnd {
            let field = try reader.readField()

            switch (field.number, field.wireType) {
            case (1, .lengthDelimited):
                secretData = try reader.readLengthDelimitedData()
            case (2, .lengthDelimited):
                label = try reader.readLengthDelimitedString()
            case (3, .lengthDelimited):
                issuer = try reader.readLengthDelimitedString()
            case (4, .varint):
                algorithm = Int(try reader.readVarint())
            case (5, .varint):
                digitsValue = Int(try reader.readVarint())
            case (6, .varint):
                type = Int(try reader.readVarint())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        guard type == 2, algorithm == 1, let secretData, !secretData.isEmpty else {
            return nil
        }

        let labelParts = splitLabel(label)
        let resolvedIssuer = firstNonEmpty(issuer, labelParts.issuer, labelParts.accountName)
        let accountName = labelParts.accountName == resolvedIssuer ? "" : labelParts.accountName
        let secret = TOTPGenerator.base32EncodedSecret(secretData)

        guard !resolvedIssuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return OTPAccount(
            issuer: resolvedIssuer,
            name: accountName,
            secret: secret,
            digits: digits(for: digitsValue),
            period: 30
        )
    }

    private static func base64URLDecodedData(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = normalized.count % 4
        if padding > 0 {
            normalized.append(String(repeating: "=", count: 4 - padding))
        }

        return Data(base64Encoded: normalized)
    }

    private static func digits(for value: Int) -> Int {
        switch value {
        case 2:
            return 8
        default:
            return 6
        }
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
    }

    private static func splitLabel(_ label: String) -> (issuer: String, accountName: String) {
        let parts = label.split(separator: ":", maxSplits: 1).map(String.init)

        guard parts.count == 2 else {
            return ("", label)
        }

        return (parts[0], parts[1])
    }
}

enum OTPImportError: LocalizedError {
    case invalidURL
    case missingSecret
    case invalidSecret
    case missingIssuer
    case unsupportedAlgorithm
    case invalidDigits
    case invalidPeriod
    case missingMigrationData
    case invalidMigrationData
    case noSupportedAccounts

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "QR code is not a TOTP authenticator URL", comment: "Import error: wrong URL scheme or host")
        case .missingSecret:
            return String(localized: "QR code does not contain a secret key", comment: "Import error: no `secret` query param")
        case .invalidSecret:
            return String(localized: "QR code contains an invalid Base32 secret", comment: "Import error: secret is not valid Base32")
        case .missingIssuer:
            return String(localized: "QR code does not contain an account issuer", comment: "Import error: no issuer in URL")
        case .unsupportedAlgorithm:
            return String(localized: "Only SHA1 TOTP accounts are supported for now", comment: "Import error: algorithm parameter is not SHA1")
        case .invalidDigits:
            return String(localized: "QR code requests an unsupported code length (only 6, 7, or 8 digits are allowed)", comment: "Import error: digits param out of allowed range")
        case .invalidPeriod:
            return String(localized: "QR code requests an unsupported refresh interval (15–300 seconds are allowed)", comment: "Import error: period param out of allowed range")
        case .missingMigrationData:
            return String(localized: "Google Authenticator QR code does not contain migration data", comment: "Import error: otpauth-migration URL missing data param")
        case .invalidMigrationData:
            return String(localized: "Google Authenticator migration data could not be decoded", comment: "Import error: protobuf payload malformed")
        case .noSupportedAccounts:
            return String(localized: "No supported TOTP/SHA1 accounts were found in this QR code", comment: "Import error: all accounts in migration QR were filtered out")
        }
    }
}

extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
