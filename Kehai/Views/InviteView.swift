import SwiftUI

/// なかまを招待する (リンクを送る) / もらったコードでつながる。
/// シートでも、初回の案内の中でも使う。
struct InvitePanel: View {
    @Environment(SessionStore.self) private var store
    @State private var code = ""
    /// つながれたときに呼ぶ (シートを閉じる、案内を次へ進めるなど)。
    var onConnected: () -> Void

    init(onConnected: @escaping () -> Void = {}) {
        self.onConnected = onConnected
    }

    var body: some View {
        Section {
            if let invite = store.inviteCode {
                Text(invite)
                    .font(.title2.monospaced().bold())
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
                ShareLink(
                    item: InviteLink.shareURL(code: invite),
                    subject: Text("Kehai でつながろう"),
                    message: Text("Kehai でつながろう。リンクを開くとつながります。")
                ) {
                    Label("招待リンクを送る", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task { await store.createInvite() }
                } label: {
                    Label("招待リンクを作る", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("招待する")
        } footer: {
            Text("LINE などで送れます。リンクは3日で期限切れになり、1回だけ使えます。")
        }

        Section("コードを入力") {
            TextField("もらったコード (KEHAI-XXXXXX)", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("コードでつながる") {
                Task {
                    if await store.redeem(code: code) {
                        code = ""
                        onConnected()
                    }
                }
            }
            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

/// ホーム画面の「＋」から開く、招待のシート。
struct InviteView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                InvitePanel { dismiss() }
            }
            .navigationTitle("なかまを招待")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
