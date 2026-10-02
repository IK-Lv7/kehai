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

struct KehaiProvider: TimelineProvider {
    func placeholder(in context: Context) -> KehaiEntry {
        KehaiEntry(date: .now, partners: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (KehaiEntry) -> Void) {
        completion(KehaiEntry(date: .now, partners: PartnerCache.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KehaiEntry>) -> Void) {
        Task {
            let partners = (try? await PartnerFetcher.fetch()) ?? PartnerCache.load()
            var entries = [KehaiEntry(date: .now, partners: partners)]
            // 送った直後なら、数秒後に通常の絵へ戻す。
            if partners.contains(where: { entries[0].isTapping($0.partnerId) }) {
                entries.append(KehaiEntry(date: .now.addingTimeInterval(4), partners: partners))
            }
            // 更新の頻度は iOS が決める。これは「このくらいで再取得してほしい」という希望。
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }
}

struct PartnerCell: View {
    let partner: PartnerState
    let tapStamp: Double
    /// 送った直後だけ、トントンの絵 (手を振る・きらっ) にする。
    let isTapping: Bool
    let now: Date

    private var presence: PresenceState { partner.presence(now: now) }

    /// ドット絵の絵は、起きてる・寝てる・トントンの3つ。
    private var spriteState: CharacterState {
        if isTapping { return .tap }
        return presence == .sleeping ? .sleep : .awake
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
            Text(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)
                .font(.caption)
                .lineLimit(1)
            Text(presence.label)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

struct KehaiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KehaiEntry

    var body: some View {
        Group {
            if entry.partners.isEmpty {
                VStack(spacing: 6) {
                    MaruView()
                    Text("アプリでつながろう").font(.caption)
                }
            } else if family == .systemSmall {
                PartnerCell(
                    partner: entry.partners[0],
                    tapStamp: entry.tapStamps[entry.partners[0].partnerId] ?? 0,
                    isTapping: entry.isTapping(entry.partners[0].partnerId),
                    now: entry.date
                )
            } else {
                HStack(spacing: 8) {
                    ForEach(entry.partners.prefix(4)) { partner in
                        PartnerCell(
                            partner: partner,
                            tapStamp: entry.tapStamps[partner.partnerId] ?? 0,
                            isTapping: entry.isTapping(partner.partnerId),
                            now: entry.date
                        )
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct KehaiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KehaiWidget", provider: KehaiProvider()) { entry in
            KehaiWidgetView(entry: entry)
        }
        .configurationDisplayName("Kehai")
        .description("大切な人の気配を、そっと。キャラをタップするとトントンが届きます。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
