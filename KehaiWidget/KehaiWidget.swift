import AppIntents
import SwiftUI
import WidgetKit

struct KehaiEntry: TimelineEntry {
    let date: Date
    let partners: [PartnerState]
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
            let entry = KehaiEntry(date: .now, partners: partners)
            // 更新の頻度は iOS が決める。これは「このくらいで再取得してほしい」という希望。
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct PartnerCell: View {
    let partner: PartnerState

    var body: some View {
        VStack(spacing: 4) {
            Button(intent: TonTonIntent(partnerId: partner.partnerId.uuidString)) {
                MaruView(color: Color(hex: partner.color))
            }
            .buttonStyle(.plain)
            Text(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)
                .font(.caption)
                .lineLimit(1)
            (Text(partner.updatedAt, style: .relative) + Text("前"))
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                PartnerCell(partner: entry.partners[0])
            } else {
                HStack(spacing: 8) {
                    ForEach(entry.partners.prefix(4)) { partner in
                        PartnerCell(partner: partner)
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
