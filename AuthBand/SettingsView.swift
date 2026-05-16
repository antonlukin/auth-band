import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appLock: AppLockManager
    let store: AccountSyncStore
    @AppStorage(AppLockManager.requireLockKey) private var requireBiometricLock = true
    @AppStorage("hideCodes") private var hideCodes = false
    @State private var showDeleteAllConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle("Require Device Unlock", isOn: $requireBiometricLock)
                Toggle("Hide Codes", isOn: $hideCodes)
            } header: {
                Text("Security")
            } footer: {
                Text("Unlock AuthBand with Face ID, Touch ID, or your device passcode — applies on launch and when the app returns from background. Requires a device passcode.")
            }

            Section {
                Button {
                    store.sendAccountsToWatch()
                    dismiss()
                } label: {
                    Text("Sync to Apple Watch")
                }

                HStack {
                    Text("Last synced")
                    Spacer()
                    Text(lastSyncedText)
                        .foregroundStyle(.secondary)
                }

                if let issue = syncIssueText {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Status")
                        Spacer()
                        Text(issue)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Push the current account list to your paired Apple Watch — useful if the watch is missing recent changes")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAllConfirm = true
                } label: {
                    Text("Delete All Accounts")
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Remove every account from this iPhone and from your Apple Watch")
            }

            Section {
                Link(destination: Self.privacyURL) {
                    HStack {
                        Text("Privacy Policy")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                }
                Link(destination: Self.supportURL) {
                    HStack {
                        Text("Support")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                }
                Link(destination: Self.sourceURL) {
                    HStack {
                        Text("Source Code")
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("About")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AuthBand is open source — the code is public on GitHub, so you can inspect what runs on your device, audit it, or build it yourself.")
                    Text("Version \(Self.appVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onChange(of: requireBiometricLock) { _, _ in
            appLock.applyLockPreferenceChange()
        }
        .alert("Delete all accounts?", isPresented: $showDeleteAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                store.removeAllAccounts()
                dismiss()
            }
        } message: {
            Text("This removes every account from this iPhone and Apple Watch — cannot be undone")
        }
    }

    private var lastSyncedText: String {
        guard let date = store.lastSyncedAt else {
            return String(localized: "Never", comment: "Settings: Apple Watch never synced before")
        }
        return Self.relativeTime(for: date, now: Date())
    }

    private var syncIssueText: String? {
        switch store.syncStatus {
        case .failed(let message):
            return message
        case .watchAppNotInstalled:
            return String(localized: "Watch app not installed", comment: "Settings: paired Watch but app not installed")
        case .watchNotPaired:
            return String(localized: "No paired Apple Watch", comment: "Settings: no Apple Watch paired with this iPhone")
        case .watchUnavailable:
            return String(localized: "Apple Watch not available", comment: "Settings: WatchConnectivity unsupported on this device")
        case .unknown, .ready, .queued:
            return nil
        }
    }

    private static func relativeTime(for date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 10 {
            return String(localized: "just now", comment: "Relative time: very recent (under 10 seconds)")
        }
        if seconds < 60 {
            return String(localized: "less than a minute ago", comment: "Relative time: between 10 and 60 seconds")
        }
        if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return String(localized: "\(minutes) min ago", comment: "Relative time: in minutes; configure plural on `minutes`")
        }
        if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return String(localized: "\(hours) h ago", comment: "Relative time: in hours; configure plural on `hours`")
        }
        let days = Int(seconds / 86400)
        return String(localized: "\(days) d ago", comment: "Relative time: in days; configure plural on `days`")
    }

    private static let sourceURL = URL(string: "https://github.com/antonlukin/auth-band")!
    private static let privacyURL = URL(string: "https://github.com/antonlukin/auth-band/blob/main/PRIVACY.md")!
    private static let supportURL = URL(string: "https://github.com/antonlukin/auth-band/issues")!

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
