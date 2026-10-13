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
                if store.needsOnboarding {
                    OnboardingView()
                } else {
                    HomeView()
                }
            } else {
                SignInView()
            }
        }
        // 招待リンクから開いたら、ログイン済みになった時点で「つながりますか？」と聞く。
        .alert(
            "招待でつながりますか？",
            isPresented: Binding(
                get: { store.isSignedIn && store.pendingInviteCode != nil },
                set: { if !$0 { store.pendingInviteCode = nil } }
            ),
            presenting: store.pendingInviteCode
        ) { code in
            Button("つながる") { Task { await store.redeem(code: code) } }
            Button("やめる", role: .cancel) {}
        } message: { code in
            Text("招待コード: \(code)")
        }
        .environment(store)
        .task { await store.start() }
        .onOpenURL { store.handle(url: $0) }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await store.syncMyState()
                    await store.loadRecentTaps()
                }
            }
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
