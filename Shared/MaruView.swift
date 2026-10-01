import SwiftUI

/// 丸い体に目と口だけの「まる」。仮素材。
struct MaruView: View {
    var color = Color(red: 0xF2 / 255, green: 0x91 / 255, blue: 0x7B / 255)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(color)
                HStack(spacing: s * 0.24) {
                    Circle().fill(.black.opacity(0.75)).frame(width: s * 0.1, height: s * 0.1)
                    Circle().fill(.black.opacity(0.75)).frame(width: s * 0.1, height: s * 0.1)
                }
                .offset(y: -s * 0.06)
                Capsule()
                    .fill(.black.opacity(0.75))
                    .frame(width: s * 0.16, height: s * 0.05)
                    .offset(y: s * 0.12)
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
