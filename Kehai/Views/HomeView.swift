import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var store
    @State private var displayName = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            List {
                Section("なかま") {
                    if store.partners.isEmpty {
                        Text("まだ誰ともつながっていません").foregroundStyle(.secondary)
                    }
                    ForEach(store.partners) { partner in
                        HStack(spacing: 12) {
                            MaruView(color: Color(hex: partner.color)).frame(width: 40, height: 40)
                            VStack(alignment: .leading) {
                                Text(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)
                                Text(partner.updatedAt, style: .relative)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("解除", role: .destructive) {
                                Task { await store.remove(partner) }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("自分のなまえ") {
                    TextField("相手に見えるなまえ", text: $displayName)
                    Button("保存") { Task { await store.updateDisplayName(displayName) } }
                        .disabled(displayName.isEmpty)
                }

                Section("つながる") {
                    Button("招待コードを作る") { Task { await store.createInvite() } }
                    if let invite = store.inviteCode {
                        Text(invite).font(.title3.monospaced()).textSelection(.enabled)
                        Text("3日で期限切れ・1回だけ使えます").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("もらったコード (KEHAI-XXXXXX)", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("コードでつながる") {
                        Task {
                            await store.redeem(code: code)
                            code = ""
                        }
                    }
                    .disabled(code.isEmpty)
                }

                Section {
                    Button("ログアウト", role: .destructive) { Task { await store.signOut() } }
                }
            }
            .navigationTitle("Kehai")
            .refreshable { await store.refreshPartners() }
        }
    }
}
