import Foundation

/// App Store Connect に登録するURLと同じもの。docs/ を GitHub Pages で公開している。
enum SharedLinks {
    static let privacyPolicy = URL(string: "https://ik-lv7.github.io/kehai/privacy.html")!
    static let support = URL(string: "https://ik-lv7.github.io/kehai/support.html")!
}

/// 招待リンク。LINE などで押せるよう https のページを送り、そのページからアプリ (kehai://) を開く。
enum InviteLink {
    static let scheme = "kehai"

    /// 相手に送るリンク (docs/join.html)。
    static func shareURL(code: String) -> URL {
        var components = URLComponents(string: "https://ik-lv7.github.io/kehai/join.html")!
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url!
    }

    /// kehai://join?code=KEHAI-XXXXXX からコードを取り出す。形が違うものは無視する。
    static func code(from url: URL) -> String? {
        guard
            url.scheme == scheme,
            url.host == "join",
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else { return nil }
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard (1...20).contains(code.count),
              code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return code
    }
}
