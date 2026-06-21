import CoreGraphics
import Foundation

/// 사용자 입력 유휴 시간 조회. 상시 폴링하지 않고 필요할 때만 질의한다.
/// 접근성/입력 모니터링 권한이 필요 없는 CGEventSource API 사용.
enum IdleMonitor {
    /// 마지막 입력(키보드/마우스 등) 이후 경과한 초.
    static func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                eventType: .init(rawValue: ~0)!)
    }
}
