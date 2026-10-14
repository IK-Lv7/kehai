import SwiftUI

/// 直近7日のトントン (あいさつ) のやりとり。自分が送ったものには、相手が見たら「見た」が付く。
struct TapHistoryView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 開いた時点で未読だったもの。見たことにした後も、この画面では目印を残す。
    @State private var newIds: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                if store.recentTaps.isEmpty {
                    Text("この7日間のやりとりはありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.recentTaps) { tap in
                    row(tap)
                }
            }
            .navigationTitle("トントンの履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .refreshable { await store.loadRecentTaps() }
            .task {
                await store.loadRecentTaps()
                newIds = Set(store.recentTaps.filter { !$0.isMine && $0.seenAt == nil }.map(\.id))
                await store.markTapsSeen()
            }
        }
    }

    private func row(_ tap: RecentTap) -> some View {
        let partner = store.partners.first { $0.partnerId == tap.partnerId }
        let name = partner.map { $0.displayName.isEmpty ? "なまえ未設定" : $0.displayName } ?? "なかま"
        return HStack(spacing: 12) {
            if let partner {
                CharacterView(style: partner.characterStyle, creature: partner.creature, color: partner.color)
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tap.isMine ? "\(name)へ \(tap.tapKind.title)" : "\(name)から \(tap.tapKind.title)")
                    .fontWeight(newIds.contains(tap.id) ? .bold : .regular)
                Text(tap.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if tap.isMine, tap.seenAt != nil {
                Label("見た", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: tap.tapKind.symbol)
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }
}
