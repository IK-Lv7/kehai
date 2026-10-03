import SwiftUI
import UIKit

enum CharacterState: String {
    case awake, sleep, tap
    /// 充電中・作業中は、起きてる絵に目印のアイコンを重ねて見せる。
    case charge, work

    /// ドット絵の絵として使うキー (character.json)。絵があるのは awake / sleep / tap だけ。
    var spriteKey: String {
        switch self {
        case .charge, .work: CharacterState.awake.rawValue
        default: rawValue
        }
    }

    /// ドット絵に重ねる印のキー (character.json の badges)。
    var badgeKey: String? {
        switch self {
        case .charge: "charging"
        case .work: "working"
        default: nil
        }
    }
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
    /// 充電中・作業中の小さな印 (ドット絵の角に重ねる)。
    let badges: [String: [String]]?

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
        guard let rows = SpriteSheet.shared?.sprites[creature]?[state.spriteKey] else { return nil }
        return render(key: "\(creature)-\(state.spriteKey)-\(colorHex)", rows: rows, tintHex: colorHex)
    }

    /// 充電中・作業中の印 (character.json の badges)。キャラの色には染めない。
    static func badge(for state: CharacterState) -> UIImage? {
        guard let name = state.badgeKey, let rows = SpriteSheet.shared?.badges?[name] else { return nil }
        return render(key: "badge-\(name)", rows: rows, tintHex: "#FFFFFF")
    }

    private static func render(key: String, rows: [String], tintHex: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }

        guard let sheet = SpriteSheet.shared,
              let width = rows.first?.count, width > 0,
              rows.allSatisfy({ $0.count == width })
        else { return nil }

        let tint = HexColor.components(tintHex)
        let shade = sheet.shadeFactor

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: CGFloat(width), height: CGFloat(rows.count))
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

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
/// 状態は絵で伝える。寝てる=目を閉じる (ドット絵は専用の絵)、充電中・作業中=右下の印。
/// 印は、ドット絵ならドット絵の電池・ノートパソコン、まるなら SF Symbol。
struct CharacterView: View {
    var style: String
    var creature: String
    var color: String
    var state: CharacterState = .awake

    var body: some View {
        character
            .overlay(alignment: .bottomTrailing) { StateBadge(state: state, style: style) }
    }

    @ViewBuilder
    private var character: some View {
        if style == "dot",
           let image = PixelRenderer.image(creature: creature, state: state, colorHex: color) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .aspectRatio(1, contentMode: .fit)
                .overlay { PixelBadge(state: state) }
        } else {
            MaruView(color: Color(hex: color), isSleeping: state == .sleep)
        }
    }
}

/// キャラの右下に重ねる、状態の目印。
private struct StateBadge: View {
    var state: CharacterState
    var style: String

    private var symbol: (name: String, tint: Color)? {
        switch state {
        case .charge: ("bolt.fill", .yellow)
        case .work: ("laptopcomputer", .white)
        // ドット絵の「寝てる」は絵そのもので伝わるので、まるのときだけ付ける。
        case .sleep where style != "dot": ("moon.zzz.fill", .white)
        default: nil
        }
    }

    var body: some View {
        // ドット絵の充電中・作業中は、ドット絵の印 (PixelBadge) を使う。
        if style != "dot", let symbol {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height) * 0.42
                Image(systemName: symbol.name)
                    .resizable()
                    .scaledToFit()
                    .padding(side * 0.2)
                    .frame(width: side, height: side)
                    .foregroundStyle(symbol.tint)
                    .background(Circle().fill(Color(white: 0.18)))
                    .position(x: geo.size.width - side / 2, y: geo.size.height - side / 2)
            }
        }
    }
}

/// ドット絵の右下に重ねる、充電中 (電池)・作業中 (ノートパソコン) の印。
private struct PixelBadge: View {
    var state: CharacterState

    var body: some View {
        if let image = PixelRenderer.badge(for: state) {
            GeometryReader { geo in
                let width = geo.size.width * 0.42
                let height = width * image.size.height / image.size.width
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: width, height: height)
                    .position(x: geo.size.width - width / 2, y: geo.size.height - height / 2)
            }
        }
    }
}
