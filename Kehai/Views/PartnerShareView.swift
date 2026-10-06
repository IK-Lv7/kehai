import SwiftUI

/// 相手ひとりに対して、自分のどの情報を見せるかを選ぶ。
struct PartnerShareView: View {
    @Environment(SessionStore.self) private var store
    let partner: PartnerState

    var body: some View {
        List {
            Section {
                toggle("充電・バッテリー", \.shareCharging)
                toggle("作業中", \.shareWorking)
                toggle("ねてる (就寝時間帯)", \.shareSleep)
            } footer: {
                Text("オフにした情報は、この人のウィジェットには出ません。ほかの人には影響しません。")
            }
        }
        .navigationTitle(partner.displayName.isEmpty ? "なまえ未設定" : partner.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ title: String, _ keyPath: WritableKeyPath<ShareSettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(
            get: { store.settings(for: partner.partnerId)[keyPath: keyPath] },
            set: { newValue in
                var settings = store.settings(for: partner.partnerId)
                settings[keyPath: keyPath] = newValue
                Task { await store.updateShareSettings(settings) }
            }
        ))
    }
}
