import AppIntents
import KehaiCore
import SwiftUI
import WidgetKit

struct KehaiEntry: TimelineEntry {
    let date: Date
    let partners: [PartnerState]
    /// 相手ごとの、最後にトントンを送れた時刻。値が変わると、まるが跳ねる。
    let tapStamps: [UUID: Double]

    /// 送ってから数秒の間は、トントンの絵を出す。
    func isTapping(_ partnerId: UUID) -> Bool {
        let stamp = tapStamps[partnerId] ?? 0
        return stamp > 0 && date.timeIntervalSince1970 - stamp < 4
    }

    init(date: Date, partners: [PartnerState]) {
        self.date = date
        self.partners = partners
        self.tapStamps = Dictionary(
            uniqueKeysWithValues: partners.map { ($0.partnerId, TapFeedback.stamp(for: $0.partnerId)) }
        )
    }
}

struct KehaiProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> KehaiEntry {
        KehaiEntry(date: .now, partners: [])
    }

    func snapshot(for configuration: SelectPartnersIntent, in context: Context) async -> KehaiEntry {
        KehaiEntry(
            date: .now,
            partners: select(from: PartnerCache.load(), configuration: configuration, family: context.family)
        )
    }

    func timeline(for configuration: SelectPartnersIntent, in context: Context) async -> Timeline<KehaiEntry> {
        let all = (try? await PartnerFetcher.fetch()) ?? PartnerCache.load()
        let partners = select(from: all, configuration: configuration, family: context.family)
        var entries = [KehaiEntry(date: .now, partners: partners)]
        // 送った直後なら、数秒後に通常の絵へ戻す。
        if partners.contains(where: { entries[0].isTapping($0.partnerId) }) {
            entries.append(KehaiEntry(date: .now.addingTimeInterval(4), partners: partners))
        }
        // 更新の頻度は iOS が決める。これは「このくらいで再取得してほしい」という希望。
        let next = Date().addingTimeInterval(15 * 60)
        return Timeline(entries: entries, policy: .after(next))
    }

    /// 編集画面で選んだ相手を、枠の数までに絞る。何も選ばれていなければ、つながった順。
    private func select(from all: [PartnerState], configuration: SelectPartnersIntent, family: WidgetFamily) -> [PartnerState] {
        let limit = family.partnerCapacity
        let selected = (configuration.partners ?? []).compactMap { UUID(uuidString: $0.id) }
        let ids = PartnerSelection.resolve(available: all.map(\.partnerId), selected: selected, limit: limit)
        return ids.compactMap { id in all.first { $0.partnerId == id } }
    }
}

struct PartnerCell: View {
    let partner: PartnerState
    let tapStamp: Double
    /// 送った直後だけ、トントンの絵 (手を振る・きらっ) にする。
    let isTapping: Bool
    let now: Date
    /// ロック画面は狭いので、名前を出さない。
    var showsName = true

    private var presence: PresenceState { partner.presence(now: now) }

    /// 状態は絵で見せる (寝てる・充電中・作業中)。送った直後だけトントンの絵。
    private var spriteState: CharacterState {
        isTapping ? .tap : partner.characterState(now: now)
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(intent: TonTonIntent(partnerId: partner.partnerId.uuidString)) {
                CharacterView(
                    style: partner.characterStyle,
                    creature: partner.creature,
                    color: partner.color,
                    state: spriteState
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)、\(presence.label)"
            )
            if showsName {
                Text(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}

extension WidgetFamily {
    /// 大きさごとに、並べられる人数。
    var partnerCapacity: Int {
        switch self {
        case .systemSmall, .accessoryCircular: 1
        case .accessoryRectangular: 3
        default: 4
        }
    }
}

struct KehaiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KehaiEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .accessoryRectangular:
                rectangular
            default:
                home
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var home: some View {
        if entry.partners.isEmpty {
            VStack(spacing: 6) {
                MaruView()
                Text("アプリでつながろう").font(.caption)
            }
        } else {
            HStack(spacing: 8) {
                ForEach(entry.partners.prefix(family.partnerCapacity)) { partner in
                    cell(partner)
                }
            }
        }
    }

    /// ロック画面の丸。1人のキャラだけを出す。
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let partner = entry.partners.first {
                cell(partner, showsName: false)
                    .padding(6)
            } else {
                MaruView().padding(10)
            }
        }
    }

    /// ロック画面の長方形。3人までを横に並べる。
    @ViewBuilder
    private var rectangular: some View {
        if entry.partners.isEmpty {
            Text("Kehai でつながろう")
        } else {
            HStack(spacing: 6) {
                ForEach(entry.partners.prefix(family.partnerCapacity)) { partner in
                    cell(partner, showsName: false)
                }
            }
        }
    }

    private func cell(_ partner: PartnerState, showsName: Bool = true) -> some View {
        PartnerCell(
            partner: partner,
            tapStamp: entry.tapStamps[partner.partnerId] ?? 0,
            isTapping: entry.isTapping(partner.partnerId),
            now: entry.date,
            showsName: showsName
        )
    }
}

@main
struct KehaiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KehaiWidget()
        if #available(iOS 18.0, *) {
            WorkingControl()
        }
    }
}

struct KehaiWidget: Widget {
    var body: some WidgetConfiguration {
        // 設定方式を変えたので、種類の名前も新しくした (古いウィジェットは追加し直しになる)。
        AppIntentConfiguration(
            kind: "KehaiPartnersWidget",
            intent: SelectPartnersIntent.self,
            provider: KehaiProvider()
        ) { entry in
            KehaiWidgetView(entry: entry)
        }
        .configurationDisplayName("Kehai")
        .description("大切な人の気配を、そっと。長押しの「ウィジェットを編集」で、出す相手を選べます。ロック画面にも置けます。キャラをタップするとトントンが届きます。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
