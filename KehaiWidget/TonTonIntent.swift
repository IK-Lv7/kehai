import AppIntents
import Foundation

/// ウィジェットのキャラをタップしたときに、相手へトントンを送る。アプリは開かない。
struct TonTonIntent: AppIntent {
    static let title: LocalizedStringResource = "トントン"
    static let isDiscoverable = false

    @Parameter(title: "相手")
    var partnerId: String

    init() {}

    init(partnerId: String) {
        self.partnerId = partnerId
    }

    func perform() async throws -> some IntentResult {
        // 3秒制限・未接続などで失敗したときは、跳ねる演出を出さない。
        do {
            try await makeSupabaseClient()
                .rpc("send_tap", params: ["p_receiver": partnerId])
                .execute()
            TapFeedback.record(partnerId: partnerId)
        } catch {}
        return .result()
    }
}
