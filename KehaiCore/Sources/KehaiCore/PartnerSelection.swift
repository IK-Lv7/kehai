/// ウィジェットに出す相手の決め方。
public enum PartnerSelection {
    /// 選ばれた相手 (選んだ順) を、枠の数までに絞る。
    /// - 何も選ばれていない、または選ばれた相手がみな解除されているときは、つながった順に自動で出す。
    /// - 一部だけ解除されているときは、残りの相手だけを出す (勝手に別の人で埋めない)。
    public static func resolve<ID: Hashable>(available: [ID], selected: [ID], limit: Int) -> [ID] {
        guard limit > 0 else { return [] }
        let availableSet = Set(available)
        var seen = Set<ID>()
        let chosen = selected.filter { availableSet.contains($0) && seen.insert($0).inserted }
        return Array((chosen.isEmpty ? available : chosen).prefix(limit))
    }
}
