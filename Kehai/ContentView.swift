import SwiftUI

struct ContentView: View {
    @State private var store = SessionStore()

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView()
            } else if store.isSignedIn {
                HomeView()
            } else {
                SignInView()
            }
        }
        .environment(store)
        .task { await store.start() }
        .alert("お知らせ", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}
