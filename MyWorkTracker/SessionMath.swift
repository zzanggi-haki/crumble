import Foundation

/// 작업시간 정산의 핵심 수학. 시스템 의존이 전혀 없어 결정론적으로 테스트 가능.
/// TrackingEngine과 라이브 표시(liveDelta)가 모두 이 함수를 사용한다.
enum SessionMath {
    /// 활성 정산(롤링/앱 전환): 세션 시작부터 now까지 전부 인정.
    /// now가 start보다 이르면 0(음수 클램프).
    static func activeCredit(start: Date, now: Date) -> Double {
        max(0, now.timeIntervalSince(start))
    }

    /// 일시정지 정산(유휴/잠금/슬립 진입): 마지막 입력 시점(now - idle)까지만 인정.
    /// 유휴 구간은 작업으로 치지 않는다.
    static func pausedCredit(start: Date, now: Date, idle: TimeInterval) -> Double {
        max(0, now.addingTimeInterval(-idle).timeIntervalSince(start))
    }

    /// 라이브 표시용: 유휴 한계 미만이면 now까지(1초씩 증가), 한계 이상이면
    /// 마지막 입력 시점에 고정(폭주 방지). 정지 상태는 호출부에서 제외.
    static func liveCredit(start: Date, now: Date, idle: TimeInterval, threshold: TimeInterval) -> Double {
        let end = idle >= threshold ? now.addingTimeInterval(-idle) : now
        return max(0, end.timeIntervalSince(start))
    }
}
