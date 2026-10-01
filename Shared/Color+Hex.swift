import SwiftUI

extension Color {
    /// "#F2917B" 形式から作る。読めなければコーラル。
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self.init(red: 0xF2 / 255, green: 0x91 / 255, blue: 0x7B / 255)
            return
        }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}
