import SwiftUI

/// はじめての人への案内。ようこそ → キャラ → なまえ → つながる → ウィジェットを置く。
struct OnboardingView: View {
    @Environment(SessionStore.self) private var store
    @State private var step = Step.welcome
    @State private var style = "maru"
    @State private var creature = "cat"
    @State private var color = CharacterPalette.colors[0].hex
    @State private var displayName = ""
    @State private var isSaving = false

    private enum Step: Int, CaseIterable {
        case welcome, character, name, invite, widget
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .character: character
                case .name: name
                case .invite: invite
                case .widget: widget
                }
            }
            .animation(.default, value: step)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("もどる") { move(by: -1) }
                    }
                    ToolbarItem(placement: .principal) {
                        progress
                    }
                }
            }
        }
        .task {
            if let profile = store.profile {
                style = profile.characterStyle
                creature = profile.creature
                color = profile.color
                displayName = profile.displayName
            }
        }
    }

    // MARK: 各ステップ

    private var welcome: some View {
        page(buttonTitle: "はじめる", action: { move(by: 1) }) {
            VStack(spacing: 20) {
                MaruView()
                    .frame(width: 140, height: 140)
                Text("Kehai へようこそ")
                    .font(.title.bold())
                Text("大切な人の気配を、そっと感じるアプリです。\n相手のキャラの絵で、ねてる・じゅうでん中・さぎょう中が分かります。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var character: some View {
        page(title: "自分のキャラを選ぶ", subtitle: "相手のウィジェットには、このキャラが出ます。", buttonTitle: "つぎへ") {
            isSaving = true
            await store.updateAppearance(style: style, creature: creature, color: color)
            isSaving = false
            move(by: 1)
        } content: {
            CharacterEditor(style: $style, creature: $creature, color: $color)
        }
    }

    private var name: some View {
        page(
            title: "なまえを決める",
            subtitle: "相手に見えるなまえです。あとから変えられます。",
            buttonTitle: "つぎへ",
            buttonDisabled: displayName.trimmingCharacters(in: .whitespaces).isEmpty
        ) {
            isSaving = true
            await store.updateDisplayName(String(displayName.prefix(20)), announce: false)
            isSaving = false
            move(by: 1)
        } content: {
            TextField("なまえ (20文字まで)", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .submitLabel(.next)
        }
    }

    private var invite: some View {
        VStack(spacing: 0) {
            header(title: "なかまとつながる", subtitle: "招待リンクを送るか、もらったコードを入力します。")
                .padding()
            List {
                InvitePanel { move(by: 1) }
            }
            bottomButton(store.partners.isEmpty ? "あとで" : "つぎへ") { move(by: 1) }
        }
    }

    private var widget: some View {
        page(
            title: "ウィジェットを置く",
            subtitle: "ホーム画面に置くと、アプリを開かなくても、なかまの気配が分かります。",
            buttonTitle: "はじめる",
            action: { store.finishOnboarding() }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                widgetStep(1, "ホーム画面の、何もないところを長押しします", systemImage: "hand.tap")
                widgetStep(2, "左上の「編集」→「ウィジェットを追加」を押します", systemImage: "plus.square")
                widgetStep(3, "「Kehai」を探して、好きな大きさで追加します", systemImage: "square.grid.2x2")
                widgetStep(4, "ウィジェットを長押しして「ウィジェットを編集」で、出す人を選べます", systemImage: "person.2")
                widgetStep(5, "ロック画面にも置けます (ロック画面を長押し →「カスタマイズ」)", systemImage: "lock")
            }
        }
    }

    // MARK: 部品

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.dropFirst(), id: \.self) { item in
                Circle()
                    .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.rawValue) / \(Step.allCases.count - 1)")
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.title2.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func widgetStep(_ number: Int, _ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            Text("\(number). \(text)")
        }
    }

    private func page<Content: View>(
        title: String? = nil,
        subtitle: String? = nil,
        buttonTitle: String,
        buttonDisabled: Bool = false,
        action: @escaping () async -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    if let title, let subtitle {
                        header(title: title, subtitle: subtitle)
                    }
                    content()
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            bottomButton(buttonTitle, disabled: buttonDisabled || isSaving, action: action)
        }
    }

    private func bottomButton(_ title: String, disabled: Bool = false, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled)
        .padding()
    }

    private func move(by delta: Int) {
        let next = step.rawValue + delta
        if let target = Step(rawValue: min(max(next, 0), Step.allCases.count - 1)) {
            step = target
        }
    }
}
