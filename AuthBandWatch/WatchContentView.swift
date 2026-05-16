import SwiftUI

struct WatchContentView: View {
    @StateObject private var store = AccountSyncStore()

    var body: some View {
        NavigationStack {
            Group {
                if store.accounts.isEmpty {
                    ContentUnavailableView {
                        Label("No codes yet", systemImage: "key.fill")
                    } description: {
                        Text("Add accounts on your iPhone")
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        List(store.accounts) { account in
                            WatchAccountRow(account: account, date: timeline.date)
                        }
                    }
                }
            }
            .navigationTitle("AuthBand")
        }
    }
}
