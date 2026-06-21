import XCTest

final class SessionMathTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: - 활성 정산 (입력 중 / 앱 전환)

    func testActiveCreditCountsFullElapsed() {
        // 10분 연속 작업 → 600초
        XCTAssertEqual(SessionMath.activeCredit(start: t0, now: at(600)), 600, accuracy: 0.001)
    }

    func testActiveCreditClampsNegative() {
        // now가 start보다 이르면 0
        XCTAssertEqual(SessionMath.activeCredit(start: at(100), now: at(50)), 0, accuracy: 0.001)
    }

    // MARK: - 일시정지 정산 (유휴/잠금 진입 시 끝부분 유휴 제외)

    func testPausedCreditSubtractsTrailingIdle() {
        // 10분 세션, 마지막 2분은 무입력 → 8분만 인정
        XCTAssertEqual(SessionMath.pausedCredit(start: t0, now: at(600), idle: 120), 480, accuracy: 0.001)
    }

    func testPausedCreditZeroIdleEqualsFull() {
        XCTAssertEqual(SessionMath.pausedCredit(start: t0, now: at(600), idle: 0), 600, accuracy: 0.001)
    }

    func testPausedCreditFullyIdleSessionCountsZero() {
        // 세션 내내 입력이 없었으면(유휴가 세션보다 큼) 0
        XCTAssertEqual(SessionMath.pausedCredit(start: t0, now: at(600), idle: 700), 0, accuracy: 0.001)
    }

    // MARK: - 라이브 표시 정산

    func testLiveCreditBelowThresholdCountsToNow() {
        // 유휴 30초 < 임계 120초 → now까지 카운트(1초씩 증가하는 느낌)
        XCTAssertEqual(SessionMath.liveCredit(start: t0, now: at(600), idle: 30, threshold: 120), 600, accuracy: 0.001)
    }

    func testLiveCreditAtOrAboveThresholdFreezesAtLastInput() {
        // 유휴 200초 ≥ 임계 120초 → 마지막 입력 시점(now-200)에 고정
        XCTAssertEqual(SessionMath.liveCredit(start: t0, now: at(600), idle: 200, threshold: 120), 400, accuracy: 0.001)
    }

    func testLiveCreditClampsNegative() {
        XCTAssertEqual(SessionMath.liveCredit(start: t0, now: at(100), idle: 500, threshold: 120), 0, accuracy: 0.001)
    }

    // MARK: - 시나리오: 15초 롤링 틱으로 1시간 연속 작업하면 정확히 3600초

    func testRollingTicksAccumulateExactly() {
        // 엔진의 활성 틱(매 15초 activeCredit 후 sessionStart=now)을 모사
        let tick = 15.0
        var start = t0
        var total = 0.0
        var now = t0
        for _ in 0..<240 {            // 240 × 15초 = 3600초
            now = now.addingTimeInterval(tick)
            total += SessionMath.activeCredit(start: start, now: now)
            start = now               // 롤링: 정산 후 시작점 갱신
        }
        XCTAssertEqual(total, 3600, accuracy: 0.001)
    }

    // MARK: - 시나리오: 작업 → 자리비움(유휴 일시정지) → 복귀

    func testWorkThenIdlePauseThenResume() {
        let threshold = 120.0
        // 0~600초: 입력하며 작업. 매 틱 활성 정산.
        var start = t0
        var total = 0.0
        var now = t0
        for _ in 0..<40 {             // 40 × 15초 = 600초
            now = now.addingTimeInterval(15)
            total += SessionMath.activeCredit(start: start, now: now)
            start = now
        }
        XCTAssertEqual(total, 600, accuracy: 0.001)

        // 이후 자리를 비움: 600~900초 구간엔 입력 없음.
        // 750초 시점 틱에서 유휴(150초 ≥ 임계)를 감지 → pausedCredit으로
        // 마지막 입력(=600초)까지만 인정하고 정지. 추가 인정분은 0.
        let pauseNow = at(750)
        let idleAtPause = pauseNow.timeIntervalSince(at(600))   // 150초
        XCTAssertGreaterThanOrEqual(idleAtPause, threshold)
        let extra = SessionMath.pausedCredit(start: start, now: pauseNow, idle: idleAtPause)
        total += extra
        XCTAssertEqual(extra, 0, accuracy: 0.001)               // 자리비움 시간은 0
        XCTAssertEqual(total, 600, accuracy: 0.001)             // 총합은 여전히 600초
    }
}
