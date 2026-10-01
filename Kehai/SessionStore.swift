import AuthenticationServices
import CryptoKit
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

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case color
        case characterStyle = "character_style"
        case creature
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

    private var currentNonce: String?

    func start() async {
        isSignedIn = (try? await client.auth.session) != nil
        isLoading = false
        if isSignedIn {
            await syncMyState()
            await refreshPartners()
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
        } catch {
            message = "ログインに失敗しました: \(error.localizedDescription)"
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        isSignedIn = false
        partners = []
        profile = nil
        inviteCode = nil
        PartnerCache.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: ペアリング

    func refreshPartners() async {
        do {
            partners = try await PartnerFetcher.fetch()
            WidgetCenter.shared.reloadAllTimelines()
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
                .select("display_name, color, character_style, creature")
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
