import Foundation

/// 한 앱의 하루 누적 사용시간.
struct AppUsage: Codable, Identifiable {
    let bundleId: String
    var displayName: String
    var seconds: Double

    var id: String { bundleId }
}

/// 하루치 기록. 날짜별 JSON 파일 1개에 대응.
struct DayRecord: Codable {
    let date: String                 // "yyyy-MM-dd"
    var apps: [String: AppUsage]     // bundleId -> usage

    init(date: String, apps: [String: AppUsage] = [:]) {
        self.date = date
        self.apps = apps
    }

    var totalSeconds: Double {
        apps.values.reduce(0) { $0 + $1.seconds }
    }

    /// 특정 앱에 시간을 누적(없으면 생성).
    mutating func add(bundleId: String, displayName: String, seconds: Double) {
        guard seconds > 0 else { return }
        if var existing = apps[bundleId] {
            existing.seconds += seconds
            existing.displayName = displayName
            apps[bundleId] = existing
        } else {
            apps[bundleId] = AppUsage(bundleId: bundleId, displayName: displayName, seconds: seconds)
        }
    }
}

/// 카테고리 관련 상수. 사용자는 카테고리를 추가/수정/삭제할 수 있으나,
/// `기본`(fallback)은 항상 존재하며 삭제할 수 없다.
enum DefaultCategory {
    static let editing = "편집 작업"
    static let work = "업무"
    static let ai = "AI 툴"
    static let fallback = "기본"          // 보호 카테고리(삭제·이름변경 불가, 항상 마지막)

    /// 최초 기본 목록(fallback 포함, fallback이 마지막).
    static let initialList = [editing, work, ai, fallback]

    /// 카테고리 이름 최대 글자수.
    static let maxNameLength = 12
}

/// 추적에서 제외할 시스템 프로세스(잠금/로그인/스크린세이버 등 = 실제 작업 아님).
enum SystemApps {
    static let ignoredBundleIds: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.SecurityAgent",
        "com.apple.WindowManager",
        "com.apple.UserNotificationCenter",
        "com.zzanggi.MyWorkTracker",     // 자기 자신
    ]

    static func isIgnored(bundleId: String, displayName: String) -> Bool {
        if ignoredBundleIds.contains(bundleId) { return true }
        let s = (bundleId + " " + displayName).lowercased()
        return s.contains("loginwindow")
            || s.contains("screensaverengine")
            || s.contains("screensaver engine")
            || s.contains("notificationcenter")   // UserNotificationCenter 등 알림 프로세스
            || s.contains("myworktracker")         // 자기 자신(이전 이름)
            || s.contains("crumble")               // 자기 자신(현재 이름)
    }
}

/// 한국어 날짜 포맷("yyyy년 M월 d일"). DateFormatter는 생성 비용이 커서 재사용한다.
let koreanDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "yyyy년 M월 d일"
    return f
}()

/// 시:분:초 포맷 헬퍼.
func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return "\(h)시간 \(m)분 \(s)초" }
    if m > 0 { return "\(m)분 \(s)초" }
    return "\(s)초"
}
