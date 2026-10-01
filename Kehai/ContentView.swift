import SwiftUI
import UIKit

struct ContentView: View {
    @State private var store = SessionStore()
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await store.syncMyState() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            Task { await store.syncMyState() }
        }
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
