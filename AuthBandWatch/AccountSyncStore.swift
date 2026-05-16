import Foundation
import Security
import WatchConnectivity

enum SyncStatus: Equatable {
    case unknown
    case ready
    case queued
    case watchUnavailable
    case watchNotPaired
    case watchAppNotInstalled
    case failed(String)
}

private struct SyncEnvelope: Codable {
    let version: Int
    let sentAt: Date
    let accounts: [OTPAccount]

    static let currentVersion = 1
    static let maxAccounts = 200
}

@MainActor
final class AccountSyncStore: NSObject, ObservableObject {
    @Published private(set) var accounts: [OTPAccount]
    @Published private(set) var syncStatus: SyncStatus = .unknown
    @Published private(set) var lastSyncedAt: Date?

    private let accountsKey = "accounts"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let legacyStorageKey = "storedAccounts"

    override init() {
        accounts = AccountSyncStore.loadStoredAccounts() ?? []
        super.init()
        activateSession()
    }

    func sendAccountsToWatch() {
        #if os(iOS)
        guard WCSession.isSupported() else {
            syncStatus = .watchUnavailable
            return
        }

        let session = WCSession.default
        guard session.activationState == .activated else {
            syncStatus = .unknown
            return
        }

        guard session.isPaired else {
            syncStatus = .watchNotPaired
            return
        }

        guard session.isWatchAppInstalled else {
            syncStatus = .watchAppNotInstalled
            return
        }

        do {
            let envelope = SyncEnvelope(
                version: SyncEnvelope.currentVersion,
                sentAt: Date(),
                accounts: accounts
            )
            let payload = try encoder.encode(envelope)
            let message = [accountsKey: payload]
            try session.updateApplicationContext(message)

            lastSyncedAt = Date()
            syncStatus = .queued

            guard session.isReachable else {
                return
            }

            session.sendMessage(
                message,
                replyHandler: nil,
                errorHandler: { [weak self] error in
                    Task { @MainActor in
                        let message = String(
                            localized: "Live sync failed: \(error.localizedDescription)",
                            comment: "Shown when WatchConnectivity sendMessage errors out"
                        )
                        self?.syncStatus = .failed(message)
                    }
                }
            )
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
        #endif
    }

    func refreshSyncStatus() {
        guard WCSession.isSupported() else {
            syncStatus = .watchUnavailable
            return
        }

        #if os(iOS)
        let session = WCSession.default
        syncStatus = Self.statusFor(session: session)
        #else
        syncStatus = .ready
        #endif
    }

    func addAccount(_ account: OTPAccount) {
        let issuer = account.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = TOTPGenerator.normalizedSecret(account.secret)

        guard !issuer.isEmpty, TOTPGenerator.isValidSecret(secret) else {
            return
        }

        guard !accounts.contains(where: { $0.secret == secret }) else {
            return
        }

        accounts.append(
            OTPAccount(
                issuer: issuer,
                name: name,
                secret: secret,
                digits: account.digits,
                period: account.period
            )
        )
        saveAccounts()
        sendAccountsToWatch()
    }

    struct ImportSummary: Equatable {
        let added: Int
        let skippedDuplicates: Int
        let skippedInvalid: Int

        var total: Int { added + skippedDuplicates + skippedInvalid }
    }

    func importAccounts(_ candidates: [OTPAccount]) -> ImportSummary {
        var added = 0
        var skippedDuplicates = 0
        var skippedInvalid = 0

        var seenSecrets = Set(accounts.map { $0.secret })

        for account in candidates {
            let issuer = account.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = TOTPGenerator.normalizedSecret(account.secret)

            guard !issuer.isEmpty, TOTPGenerator.isValidSecret(secret) else {
                skippedInvalid += 1
                continue
            }

            guard !seenSecrets.contains(secret) else {
                skippedDuplicates += 1
                continue
            }

            accounts.append(
                OTPAccount(
                    issuer: issuer,
                    name: name,
                    secret: secret,
                    digits: account.digits,
                    period: account.period
                )
            )
            seenSecrets.insert(secret)
            added += 1
        }

        if added > 0 {
            saveAccounts()
            sendAccountsToWatch()
        }

        return ImportSummary(
            added: added,
            skippedDuplicates: skippedDuplicates,
            skippedInvalid: skippedInvalid
        )
    }

    func removeAccount(id: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return
        }
        accounts.remove(at: index)
        saveAccounts()
        sendAccountsToWatch()
    }

    func removeAllAccounts() {
        guard !accounts.isEmpty else {
            return
        }
        accounts.removeAll()
        saveAccounts()
        sendAccountsToWatch()
    }

    func updateAccount(id: UUID, issuer: String, name: String) {
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedIssuer.isEmpty,
              let index = accounts.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let existing = accounts[index]
        accounts[index] = OTPAccount(
            id: existing.id,
            issuer: trimmedIssuer,
            name: trimmedName,
            secret: existing.secret,
            digits: existing.digits,
            period: existing.period
        )
        saveAccounts()
        sendAccountsToWatch()
    }

    private func activateSession() {
        guard WCSession.isSupported() else {
            syncStatus = .watchUnavailable
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()

        #if os(watchOS)
        applyApplicationContext(session.receivedApplicationContext)
        #endif
    }

    private func applyApplicationContext(_ applicationContext: [String: Any]) {
        guard let payload = applicationContext[accountsKey] as? Data else {
            return
        }

        let envelope: SyncEnvelope
        do {
            envelope = try decoder.decode(SyncEnvelope.self, from: payload)
        } catch {
            syncStatus = .failed(String(localized: "Received invalid accounts", comment: "Sync error: payload could not be decoded"))
            return
        }

        guard envelope.version == SyncEnvelope.currentVersion else {
            syncStatus = .failed(String(localized: "Unsupported sync version \(envelope.version)", comment: "Sync error: envelope version higher than this build supports"))
            return
        }

        guard envelope.accounts.count <= SyncEnvelope.maxAccounts else {
            syncStatus = .failed(String(localized: "Sync payload too large (\(envelope.accounts.count) accounts)", comment: "Sync error: too many accounts in single payload"))
            return
        }

        accounts = envelope.accounts
        saveAccounts()
        syncStatus = .ready
        lastSyncedAt = Date()
    }

    private static func loadStoredAccounts() -> [OTPAccount]? {
        if let payload = KeychainAccountStorage.load() {
            return try? JSONDecoder().decode([OTPAccount].self, from: payload)
        }

        guard
            let legacyPayload = UserDefaults.standard.data(forKey: legacyStorageKey),
            let legacyAccounts = try? JSONDecoder().decode([OTPAccount].self, from: legacyPayload)
        else {
            return nil
        }

        // Fail-closed: if migration to Keychain fails, do not expose legacy data
        // to the running app. The legacy UserDefaults entry stays in place so a
        // subsequent launch can retry the migration.
        guard KeychainAccountStorage.save(legacyPayload) else {
            return nil
        }

        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        return legacyAccounts
    }

    private func saveAccounts() {
        guard let payload = try? encoder.encode(accounts) else {
            return
        }

        if !KeychainAccountStorage.save(payload) {
            syncStatus = .failed(String(localized: "Local secure storage failed", comment: "Sync error: Keychain write returned an error"))
        }
    }

    #if os(iOS)
    private static func statusFor(session: WCSession) -> SyncStatus {
        switch session.activationState {
        case .activated:
            if !session.isPaired { return .watchNotPaired }
            if !session.isWatchAppInstalled { return .watchAppNotInstalled }
            return .ready
        case .inactive, .notActivated:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
    #endif
}

extension AccountSyncStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.syncStatus = .failed(String(localized: "Activation failed: \(error.localizedDescription)", comment: "Sync error: WCSession activation returned an error"))
                return
            }

            #if os(iOS)
            self.syncStatus = Self.statusFor(session: session)
            self.sendAccountsToWatch()
            #else
            self.syncStatus = activationState == .activated ? .ready : .unknown
            self.applyApplicationContext(session.receivedApplicationContext)
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.applyApplicationContext(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.applyApplicationContext(message)
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.syncStatus = .unknown
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.syncStatus = .unknown
        }
        session.activate()
    }
    #endif
}

private enum KeychainAccountStorage {
    private static let service = "com.antonlukin.authband.accounts"
    private static let account = "storedAccounts"

    static func load() -> Data? {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            return nil
        }

        return item as? Data
    }

    static func save(_ data: Data) -> Bool {
        let query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            return false
        }

        var newItem = query
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        newItem[kSecValueData as String] = data

        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
