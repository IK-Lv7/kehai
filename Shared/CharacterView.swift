import SwiftUI
import UIKit

enum CharacterState: String {
    case awake, sleep, tap
}

/// 選べる色。1人1色で、自分で選ぶ。
enum CharacterPalette {
    static let colors: [(name: String, hex: String)] = [
        ("コーラル", "#F2917B"),
        ("ミント", "#7CCBA8"),
        ("ラベンダー", "#AE9BEA"),
        ("バター", "#F3CF5E"),
    ]
}

/// 選べるいきもの (ドット絵)。id は character.json のキーと DB の creature に一致する。
enum Creature {
    static let all: [(id: String, name: String)] = [
        ("cat", "ねこ"), ("frog", "かえる"), ("robot", "ロボ"), ("chick", "ひよこ"),
    ]
}

/// character.json (16×16 の文字データ)。アプリとウィジェットの両方に同梱する。
struct SpriteSheet: Decodable {
    let size: Int
    let palette: [String: String]
    let shadeFactor: Double
    let sprites: [String: [String: [String]]]

    static let shared: SpriteSheet? = {
        guard
            let url = Bundle.main.url(forResource: "character", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(SpriteSheet.self, from: data)
    }()
}

enum PixelRenderer {
    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    /// 1ピクセル=1ドットの小さな画像にする。拡大は表示側で、補間なしで行う。
    static func image(creature: String, state: CharacterState, colorHex: String) -> UIImage? {
        let key = "\(creature)-\(state.rawValue)-\(colorHex)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }

        guard
            let sheet = SpriteSheet.shared,
            let rows = sheet.sprites[creature]?[state.rawValue],
            rows.count == sheet.size
        else { return nil }

        let tint = HexColor.components(colorHex)
        let shade = sheet.shadeFactor

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let side = CGFloat(sheet.size)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)

        let image = renderer.image { context in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() {
                    let color: UIColor?
                    switch ch {
                    case ".":
                        color = nil
                    case "b":
                        color = UIColor(red: tint.r, green: tint.g, blue: tint.b, alpha: 1)
                    case "s":
                        color = UIColor(red: tint.r * shade, green: tint.g * shade, blue: tint.b * shade, alpha: 1)
                    default:
                        if let hex = sheet.palette[String(ch)] {
                            let c = HexColor.components(hex)
                            color = UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
                        } else {
                            color = nil
                        }
                    }
                    if let color {
                        color.setFill()
                        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
        }
        cache[key] = image
        return image
    }
}

/// style が "dot" ならドット絵、それ以外は「まる」。
struct CharacterView: View {
    var style: String
    var creature: String
    var color: String
    var state: CharacterState = .awake

    var body: some View {
        if style == "dot",
           let image = PixelRenderer.image(creature: creature, state: state, colorHex: color) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(1, contentMode: .fit)
        } else {
            MaruView(color: Color(hex: color))
        }
    }
}
