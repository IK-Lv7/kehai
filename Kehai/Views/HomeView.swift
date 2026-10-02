import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var store
    @State private var displayName = ""
    @State private var code = ""
    @State private var style = "maru"
    @State private var creature = "cat"
    @State private var color = CharacterPalette.colors[0].hex
    @State private var partnerToRemove: PartnerState?

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
                                Text(partner.presence(now: Date()).label)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("解除", role: .destructive) {
                                partnerToRemove = partner
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
                    characterGrid
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
            .confirmationDialog(
                "\(partnerToRemove.map { $0.displayName.isEmpty ? "この人" : $0.displayName } ?? "")とのつながりを解除しますか？",
                isPresented: Binding(
                    get: { partnerToRemove != nil },
                    set: { if !$0 { partnerToRemove = nil } }
                ),
                titleVisibility: .visible,
                presenting: partnerToRemove
            ) { partner in
                Button("解除する", role: .destructive) {
                    Task { await store.remove(partner) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: { _ in
                Text("もう一度つながるには、新しい招待コードが必要です。")
            }
            .onChange(of: style) { saveAppearance() }
            .onChange(of: creature) { saveAppearance() }
            .onChange(of: color) { saveAppearance() }
        }
    }

    /// キャラ一覧。色ごとには並べず、代表色の1体だけを表示し、色は下のパレットで選ぶ。
    private var characterGrid: some View {
        let representative = CharacterPalette.colors[0].hex
        let items: [(key: String, name: String, style: String, creature: String)] =
            [("maru", "まる", "maru", creature)]
            + Creature.all.map { ($0.id, $0.name, "dot", $0.id) }
        let selectedKey = style == "dot" ? creature : "maru"
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(items, id: \.key) { item in
                Button {
                    style = item.style
                    creature = item.creature
                } label: {
                    VStack(spacing: 6) {
                        CharacterView(style: item.style, creature: item.creature, color: representative)
                            .frame(width: 56, height: 56)
                        Text(item.name).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor, lineWidth: selectedKey == item.key ? 3 : 0)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
            }
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
