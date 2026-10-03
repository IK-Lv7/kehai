import AppIntents
import Foundation
import WidgetKit

/// ウィジェットの編集画面に出る、相手の選択肢。
struct PartnerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "なかま"
    static let defaultQuery = PartnerQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PartnerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PartnerEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PartnerEntity] {
        await all()
    }

    private func all() async -> [PartnerEntity] {
        let partners = (try? await PartnerFetcher.fetch()) ?? PartnerCache.load()
        return partners.map {
            PartnerEntity(
                id: $0.partnerId.uuidString,
                name: $0.displayName.isEmpty ? "なまえ未設定" : $0.displayName
            )
        }
    }
}

/// 「ウィジェットを編集」で、出す相手を選ぶ。小サイズは1人、中サイズは最大4人。
struct SelectPartnersIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "表示するなかま"
    static let description = IntentDescription("ウィジェットに出す相手を選びます。選ばないと、つながった順に出ます。")

    @Parameter(title: "なかま", size: [.systemSmall: 1, .systemMedium: 4])
    var partners: [PartnerEntity]?

    init() {}
}
