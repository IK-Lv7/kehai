import Foundation

/// 公開してよい値 (publishable key)。データは RLS で守られている。
enum SupabaseConfig {
    static let url = URL(string: "https://kjbyetjgiqmkybwwtcmt.supabase.co")!
    static let publishableKey = "sb_publishable_KFYIg-3KkBuxZPQtIWwsNQ_mJ6vlTGl"
}
