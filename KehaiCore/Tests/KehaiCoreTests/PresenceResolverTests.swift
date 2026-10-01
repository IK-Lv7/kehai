import XCTest
@testable import KehaiCore

final class PresenceResolverTests: XCTestCase {
    /// 日本時間 (UTC+9) の、指定した日時を作る。
    private func jst(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar.date(from: components)!
    }

    private func input(
        charging: Bool = false,
        battery: Int? = 80,
        working: Bool = false,
        updatedAt: Date
    ) -> PresenceInput {
        PresenceInput(
            isCharging: charging,
            batteryLevel: battery,
            isWorking: working,
            updatedAt: updatedAt
        )
    }

    // MARK: 基本

    func testAwakeByDefault() {
        let now = jst(14)
        XCTAssertEqual(PresenceResolver.resolve(input(updatedAt: now), now: now), .awake)
    }

    func testCharging() {
        let now = jst(14)
        XCTAssertEqual(PresenceResolver.resolve(input(charging: true, updatedAt: now), now: now), .charging)
    }

    func testLowBatteryCountsAsCharging() {
        let now = jst(14)
        XCTAssertEqual(PresenceResolver.resolve(input(battery: 10, updatedAt: now), now: now), .charging)
        XCTAssertEqual(PresenceResolver.resolve(input(battery: 11, updatedAt: now), now: now), .awake)
    }

    func testUnknownBatteryIsNotLow() {
        let now = jst(14)
        XCTAssertEqual(PresenceResolver.resolve(input(battery: nil, updatedAt: now), now: now), .awake)
    }

    func testWorking() {
        let now = jst(14)
        XCTAssertEqual(PresenceResolver.resolve(input(working: true, updatedAt: now), now: now), .working)
    }

    // MARK: 優先順位

    func testChargingBeatsWorking() {
        let now = jst(14)
        XCTAssertEqual(
            PresenceResolver.resolve(input(charging: true, working: true, updatedAt: now), now: now),
            .charging
        )
    }

    func testSleepingBeatsCharging() {
        let now = jst(2)
        XCTAssertEqual(PresenceResolver.resolve(input(charging: true, updatedAt: now), now: now), .sleeping)
    }

    // MARK: 寝てる

    func testNotSleepingInWindowWhenFreshAndNotCharging() {
        let now = jst(2)
        XCTAssertEqual(PresenceResolver.resolve(input(updatedAt: now), now: now), .awake)
    }

    func testSleepingInWindowWhenStale() {
        let now = jst(2)
        let stale = now.addingTimeInterval(-PresenceResolver.staleAfter)
        XCTAssertEqual(PresenceResolver.resolve(input(updatedAt: stale), now: now), .sleeping)
    }

    func testJustBeforeStaleIsNotSleeping() {
        let now = jst(2)
        let almost = now.addingTimeInterval(-PresenceResolver.staleAfter + 1)
        XCTAssertEqual(PresenceResolver.resolve(input(updatedAt: almost), now: now), .awake)
    }

    func testStaleOutsideWindowIsNotSleeping() {
        let now = jst(14)
        let stale = now.addingTimeInterval(-6 * 3600)
        XCTAssertEqual(PresenceResolver.resolve(input(updatedAt: stale), now: now), .awake)
    }

    func testChargingOutsideWindowIsNotSleeping() {
        let now = jst(14)
        XCTAssertEqual(PresenceResolver.resolve(input(charging: true, updatedAt: now), now: now), .charging)
    }

    // MARK: 就寝時間帯 (日またぎ)

    func testWindowAcrossMidnight() {
        let start = 23 * 60
        let end = 7 * 60
        func inWindow(_ date: Date) -> Bool {
            PresenceResolver.isInSleepWindow(now: date, startMinutes: start, endMinutes: end, utcOffsetMinutes: 540)
        }
        XCTAssertTrue(inWindow(jst(23, 0, day: 1)))
        XCTAssertTrue(inWindow(jst(23, 59, day: 1)))
        XCTAssertTrue(inWindow(jst(0, 0)))
        XCTAssertTrue(inWindow(jst(6, 59)))
        XCTAssertFalse(inWindow(jst(7, 0)))
        XCTAssertFalse(inWindow(jst(12, 0)))
        XCTAssertFalse(inWindow(jst(22, 59)))
    }

    func testWindowWithinOneDay() {
        func inWindow(_ date: Date) -> Bool {
            PresenceResolver.isInSleepWindow(now: date, startMinutes: 13 * 60, endMinutes: 15 * 60, utcOffsetMinutes: 540)
        }
        XCTAssertFalse(inWindow(jst(12, 59)))
        XCTAssertTrue(inWindow(jst(13, 0)))
        XCTAssertTrue(inWindow(jst(14, 59)))
        XCTAssertFalse(inWindow(jst(15, 0)))
    }

    func testEmptyWindowWhenStartEqualsEnd() {
        XCTAssertFalse(
            PresenceResolver.isInSleepWindow(now: jst(3), startMinutes: 0, endMinutes: 0, utcOffsetMinutes: 540)
        )
    }

    func testUsesPartnersLocalTimeNotViewers() {
        // 見ている側の時刻に関係なく、相手の UTC との差で換算する。
        // UTC 17:00 は、日本 (UTC+9) では 02:00 で、就寝時間帯。ニューヨーク (UTC-4) では 13:00 で、時間帯の外。
        let utc1700 = Date(timeIntervalSince1970: 1_790_960_400 - (1_790_960_400 % 86_400) + 17 * 3600)
        XCTAssertTrue(
            PresenceResolver.isInSleepWindow(now: utc1700, startMinutes: 23 * 60, endMinutes: 7 * 60, utcOffsetMinutes: 540)
        )
        XCTAssertFalse(
            PresenceResolver.isInSleepWindow(now: utc1700, startMinutes: 23 * 60, endMinutes: 7 * 60, utcOffsetMinutes: -240)
        )
    }

    func testNegativeOffsetWrapsAroundMidnight() {
        // UTC 03:00 は、UTC-5 では前日の 22:00。
        let utc0300 = Date(timeIntervalSince1970: 1_790_960_400 - (1_790_960_400 % 86_400) + 3 * 3600)
        XCTAssertTrue(
            PresenceResolver.isInSleepWindow(now: utc0300, startMinutes: 21 * 60, endMinutes: 23 * 60, utcOffsetMinutes: -300)
        )
    }

    // MARK: 時刻の文字列

    func testMinutesFromTime() {
        XCTAssertEqual(PresenceResolver.minutes(fromTime: "23:00:00"), 1380)
        XCTAssertEqual(PresenceResolver.minutes(fromTime: "07:30"), 450)
        XCTAssertEqual(PresenceResolver.minutes(fromTime: "00:00:00"), 0)
        XCTAssertNil(PresenceResolver.minutes(fromTime: "24:00:00"))
        XCTAssertNil(PresenceResolver.minutes(fromTime: "abc"))
        XCTAssertNil(PresenceResolver.minutes(fromTime: "12:60"))
    }

    // MARK: 一言

    func testLabels() {
        XCTAssertEqual(PresenceState.sleeping.label, "ねてる")
        XCTAssertEqual(PresenceState.awake.label, "おきてる")
    }
}
