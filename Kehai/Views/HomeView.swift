import SwiftUI

/// ホーム。なかまのキャラを大きく並べる。タップでトントン、長押しでほかのあいさつ・設定。
/// 自分のキャラや通知などの設定は、右上の歯車から。
struct HomeView: View {
    @Environment(SessionStore.self) private var store
    @State private var showingInvite = false
    @State private var showingHistory = false
    @State private var partnerToRemove: PartnerState?
    @State private var sharePartnerId: UUID?
    /// 送った (届いた) 直後だけ、手を振る絵にする。
    @State private var tappingIds: Set<UUID> = []
    @State private var hapticCount = 0

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.partners.isEmpty {
                    emptyState
                } else {
                    partnerGrid
                }
            }
            .navigationTitle("Kehai")
            .refreshable {
                await store.refreshPartners()
                await store.loadRecentTaps()
            }
            .toolbar { toolbar }
            .sheet(isPresented: $showingInvite) { InviteView() }
            .sheet(isPresented: $showingHistory) { TapHistoryView() }
            .navigationDestination(item: $sharePartnerId) { id in
                if let partner = store.partners.first(where: { $0.partnerId == id }) {
                    PartnerShareView(partner: partner)
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
                Text("もう一度つながるには、新しい招待リンクが必要です。")
            }
            .sensoryFeedback(.impact(weight: .light), trigger: hapticCount)
            .onReceive(NotificationCenter.default.publisher(for: .tapReceived)) { note in
                if let senderId = (note.object as? String).flatMap(UUID.init(uuidString:)) {
                    bounce(senderId)
                }
                Task {
                    await store.loadRecentTaps()
                    await store.refreshPartners()
                }
            }
        }
    }

    // MARK: なかま

    private var partnerGrid: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(store.partners) { partner in
                    Button {
                        send(.tonton, to: partner)
                    } label: {
                        PartnerTile(partner: partner, isTapping: tappingIds.contains(partner.partnerId))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { menu(for: partner) }
                    .accessibilityHint("タップでトントン。長押しで、ほかのあいさつ")
                }
                // つながれる上限 (4人) までは、招待の枠を出す。
                if store.partners.count < 4 {
                    Button {
                        showingInvite = true
                    } label: {
                        InviteTile()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("なかまを招待")
                }
            }
            Text("タップでトントン・長押しでほかのあいさつ")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private func menu(for partner: PartnerState) -> some View {
        ForEach(TapKind.allCases.filter { $0 != .tonton }) { kind in
            Button {
                send(kind, to: partner)
            } label: {
                Label(kind.title, systemImage: kind.symbol)
            }
        }
        Divider()
        Button {
            sharePartnerId = partner.partnerId
        } label: {
            Label("見せる情報", systemImage: "eye")
        }
        Button(role: .destructive) {
            partnerToRemove = partner
        } label: {
            Label("つながりを解除", systemImage: "person.badge.minus")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            MaruView()
                .frame(width: 140, height: 140)
            Text("まだ誰ともつながっていません")
                .font(.headline)
            Text("大切な人を招待すると、ここにその人の気配が並びます。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingInvite = true
            } label: {
                Label("なかまを招待する", systemImage: "person.badge.plus")
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.top, 80)
        .padding(.horizontal, 32)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .overlay(alignment: .topTrailing) {
                        if store.unseenTapCount > 0 {
                            Circle()
                                .fill(.red)
                                .frame(width: 9, height: 9)
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .accessibilityLabel(store.unseenTapCount > 0 ? "トントンの履歴 (新着あり)" : "トントンの履歴")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                showingInvite = true
            } label: {
                Image(systemName: "person.badge.plus")
            }
            .accessibilityLabel("なかまを招待")
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("設定")
        }
    }

    // MARK: 送る

    private func send(_ kind: TapKind, to partner: PartnerState) {
        hapticCount += 1
        Task {
            if await store.sendTap(to: partner, kind: kind) {
                bounce(partner.partnerId)
            }
        }
    }

    private func bounce(_ id: UUID) {
        tappingIds.insert(id)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            tappingIds.remove(id)
        }
    }
}

/// なかま1人の枠。キャラの絵だけで状態が分かるようにし、文字は名前だけ。
private struct PartnerTile: View {
    let partner: PartnerState
    let isTapping: Bool

    var body: some View {
        VStack(spacing: 8) {
            CharacterView(
                style: partner.characterStyle,
                creature: partner.creature,
                color: partner.color,
                state: isTapping ? .tap : partner.characterState(now: Date())
            )
            .frame(width: 112, height: 112)
            .scaleEffect(isTapping ? 1.12 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.4), value: isTapping)
            Text(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)
                .font(.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(.fill.tertiary))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)、\(partner.presence(now: Date()).label)"
        )
    }
}

/// まだ空いている枠。押すと招待のシートを開く。
private struct InviteTile: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 36, weight: .semibold))
                .frame(width: 112, height: 112)
            Text("招待する")
                .font(.headline)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(.tertiary)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}
