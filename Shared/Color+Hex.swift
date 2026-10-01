import SwiftUI

enum HexColor {
    /// "#F2917B" 形式を 0〜1 の RGB にする。読めなければコーラル。
    static func components(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return (0xF2 / 255, 0x91 / 255, 0x7B / 255)
        }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

extension Color {
    init(hex: String) {
        let c = HexColor.components(hex)
        self.init(red: c.r, green: c.g, blue: c.b)
    }
}
