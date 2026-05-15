import SwiftUI

struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    let store: AccountSyncStore
    let onImport: (AccountSyncStore.ImportSummary) -> Void

    @State private var issuer = ""
    @State private var accountName = ""
    @State private var secret = ""
    @State private var digits = 6
    @State private var period: TimeInterval = 30
    @State private var isScanningQRCode = false
    @State private var scanError: String?

    private enum Field {
        case issuer
        case account
        case secret
    }

    private var trimmedIssuer: String {
        issuer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAccountName: String {
        accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedSecret: String {
        TOTPGenerator.normalizedSecret(secret)
    }

    private var isSecretValid: Bool {
        TOTPGenerator.isValidSecret(normalizedSecret)
    }

    private var canSave: Bool {
        !trimmedIssuer.isEmpty && isSecretValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isScanningQRCode = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                    }
                } footer: {
                    if let scanError {
                        Text(scanError)
                            .foregroundStyle(.red)
                    }
                }

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
                        .submitLabel(.next)
                        .onSubmit {
                            focusedField = .secret
                        }

                    TextField("Secret key", text: $secret)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .font(.body.monospaced())
                        .focused($focusedField, equals: .secret)
                        .submitLabel(.done)
                } header: {
                    Text("Account")
                } footer: {
                    accountSectionFooter
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard canSave else {
                            return
                        }

                        store.addAccount(
                            OTPAccount(
                                issuer: trimmedIssuer,
                                name: trimmedAccountName,
                                secret: normalizedSecret,
                                digits: digits,
                                period: period
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .fullScreenCover(isPresented: $isScanningQRCode) {
                NavigationStack {
                    QRCodeScannerView { scannedCode in
                        handleScannedCode(scannedCode)
                    } onError: { message in
                        scanError = message
                        isScanningQRCode = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan QR Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isScanningQRCode = false
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountSectionFooter: some View {
        if !secret.isEmpty && !isSecretValid {
            Text("Secret must be valid Base32")
                .foregroundStyle(.red)
        } else if trimmedIssuer.isEmpty && secret.isEmpty {
            Text("Issuer and secret are required")
        } else if trimmedIssuer.isEmpty {
            Text("Issuer is required")
        } else if secret.isEmpty {
            Text("Secret is required")
        }
    }

    private func handleScannedCode(_ scannedCode: String) {
        do {
            let result = try OTPQRCodeParser.parse(scannedCode)

            switch result {
            case .singleAccount(let account):
                applyScannedAccount(account)
                scanError = nil
                isScanningQRCode = false
            case .accountBundle(let accounts):
                let summary = store.importAccounts(accounts)
                onImport(summary)
                dismiss()
            }
        } catch {
            scanError = error.localizedDescription
            isScanningQRCode = false
        }
    }

    private func applyScannedAccount(_ account: OTPAccount) {
        issuer = account.issuer
        accountName = account.name
        secret = account.secret
        digits = account.digits
        period = account.period
    }
}
