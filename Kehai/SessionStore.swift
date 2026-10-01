import AuthenticationServices
import CryptoKit
import Supabase
import SwiftUI

struct PartnerState: Decodable, Identifiable {
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

@MainActor
@Observable
final class SessionStore {
    let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey
    )

    var isLoading = true
    var isSignedIn = false
    var partners: [PartnerState] = []
    var inviteCode: String?
    var message: String?

    private var currentNonce: String?

    func start() async {
        isSignedIn = (try? await client.auth.session) != nil
        isLoading = false
        if isSignedIn { await refreshPartners() }
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
        inviteCode = nil
    }

    // MARK: ペアリング

    func refreshPartners() async {
        do {
            partners = try await client.rpc("get_partner_states").execute().value
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

    func updateDisplayName(_ name: String) async {
        guard let id = client.auth.currentUser?.id else { return }
        do {
            try await client.from("profiles")
                .update(["display_name": name])
                .eq("id", value: id)
                .execute()
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
