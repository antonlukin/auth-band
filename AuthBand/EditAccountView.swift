import SwiftUI

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    let store: AccountSyncStore
    let accountID: UUID

    @State private var issuer: String
    @State private var accountName: String
    @State private var showDeleteConfirm = false

    private enum Field {
        case issuer
        case account
    }

    init(store: AccountSyncStore, account: OTPAccount) {
        self.store = store
        self.accountID = account.id
        _issuer = State(initialValue: account.issuer)
        _accountName = State(initialValue: account.name)
    }

    private var trimmedIssuer: String {
        issuer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedIssuer.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Issuer", text: $issuer)
                    .textInputAutocapitalization(.words)
                    .textContentType(.organizationName)
                    .focused($focusedField, equals: .issuer)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .account
                    }

                TextField("Account", text: $accountName)
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    .focused($focusedField, equals: .account)
                    .submitLabel(.done)
            } header: {
                Text("Account")
            } footer: {
                if trimmedIssuer.isEmpty {
                    Text("Issuer is required")
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete Account")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard canSave else {
                        return
                    }

                    store.updateAccount(
                        id: accountID,
                        issuer: trimmedIssuer,
                        name: accountName
                    )
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .alert("Delete this account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.removeAccount(id: accountID)
                dismiss()
            }
        } message: {
            Text("The TOTP code on Apple Watch will stop working")
        }
    }
}
