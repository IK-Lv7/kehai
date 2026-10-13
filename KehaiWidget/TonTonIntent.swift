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
        await TapSender.send(to: partnerId)
        return .result()
    }
}
