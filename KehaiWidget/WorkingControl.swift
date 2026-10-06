import AppIntents
import SwiftUI
import WidgetKit

/// コントロールセンターの1タップで、「作業中」をオン・オフする (iOS 18 以降)。
@available(iOS 18.0, *)
struct WorkingControl: ControlWidget {
    static let kind = "KehaiWorkingControl"

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            await MyStateWriter.isWorking()
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isWorking in
            ControlWidgetToggle(
                "さぎょうちゅう",
                isOn: isWorking,
                action: SetWorkingIntent()
            ) { isOn in
                Label(isOn ? "オン" : "オフ", systemImage: "laptopcomputer")
            }
        }
        .displayName("さぎょうちゅう")
        .description("相手のウィジェットに、作業中のサインを出します。")
    }
}

@available(iOS 18.0, *)
struct SetWorkingIntent: SetValueIntent {
    static let title: LocalizedStringResource = "さぎょうちゅう"

    @Parameter(title: "オン")
    var value: Bool

    func perform() async throws -> some IntentResult {
        try await MyStateWriter.setWorking(value)
        return .result()
    }
}
