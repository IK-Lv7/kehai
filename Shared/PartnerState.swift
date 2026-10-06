import Foundation
import KehaiCore

struct PartnerState: Codable, Identifiable {
    let partnerId: UUID
    let displayName: String
    let color: String
    let characterStyle: String
    let creature: String
    let isCharging: Bool
    let batteryLevel: Int?
    let isWorking: Bool
    /// DB の time 型 ("23:00:00")。
    let sleepStart: String
    let sleepEnd: String
    let utcOffsetMinutes: Int
    let updatedAt: Date

    var id: UUID { partnerId }

    /// 今の状態。「寝てる」は保存せず、ここで推測する。
    func presence(now: Date) -> PresenceState {
        PresenceResolver.resolve(
            PresenceInput(
                isCharging: isCharging,
                batteryLevel: batteryLevel,
                isWorking: isWorking,
                sleepStartMinutes: PresenceResolver.minutes(fromTime: sleepStart) ?? 23 * 60,
                sleepEndMinutes: PresenceResolver.minutes(fromTime: sleepEnd) ?? 7 * 60,
                utcOffsetMinutes: utcOffsetMinutes,
                updatedAt: updatedAt
            ),
            now: now
        )
    }

    /// 今の状態を表す、キャラの絵。文字は出さず、絵だけで伝える。
    func characterState(now: Date) -> CharacterState {
        switch presence(now: now) {
        case .sleeping: .sleep
        case .charging: .charge
        case .working: .work
        case .awake: .awake
        }
    }

    enum CodingKeys: String, CodingKey {
        case partnerId = "partner_id"
        case displayName = "display_name"
        case color
        case characterStyle = "character_style"
        case creature
        case isCharging = "is_charging"
        case batteryLevel = "battery_level"
        case isWorking = "is_working"
        case sleepStart = "sleep_start"
        case sleepEnd = "sleep_end"
        case utcOffsetMinutes = "utc_offset_minutes"
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

/// 最後にトントンを送れた・受け取った時刻。ウィジェットが手を振る絵を出す演出に使う。
enum TapFeedback {
    private static func key(_ partnerId: String) -> String { "lastTap.\(partnerId)" }

    static func record(partnerId: String) {
        SharedConfig.defaults.set(Date().timeIntervalSince1970, forKey: key(partnerId))
    }

    static func stamp(for partnerId: UUID) -> Double {
        SharedConfig.defaults.double(forKey: key(partnerId.uuidString))
    }
}
