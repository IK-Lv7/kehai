import Foundation

/// 送れるあいさつの種類。DB の taps.kind と一致する。
enum TapKind: String, CaseIterable, Codable, Identifiable {
    case tonton, ohayo, otsukare, oyasumi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tonton: "トントン"
        case .ohayo: "おはよう"
        case .otsukare: "おつかれ"
        case .oyasumi: "おやすみ"
        }
    }

    var symbol: String {
        switch self {
        case .tonton: "hand.tap.fill"
        case .ohayo: "sun.max.fill"
        case .otsukare: "cup.and.saucer.fill"
        case .oyasumi: "moon.stars.fill"
        }
    }
}

/// トントン (あいさつ) を送る。アプリ本体とウィジェットの両方から使う。
enum TapSender {
    private struct Params: Encodable {
        let p_receiver: String
        let p_kind: String
    }

    /// 送れたら true。3秒制限・未接続などで失敗したら false (跳ねる演出は出さない)。
    @discardableResult
    static func send(to partnerId: String, kind: TapKind = .tonton) async -> Bool {
        do {
            try await makeSupabaseClient()
                .rpc("send_tap_with_kind", params: Params(p_receiver: partnerId, p_kind: kind.rawValue))
                .execute()
            TapFeedback.record(partnerId: partnerId)
            return true
        } catch {
            return false
        }
    }
}
