import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            MaruView().frame(width: 120, height: 120)
            Text("Kehai").font(.title.bold())
            Text("気配を、そっと届ける。").foregroundStyle(.secondary)
            SignInWithAppleButton(.signIn) { request in
                store.prepare(request)
            } onCompletion: { result in
                Task { await store.complete(result) }
            }
            .frame(height: 48)
            .padding(.horizontal, 40)
            Link("プライバシーポリシー", destination: SharedLinks.privacyPolicy)
                .font(.footnote)
        }
        .padding()
    }
}
