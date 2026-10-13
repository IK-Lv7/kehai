import SwiftUI

/// ホーム右上の歯車から開く設定。キャラ・状態・見せる情報・通知・アカウントなど。
struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @State private var displayName = ""
    @State private var style = "maru"
    @State private var creature = "cat"
    @State private var color = CharacterPalette.colors[0].hex
    @State private var sleepStart = Date()
    @State private var sleepEnd = Date()
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section("自分のキャラ") {
                CharacterEditor(style: $style, creature: $creature, color: $color)
                    .padding(.vertical, 8)
            }

            Section("自分のなまえ") {
                TextField("相手に見えるなまえ", text: $displayName)
                Button("保存") { Task { await store.updateDisplayName(displayName) } }
                    .disabled(displayName.isEmpty || displayName == store.profile?.displayName)
            }

            Section {
                Toggle("さぎょうちゅう", isOn: Binding(
                    get: { store.isWorking },
                    set: { newValue in Task { await store.setWorking(newValue) } }
                ))
                DatePicker("ねる時間", selection: $sleepStart, displayedComponents: .hourAndMinute)
                DatePicker("おきる時間", selection: $sleepEnd, displayedComponents: .hourAndMinute)
            } header: {
                Text("自分の状態")
            } footer: {
                Text("ねる時間のあいだ、充電しているか、しばらくアプリが動いていないと、相手には「ねてる」と見えます。コントロールセンターにも「さぎょうちゅう」のボタンを置けます。")
            }

            if !store.partners.isEmpty {
                Section {
                    ForEach(store.partners) { partner in
                        NavigationLink {
                            PartnerShareView(partner: partner)
                        } label: {
                            Text(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)
                        }
                    }
                } header: {
                    Text("見せる情報")
                } footer: {
                    Text("相手ごとに、自分の何を見せるかを選べます。")
                }
            }

            Section {
                Toggle("トントンの通知を受け取る", isOn: Binding(
                    get: { store.profile?.receiveTaps ?? true },
                    set: { newValue in Task { await store.setReceiveTaps(newValue) } }
                ))
            } header: {
                Text("通知")
            } footer: {
                Text("届かないときは、iOSの設定でKehaiの通知を許可してください。")
            }

            Section {
                Button("使い方をもう一度見る") { store.replayOnboarding() }
                Link("プライバシーポリシー", destination: SharedLinks.privacyPolicy)
                Link("サポート", destination: SharedLinks.support)
            }

            Section {
                Button("ログアウト", role: .destructive) { Task { await store.signOut() } }
                Button("アカウントを削除", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("アカウントを削除すると、なまえ・キャラ・つながり・トントンの記録がすべて消えます。")
            }
        }
        .navigationTitle("設定")
        .task {
            await store.loadMyState()
            sleepStart = Self.date(fromMinutes: store.sleepStartMinutes)
            sleepEnd = Self.date(fromMinutes: store.sleepEndMinutes)
            await store.loadShareSettings()
            await store.loadProfile()
            if let profile = store.profile {
                displayName = profile.displayName
                style = profile.characterStyle
                creature = profile.creature
                color = profile.color
            }
        }
        .confirmationDialog(
            "アカウントを削除しますか？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("削除する", role: .destructive) {
                Task { await store.deleteAccount() }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。つながっていた人のウィジェットからも、あなたは消えます。")
        }
        .onChange(of: sleepStart) { saveSleepWindow() }
        .onChange(of: sleepEnd) { saveSleepWindow() }
        .onChange(of: style) { saveAppearance() }
        .onChange(of: creature) { saveAppearance() }
        .onChange(of: color) { saveAppearance() }
    }

    static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 読み込み直後の値の反映では、保存しない (今の値と同じときは何もしない)。
    private func saveSleepWindow() {
        let start = Self.minutes(from: sleepStart)
        let end = Self.minutes(from: sleepEnd)
        guard start != store.sleepStartMinutes || end != store.sleepEndMinutes else { return }
        Task {
            await store.updateSleepWindow(startMinutes: start, endMinutes: end)
            await store.refreshPartners()
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
