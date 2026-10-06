import AuthenticationServices
import CryptoKit
import KehaiCore
import Supabase
import SwiftUI
import UIKit
import WidgetKit

/// 自分のキャラの見た目と名前。
struct MyProfile: Codable {
    var displayName: String
    var color: String
    var characterStyle: String
    var creature: String
    var receiveTaps: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case color
        case characterStyle = "character_style"
        case creature
        case receiveTaps = "receive_taps"
    }
}

/// 相手ひとりに対して、自分のどの情報を見せるか。
struct ShareSettings: Codable, Equatable {
    var viewerId: UUID
    var shareCharging = true
    var shareWorking = true
    var shareSleep = true

    enum CodingKeys: String, CodingKey {
        case viewerId = "viewer_id"
        case shareCharging = "share_charging"
        case shareWorking = "share_working"
        case shareSleep = "share_sleep"
    }
}

/// 自分の状態のうち、画面で変えられるもの。
private struct MyStateRow: Decodable {
    let isWorking: Bool
    let sleepStart: String
    let sleepEnd: String

    enum CodingKeys: String, CodingKey {
        case isWorking = "is_working"
        case sleepStart = "sleep_start"
        case sleepEnd = "sleep_end"
    }
}

@MainActor
@Observable
final class SessionStore {
    let client = makeSupabaseClient()

    var isLoading = true
    var isSignedIn = false
    var partners: [PartnerState] = []
    var profile: MyProfile?
    var inviteCode: String?
    var message: String?
    var isWorking = false
    /// 就寝時間帯 (0時からの分)。
    var sleepStartMinutes = 23 * 60
    var sleepEndMinutes = 7 * 60
    var shareSettings: [UUID: ShareSettings] = [:]

    private var currentNonce: String?

    func start() async {
        isSignedIn = (try? await client.auth.session) != nil
        isLoading = false
        if isSignedIn {
            await syncMyState()
            await refreshPartners()
            await PushRegistrar.uploadStored()
        }
    }

    // MARK: Sign in with Apple

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = []
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) async {
        do {
            let authorization = try result.get()
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                message = "ログインに失敗しました"
                return
            }
            try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
            isSignedIn = true
            await refreshPartners()
            await PushRegistrar.uploadStored()
        } catch {
            message = "ログインに失敗しました: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        await PushRegistrar.unregister()
        try? await client.auth.signOut()
        isSignedIn = false
        partners = []
        profile = nil
        inviteCode = nil
        shareSettings = [:]
        PartnerCache.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// アカウントと、それに紐づくデータをすべて消す。成功したらログアウト状態に戻る。
    func deleteAccount() async {
        do {
            try await client.rpc("delete_account").execute()
            await signOut()
            message = "アカウントを削除しました"
        } catch {
            message = "アカウントを削除できませんでした: \(error.localizedDescription)"
        }
    }

    // MARK: ペアリング

    func refreshPartners() async {
        do {
            partners = try await PartnerFetcher.fetch()
            WidgetCenter.shared.reloadAllTimelines()
            // 誰かとつながってから、通知の許可を聞く (つながる前は、聞く理由が無い)。
            if !partners.isEmpty, profile?.receiveTaps ?? true {
                await PushRegistrar.requestAndRegister()
            }
        } catch {
            message = "なかまの取得に失敗しました: \(error.localizedDescription)"
        }
    }

    func createInvite() async {
        do {
            inviteCode = try await client.rpc("create_invite").execute().value
        } catch {
            message = "招待コードを作れませんでした: \(error.localizedDescription)"
        }
    }

    func redeem(code: String) async {
        do {
            try await client.rpc("redeem_invite", params: ["p_code": code]).execute()
            message = "つながりました"
            await refreshPartners()
        } catch {
            message = Self.describe(error)
        }
    }

    func remove(_ partner: PartnerState) async {
        do {
            try await client.rpc("remove_pair", params: ["p_partner": partner.partnerId.uuidString]).execute()
            await refreshPartners()
        } catch {
            message = "解除できませんでした: \(error.localizedDescription)"
        }
    }

    /// 自分の充電・バッテリー・時差を送る。画面を開いたときと、充電状態が変わったときに呼ぶ。
    func syncMyState() async {
        guard isSignedIn, let id = client.auth.currentUser?.id else { return }
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        struct Payload: Encodable {
            let user_id: UUID
            let is_charging: Bool
            let battery_level: Int?
            let utc_offset_minutes: Int
        }
        let level = device.batteryLevel  // 取れないときは -1
        let payload = Payload(
            user_id: id,
            is_charging: device.batteryState == .charging || device.batteryState == .full,
            battery_level: level >= 0 ? Int((level * 100).rounded()) : nil,
            utc_offset_minutes: TimeZone.current.secondsFromGMT() / 60
        )
        do {
            try await client.from("user_states").upsert(payload).execute()
        } catch {
            // 状態の同期は黙って失敗してよい (次に開いたときに、また送る)。
        }
    }

    func loadProfile() async {
        guard let id = client.auth.currentUser?.id else { return }
        do {
            profile = try await client.from("profiles")
                .select("display_name, color, character_style, creature, receive_taps")
                .eq("id", value: id)
                .single()
                .execute()
                .value
        } catch {
            message = "プロフィールを取得できませんでした: \(error.localizedDescription)"
        }
    }

    func updateAppearance(style: String, creature: String, color: String) async {
        guard let id = client.auth.currentUser?.id else { return }
        do {
            try await client.from("profiles")
                .update(["character_style": style, "creature": creature, "color": color])
                .eq("id", value: id)
                .execute()
            profile?.characterStyle = style
            profile?.creature = creature
            profile?.color = color
        } catch {
            message = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    func setReceiveTaps(_ on: Bool) async {
        guard let id = client.auth.currentUser?.id else { return }
        do {
            try await client.from("profiles")
                .update(["receive_taps": on])
                .eq("id", value: id)
                .execute()
            profile?.receiveTaps = on
            if on { await PushRegistrar.requestAndRegister() }
        } catch {
            message = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    // MARK: 自分の状態 (作業中・就寝時間帯)

    func loadMyState() async {
        guard let id = client.auth.currentUser?.id else { return }
        do {
            let row: MyStateRow = try await client.from("user_states")
                .select("is_working, sleep_start, sleep_end")
                .eq("user_id", value: id)
                .single()
                .execute()
                .value
            isWorking = row.isWorking
            sleepStartMinutes = PresenceResolver.minutes(fromTime: row.sleepStart) ?? sleepStartMinutes
            sleepEndMinutes = PresenceResolver.minutes(fromTime: row.sleepEnd) ?? sleepEndMinutes
        } catch {
            message = "状態を取得できませんでした: \(error.localizedDescription)"
        }
    }

    func setWorking(_ on: Bool) async {
        do {
            try await MyStateWriter.setWorking(on)
            isWorking = on
        } catch {
            message = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    func updateSleepWindow(startMinutes: Int, endMinutes: Int) async {
        guard let id = client.auth.currentUser?.id else { return }
        func time(_ minutes: Int) -> String {
            String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
        }
        do {
            try await client.from("user_states")
                .update(["sleep_start": time(startMinutes), "sleep_end": time(endMinutes)])
                .eq("user_id", value: id)
                .execute()
            sleepStartMinutes = startMinutes
            sleepEndMinutes = endMinutes
        } catch {
            message = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    // MARK: 見せる情報 (相手ごと)

    func settings(for partnerId: UUID) -> ShareSettings {
        shareSettings[partnerId] ?? ShareSettings(viewerId: partnerId)
    }

    func loadShareSettings() async {
        do {
            let rows: [ShareSettings] = try await client.rpc("get_share_settings").execute().value
            shareSettings = Dictionary(uniqueKeysWithValues: rows.map { ($0.viewerId, $0) })
        } catch {
            message = "設定を取得できませんでした: \(error.localizedDescription)"
        }
    }

    func updateShareSettings(_ settings: ShareSettings) async {
        struct Params: Encodable {
            let p_viewer: UUID
            let p_charging: Bool
            let p_working: Bool
            let p_sleep: Bool
        }
        let previous = shareSettings[settings.viewerId]
        shareSettings[settings.viewerId] = settings
        do {
            try await client.rpc("set_share_settings", params: Params(
                p_viewer: settings.viewerId,
                p_charging: settings.shareCharging,
                p_working: settings.shareWorking,
                p_sleep: settings.shareSleep
            )).execute()
        } catch {
            shareSettings[settings.viewerId] = previous
            message = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    func updateDisplayName(_ name: String) async {
        guard let id = client.auth.currentUser?.id else { return }
        do {
            try await client.from("profiles")
                .update(["display_name": name])
                .eq("id", value: id)
                .execute()
            profile?.displayName = name
            message = "名前を保存しました"
        } catch {
            message = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    // MARK: 補助

    private static func describe(_ error: Error) -> String {
        let text = "\(error)"
        if text.contains("invalid_or_expired_code") { return "コードが違うか、期限が切れています" }
        if text.contains("cannot_pair_with_self") { return "自分のコードにはつながれません" }
        if text.contains("already_paired") { return "すでにつながっています" }
        if text.contains("too_many_partners") { return "これ以上つながれません (最大4人)" }
        return "つなげませんでした: \(error.localizedDescription)"
    }

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
