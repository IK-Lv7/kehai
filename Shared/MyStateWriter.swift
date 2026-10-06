import Foundation

/// 自分の「作業中」を読み書きする。アプリ本体と、コントロールセンターのボタン (別プロセス) の両方から使う。
enum MyStateWriter {
    private struct WorkingPayload: Encodable {
        let is_working: Bool
    }

    private struct WorkingRow: Decodable {
        let is_working: Bool
    }

    static func setWorking(_ value: Bool) async throws {
        let client = makeSupabaseClient()
        let id = try await client.auth.session.user.id
        try await client.from("user_states")
            .update(WorkingPayload(is_working: value))
            .eq("user_id", value: id)
            .execute()
    }

    static func isWorking() async -> Bool {
        do {
            let client = makeSupabaseClient()
            let id = try await client.auth.session.user.id
            let row: WorkingRow = try await client.from("user_states")
                .select("is_working")
                .eq("user_id", value: id)
                .single()
                .execute()
                .value
            return row.is_working
        } catch {
            return false
        }
    }
}
