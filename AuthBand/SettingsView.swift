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
}
