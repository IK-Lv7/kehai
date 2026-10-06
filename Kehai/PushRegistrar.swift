import Foundation
import UIKit
import UserNotifications

/// プッシュ通知の端末トークンを、サーバーに登録・解除する。
enum PushRegistrar {
    private static let tokenKey = "pushToken"

    #if DEBUG
    private static let environment = "sandbox"
    #else
    private static let environment = "production"
    #endif

    /// 通知の許可を (初回だけ) 聞き、許可されたらトークンの発行を依頼する。
    @MainActor
    static func requestAndRegister() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func didReceive(token: Data) async {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        SharedConfig.defaults.set(hex, forKey: tokenKey)
        await uploadStored()
    }

    /// 保存済みのトークンを、今のアカウントに結びつける。ログイン直後にも呼ぶ。
    static func uploadStored() async {
        guard let token = SharedConfig.defaults.string(forKey: tokenKey) else { return }
        _ = try? await makeSupabaseClient()
            .rpc("register_device_token", params: ["p_token": token, "p_environment": environment])
            .execute()
    }

    /// ログアウトの前に呼ぶ。別のアカウントに切り替えても、前の人の通知が届かないようにする。
    static func unregister() async {
        guard let token = SharedConfig.defaults.string(forKey: tokenKey) else { return }
        _ = try? await makeSupabaseClient()
            .rpc("unregister_device_token", params: ["p_token": token])
            .execute()
    }
}
