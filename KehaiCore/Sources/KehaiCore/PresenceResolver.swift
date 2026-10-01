import Foundation

/// 相手のキャラに出す状態。
public enum PresenceState: String, Equatable, Sendable {
    case sleeping  // 寝てる
    case charging  // 充電中
    case working   // 作業中
    case awake     // 起きてる

    /// ウィジェットに出す一言。
    public var label: String {
        switch self {
        case .sleeping: "ねてる"
        case .charging: "じゅうでん"
        case .working: "さぎょうちゅう"
        case .awake: "おきてる"
        }
    }
}

/// 状態の判定に使う、相手の最新の情報。
public struct PresenceInput: Equatable, Sendable {
    public var isCharging: Bool
    public var batteryLevel: Int?
    public var isWorking: Bool
    /// 就寝時間帯 (本人の現地時間、0時からの分)。
    public var sleepStartMinutes: Int
    public var sleepEndMinutes: Int
    /// 本人の現地時間と UTC との差 (分)。日本は 540。
    public var utcOffsetMinutes: Int
    /// 状態の最終更新。
    public var updatedAt: Date

    public init(
        isCharging: Bool,
        batteryLevel: Int?,
        isWorking: Bool,
        sleepStartMinutes: Int = 23 * 60,
        sleepEndMinutes: Int = 7 * 60,
        utcOffsetMinutes: Int = 540,
        updatedAt: Date
    ) {
        self.isCharging = isCharging
        self.batteryLevel = batteryLevel
        self.isWorking = isWorking
        self.sleepStartMinutes = sleepStartMinutes
        self.sleepEndMinutes = sleepEndMinutes
        self.utcOffsetMinutes = utcOffsetMinutes
        self.updatedAt = updatedAt
    }
}

/// 状態の判定ルール。優先順位は上から「寝てる」「充電中」「作業中」「起きてる」。
/// 「寝てる」は保存せず、見る側がここで推測する。
public enum PresenceResolver {
    /// これ以上更新が止まっていたら、「止まっている」とみなす。
    public static let staleAfter: TimeInterval = 60 * 60
    /// これ以下なら、充電していなくても「充電中」の扱い (バッテリー残りわずか)。
    public static let lowBatteryLevel = 10

    public static func resolve(_ input: PresenceInput, now: Date) -> PresenceState {
        let inSleepWindow = isInSleepWindow(
            now: now,
            startMinutes: input.sleepStartMinutes,
            endMinutes: input.sleepEndMinutes,
            utcOffsetMinutes: input.utcOffsetMinutes
        )
        let isStale = now.timeIntervalSince(input.updatedAt) >= staleAfter

        if inSleepWindow && (input.isCharging || isStale) {
            return .sleeping
        }
        if input.isCharging || isLowBattery(input.batteryLevel) {
            return .charging
        }
        if input.isWorking {
            return .working
        }
        return .awake
    }

    static func isLowBattery(_ level: Int?) -> Bool {
        guard let level else { return false }
        return level <= lowBatteryLevel
    }

    /// 就寝時間帯に入っているか。23:00〜7:00 のように日をまたぐ範囲にも対応する。
    /// 開始と終了が同じなら、時間帯は無いものとする。
    public static func isInSleepWindow(
        now: Date,
        startMinutes: Int,
        endMinutes: Int,
        utcOffsetMinutes: Int
    ) -> Bool {
        guard startMinutes != endMinutes else { return false }
        let utcMinutes = Int((now.timeIntervalSince1970 / 60).rounded(.down))
        let local = ((utcMinutes + utcOffsetMinutes) % 1440 + 1440) % 1440
        if startMinutes < endMinutes {
            return local >= startMinutes && local < endMinutes
        } else {
            return local >= startMinutes || local < endMinutes
        }
    }

    /// DB の time 型の文字列 ("23:00:00" や "07:30") を、0時からの分にする。
    public static func minutes(fromTime text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        return h * 60 + m
    }
}
