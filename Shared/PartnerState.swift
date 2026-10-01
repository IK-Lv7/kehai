import Foundation

struct PartnerState: Codable, Identifiable {
    let partnerId: UUID
    let displayName: String
    let color: String
    let updatedAt: Date

    var id: UUID { partnerId }

    enum CodingKeys: String, CodingKey {
        case partnerId = "partner_id"
        case displayName = "display_name"
        case color
        case updatedAt = "updated_at"
    }
}

/// 最後に取れた相手の一覧。通信に失敗したとき、ウィジェットが古い表示を保つために使う。
enum PartnerCache {
    private static let key = "partnerCache"

    static func save(_ partners: [PartnerState]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(partners) {
            SharedConfig.defaults.set(data, forKey: key)
        }
    }

    static func load() -> [PartnerState] {
        guard let data = SharedConfig.defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([PartnerState].self, from: data)) ?? []
    }

    static func clear() {
        SharedConfig.defaults.removeObject(forKey: key)
    }
}

enum PartnerFetcher {
    static func fetch() async throws -> [PartnerState] {
        let partners: [PartnerState] = try await makeSupabaseClient()
            .rpc("get_partner_states").execute().value
        PartnerCache.save(partners)
        return partners
    }
}
