import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var appLock: AppLockManager
    let store: AccountSyncStore
    @AppStorage(AppLockManager.requireLockKey) private var requireBiometricLock = true
    @State private var showDeleteAllConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle("Require Device Unlock", isOn: $requireBiometricLock)
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

    private static let sourceURL = URL(string: "https://github.com/antonlukin/auth-band")!

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}
