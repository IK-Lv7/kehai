import Foundation

struct PartnerState: Codable, Identifiable {
    let partnerId: UUID
    let displayName: String
    let color: String
    let characterStyle: String
    let creature: String
    let updatedAt: Date

    var id: UUID { partnerId }

    enum CodingKeys: String, CodingKey {
        case partnerId = "partner_id"
        case displayName = "display_name"
        case color
        case characterStyle = "character_style"
        case creature
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

/// 最後にトントンを送れた時刻。ウィジェットが「ぽん」と跳ねる演出に使う。
enum TapFeedback {
    private static func key(_ partnerId: String) -> String { "lastTap.\(partnerId)" }

    static func record(partnerId: String) {
        SharedConfig.defaults.set(Date().timeIntervalSince1970, forKey: key(partnerId))
    }

    static func stamp(for partnerId: UUID) -> Double {
        SharedConfig.defaults.double(forKey: key(partnerId.uuidString))
    }
}
