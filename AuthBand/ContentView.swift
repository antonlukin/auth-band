import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var appLock: AppLockManager
    @StateObject private var store = AccountSyncStore()
    @State private var isAddingAccount = false
    @State private var isShowingSettings = false
    @State private var pendingImportSummary: AccountSyncStore.ImportSummary?
    @State private var lastImportSummary: AccountSyncStore.ImportSummary?
    @State private var isShowingImportAlert = false
    @State private var accountToEdit: OTPAccount?
    @State private var accountToDelete: OTPAccount?
    @State private var isShowingDeleteAlert = false
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    emptyStateView
                } else {
                    accountsList
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toastMessage)
            .navigationDestination(item: $accountToEdit) { account in
                EditAccountView(store: store, account: account)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("AuthBand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }

                if !store.accounts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            let countdown = Self.countdown(for: timeline.date, period: 30)
                            CircularCountdownView(
                                remainingSeconds: countdown.remainingSeconds,
                                progress: countdown.progress
                            )
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingAccount = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add account")
                    }
                }
            }
            .onAppear {
                store.refreshSyncStatus()
            }
            .fullScreenCover(
                isPresented: $isAddingAccount,
                onDismiss: {
                    if let summary = pendingImportSummary {
                        pendingImportSummary = nil
                        lastImportSummary = summary
                        isShowingImportAlert = true
                    }
                }
            ) {
                AddAccountView(store: store) { summary in
                    pendingImportSummary = summary
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView(appLock: appLock, store: store)
                }
            }
            .alert(
                "Import complete",
                isPresented: $isShowingImportAlert,
                presenting: lastImportSummary
            ) { _ in
                Button("OK", role: .cancel) {
                    lastImportSummary = nil
                }
            } message: { summary in
                Text(Self.importMessage(for: summary))
            }
            .alert(
                "Delete this account?",
                isPresented: $isShowingDeleteAlert,
                presenting: accountToDelete
            ) { _ in
                Button("Cancel", role: .cancel) {
                    accountToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let account = accountToDelete {
                        store.removeAccount(id: account.id)
                    }
                    accountToDelete = nil
                }
            } message: { _ in
                Text("The TOTP code on Apple Watch will stop working")
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Accounts", systemImage: "key.fill")
        } description: {
            Text("Add your first authentication code by scanning a QR code or entering it manually")
        } actions: {
            Button {
                isAddingAccount = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }

    private var accountsList: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            List {
                Section {
                    if filteredAccounts.isEmpty {
                        Text("No matches for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredAccounts) { account in
                            AccountRow(
                                account: account,
                                date: timeline.date,
                                onCopied: { showToast("Code copied") },
                                onEdit: { accountToEdit = account },
                                onDelete: {
                                    accountToDelete = account
                                    isShowingDeleteAlert = true
                                }
                            )
                            .listRowBackground(Self.cardBackground)
                        }
                    }
                } footer: {
                    footerView(now: timeline.date)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.top, 0, for: .scrollContent)
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search accounts"
        )
    }

    private var filteredAccounts: [OTPAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return store.accounts
        }
        return store.accounts.filter { account in
            account.issuer.localizedCaseInsensitiveContains(query)
                || account.name.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func footerView(now: Date) -> some View {
        let text = footerText(now: now)

        if case .failed = store.syncStatus {
            HStack(alignment: .center, spacing: 8) {
                Text(text)
                Spacer(minLength: 8)
                Button("Retry") {
                    store.sendAccountsToWatch()
                }
                .buttonStyle(.borderless)
            }
        } else {
            Text(text)
        }
    }

    private func footerText(now: Date) -> String {
        let sync = syncStatusText(now: now)
        let count = store.accounts.count

        guard count > 0 else {
            return sync
        }

        let countText = count == 1 ? "1 account" : "\(count) accounts"
        return "\(countText) • \(sync)"
    }

    private func syncStatusText(now: Date) -> String {
        switch store.syncStatus {
        case .failed:
            return "Sync failed"
        case .watchAppNotInstalled:
            return "Watch app not installed"
        case .watchNotPaired:
            return "No paired Apple Watch"
        case .watchUnavailable:
            return "Watch not available"
        case .unknown, .ready, .queued:
            if let last = store.lastSyncedAt {
                return "Synced \(Self.relativeTime(for: last, now: now))"
            }
            return "Not synced yet"
        }
    }

    private static func relativeTime(for date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 {
            return "just now"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60))m ago"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600))h ago"
        }
        return "\(Int(seconds / 86400))d ago"
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else {
                return
            }
            toastMessage = nil
        }
    }

    private static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.secondarySystemGroupedBackground
            : UIColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1.0)
    })

    private static func countdown(for date: Date, period: TimeInterval) -> (remainingSeconds: Int, progress: Double) {
        let elapsed = date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        let remaining = period - elapsed
        return (max(Int(ceil(remaining)), 0), remaining / period)
    }

    private static func importMessage(for summary: AccountSyncStore.ImportSummary) -> String {
        let added = summary.added
        let dupes = summary.skippedDuplicates
        let invalid = summary.skippedInvalid

        if added == 0 && dupes == 0 && invalid == 0 {
            return "Nothing to import"
        }

        if added == 0 && invalid == 0 {
            return dupes == 1
                ? "This account is already saved"
                : "All \(dupes) accounts are already saved"
        }

        var parts: [String] = []
        parts.append(added == 1 ? "Added 1 new account" : "Added \(added) new accounts")

        if dupes == 1 {
            parts.append("1 was already saved")
        } else if dupes > 1 {
            parts.append("\(dupes) were already saved")
        }

        if invalid == 1 {
            parts.append("1 couldn't be imported")
        } else if invalid > 1 {
            parts.append("\(invalid) couldn't be imported")
        }

        return parts.joined(separator: " — ")
    }

}


