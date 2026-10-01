import Foundation
import Supabase

/// アプリとウィジェットで共有する設定と、Supabase への接続。
enum SharedConfig {
    static let appGroup = "group.com.hinodeentertainment.kehai"
    /// 公開してよい値 (publishable key)。データは RLS で守られている。
    static let supabaseURL = URL(string: "https://kjbyetjgiqmkybwwtcmt.supabase.co")!
    static let publishableKey = "sb_publishable_KFYIg-3KkBuxZPQtIWwsNQ_mJ6vlTGl"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}

/// ログイン情報を App Group に置き、ウィジェット (別プロセス) からも使えるようにする。
struct SharedAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {
        SharedConfig.defaults.set(value, forKey: key)
    }

    func retrieve(key: String) throws -> Data? {
        SharedConfig.defaults.data(forKey: key)
    }

    func remove(key: String) throws {
        SharedConfig.defaults.removeObject(forKey: key)
    }
}

func makeSupabaseClient() -> SupabaseClient {
    SupabaseClient(
        supabaseURL: SharedConfig.supabaseURL,
        supabaseKey: SharedConfig.publishableKey,
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(storage: SharedAuthStorage())
        )
    )
}
