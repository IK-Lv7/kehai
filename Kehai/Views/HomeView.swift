import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var store
    @State private var displayName = ""
    @State private var code = ""
    @State private var style = "maru"
    @State private var creature = "cat"
    @State private var color = CharacterPalette.colors[0].hex

    var body: some View {
        NavigationStack {
            List {
                Section("なかま") {
                    if store.partners.isEmpty {
                        Text("まだ誰ともつながっていません").foregroundStyle(.secondary)
                    }
                    ForEach(store.partners) { partner in
                        HStack(spacing: 12) {
                            CharacterView(
                                style: partner.characterStyle,
                                creature: partner.creature,
                                color: partner.color
                            )
                            .frame(width: 40, height: 40)
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

                Section("自分のキャラ") {
                    HStack {
                        Spacer()
                        CharacterView(style: style, creature: creature, color: color)
                            .frame(width: 96, height: 96)
                        Spacer()
                    }
                    Picker("スタイル", selection: $style) {
                        Text("まる").tag("maru")
                        Text("ドット絵").tag("dot")
                    }
                    .pickerStyle(.segmented)
                    if style == "dot" {
                        Picker("いきもの", selection: $creature) {
                            ForEach(Creature.all, id: \.id) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    HStack(spacing: 16) {
                        ForEach(CharacterPalette.colors, id: \.hex) { item in
                            Button {
                                color = item.hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: item.hex))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle().stroke(Color.primary, lineWidth: color == item.hex ? 3 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.name)
                        }
                    }
                    .frame(maxWidth: .infinity)
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
            .task {
                await store.loadProfile()
                if let profile = store.profile {
                    displayName = profile.displayName
                    style = profile.characterStyle
                    creature = profile.creature
                    color = profile.color
                }
            }
            .onChange(of: style) { saveAppearance() }
            .onChange(of: creature) { saveAppearance() }
            .onChange(of: color) { saveAppearance() }
        }
    }

    /// 読み込み直後の値の反映では、保存しない (今の値と同じときは何もしない)。
    private func saveAppearance() {
        guard let profile = store.profile,
              profile.characterStyle != style || profile.creature != creature || profile.color != color
        else { return }
        Task {
            await store.updateAppearance(style: style, creature: creature, color: color)
            await store.refreshPartners()
        }
    }
}
