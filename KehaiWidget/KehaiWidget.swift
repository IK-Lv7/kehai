import SwiftUI
import WidgetKit

struct KehaiEntry: TimelineEntry {
    let date: Date
}

struct KehaiProvider: TimelineProvider {
    func placeholder(in context: Context) -> KehaiEntry {
        KehaiEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (KehaiEntry) -> Void) {
        completion(KehaiEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KehaiEntry>) -> Void) {
        completion(Timeline(entries: [KehaiEntry(date: .now)], policy: .never))
    }
}

struct KehaiWidgetView: View {
    let entry: KehaiEntry

    var body: some View {
        VStack(spacing: 6) {
            MaruView()
            Text("おきてる").font(.caption)
            Text(entry.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
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
        .description("大切な人の気配を、そっと。")
        .supportedFamilies([.systemSmall])
    }
}
