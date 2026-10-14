import SwiftUI

/// 自分のキャラの見た目を選ぶ (プレビュー・キャラ一覧・色)。保存は呼び出し側で行う。
struct CharacterEditor: View {
    @Binding var style: String
    @Binding var creature: String
    @Binding var color: String

    var body: some View {
        VStack(spacing: 16) {
            CharacterView(style: style, creature: creature, color: color)
                .frame(width: 96, height: 96)
            characterGrid
            palette
        }
        .frame(maxWidth: .infinity)
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
                .accessibilityAddTraits(selectedKey == item.key ? .isSelected : [])
            }
        }
    }

    private var palette: some View {
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
                .accessibilityAddTraits(color == item.hex ? .isSelected : [])
            }
        }
    }
}
