import Foundation
import Combine
import AppKit
import UserNotifications

/// 측정 핵심. 최전면 앱 세션을 이벤트 기반으로 누적하고, 유휴 시간은 차감한다.
/// 상시 1초 폴링 대신 저빈도 틱(기본 15초)만 사용 → 가볍다.
final class TrackingEngine: ObservableObject {
    static let shared = TrackingEngine()

    let storage = Storage()
    let categorizer = Categorizer()
    let goals = GoalStore()
    private let monitor = FrontmostMonitor()

    /// 오늘(혹은 현재 진행 중 날짜)의 라이브 기록. UI가 구독.
    @Published private(set) var today: DayRecord

    /// 유휴 임계값(초). 이 시간 이상 입력이 없으면 측정 일시정지.
    @Published var idleThresholdSeconds: Double {
        didSet { UserDefaults.standard.set(idleThresholdSeconds, forKey: idleKey) }
    }

    /// 현재 측정 중인지(디버그/표시용).
    @Published private(set) var isPaused = false

    private let idleKey = "idleThresholdSeconds"
    private let tickInterval: TimeInterval = 15

    // 세션 상태
    private var currentBundleId: String?
    private var currentDisplayName: String = ""
    private var sessionStart: Date?

    private var tickTimer: DispatchSourceTimer?
    private var notifiedGoalKeys = Set<String>()   // "goalId-yyyy-MM-dd" 중복 알림 방지
    private var dirty = false                       // today가 마지막 저장 이후 바뀌었는지(불필요한 디스크 쓰기 방지)

    private init() {
        let stored = UserDefaults.standard.double(forKey: idleKey)
        idleThresholdSeconds = stored > 0 ? stored : 120
        today = DayRecord(date: Storage.todayString())
        today = storage.load(date: today.date)
        start()
    }

    // MARK: - 시작/정지

    private func start() {
        monitor.onFrontmostChange = { [weak self] bid, name in
            self?.handleFrontmostChange(bundleId: bid, displayName: name)
        }
        monitor.onPause = { [weak self] in self?.pause() }
        monitor.onResume = { [weak self] in self?.resumeSession(at: Date()) }
        monitor.start()

        // 종료 시 진행 중 세션을 정산·저장(틱 사이에 종료해도 손실 최소화).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.credit(now: Date(), pausing: false)
            self?.saveIfDirty()
        }

        // 목표 달성 알림 권한 요청. provisional 포함 → 팝업 없이도 조용히 전달 가능.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional]) { _, _ in }

        // 시작 시점에 이미 달성된 오늘 목표는 알림한 것으로 표시 → 재시작 시 중복 알림 방지.
        for goal in goals.activeGoals(on: today.date) where goal.targetSeconds > 0 {
            if (today.apps[goal.bundleId]?.seconds ?? 0) >= goal.targetSeconds {
                notifiedGoalKeys.insert("\(goal.id.uuidString)-\(today.date)")
            }
        }

        // 시작 시 현재 최전면 앱으로 세션 개시(시스템 프로세스는 제외)
        if let cur = monitor.currentApp(),
           !SystemApps.isIgnored(bundleId: cur.0, displayName: cur.1) {
            currentBundleId = cur.0
            currentDisplayName = cur.1
            categorizer.register(bundleId: cur.0, displayName: cur.1)
            sessionStart = Date()
        } else {
            isPaused = true
        }

        // 팝오버(메뉴 트래킹)가 열려 있어도 멈추지 않도록 런루프 모드와 무관한
        // GCD 타이머 사용. NSTimer는 이벤트 트래킹 모드에서 멈출 수 있음.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + tickInterval, repeating: tickInterval, leeway: .seconds(3))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        tickTimer = timer
    }

    // MARK: - 이벤트 핸들러

    private func handleFrontmostChange(bundleId: String, displayName: String) {
        // 자기 자신(메뉴바 팝오버)은 추적하지 않음 → 이전 앱 세션 유지
        if bundleId == Bundle.main.bundleIdentifier { return }

        let now = Date()
        // 잠금/로그인/스크린세이버 등 시스템 프로세스 → 측정 중지(이 시간은 작업 아님)
        if SystemApps.isIgnored(bundleId: bundleId, displayName: displayName) {
            credit(now: now, pausing: true)
            currentBundleId = nil
            sessionStart = nil
            isPaused = true
            return
        }

        categorizer.register(bundleId: bundleId, displayName: displayName)
        credit(now: now, pausing: false)      // 이전 앱 시간 정산
        currentBundleId = bundleId
        currentDisplayName = displayName
        // 최전면 전환은 사용자 입력 행위이므로 측정 재개.
        sessionStart = now
        isPaused = false
    }

    private func pause() {
        credit(now: Date(), pausing: true)
        sessionStart = nil
        isPaused = true
    }

    private func resumeSession(at now: Date) {
        // 재개 시점의 최전면이 시스템 프로세스(잠금화면 등)면 계속 정지 상태 유지.
        guard let cur = monitor.currentApp(),
              !SystemApps.isIgnored(bundleId: cur.0, displayName: cur.1) else {
            currentBundleId = nil
            sessionStart = nil
            isPaused = true
            return
        }
        currentBundleId = cur.0
        currentDisplayName = cur.1
        categorizer.register(bundleId: cur.0, displayName: cur.1)
        sessionStart = now
        isPaused = false
    }

    // MARK: - 틱 (저빈도)

    private func tick() {
        let now = Date()
        rolloverIfNeeded(now: now)

        // 추적 중이던 앱이 종료됐으면 정산을 멈춘다(종료 앱 시간이 계속 쌓이는 것 방지).
        if !isPaused, currentBundleId != nil, !isCurrentAppRunning() {
            sessionStart = nil
            currentBundleId = nil
            isPaused = true
            saveIfDirty()
            return
        }

        let idle = IdleMonitor.idleSeconds()
        if isPaused {
            if idle < idleThresholdSeconds {
                resumeSession(at: now)
            }
        } else if idle >= idleThresholdSeconds {
            // 유휴 진입: 마지막 입력 시점까지만 인정하고 일시정지
            credit(now: now, pausing: true)
            sessionStart = nil
            isPaused = true
        } else {
            // 활성: 누적 시간을 롤링 정산(UI 라이브 + 크래시 대비)
            credit(now: now, pausing: false)
            sessionStart = now
        }

        saveIfDirty()
        checkGoalCompletions()
    }

    /// 목표를 처음 채우는 순간 시스템 알림(팝오버가 닫혀 있어도 알려줌).
    private func checkGoalCompletions() {
        let dayStr = today.date
        for goal in goals.activeGoals(on: dayStr) where goal.targetSeconds > 0 {
            let key = "\(goal.id.uuidString)-\(dayStr)"
            guard !notifiedGoalKeys.contains(key) else { continue }
            let secs = today.apps[goal.bundleId]?.seconds ?? 0
            if secs >= goal.targetSeconds {
                notifiedGoalKeys.insert(key)
                let content = UNMutableNotificationContent()
                content.title = "🎉 목표 달성!"
                content.body = "\(goal.displayName) \(formatDuration(goal.targetSeconds)) 달성!"
                content.sound = .default
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }

    // MARK: - 정산 로직

    /// 현재 세션의 경과시간을 today에 누적.
    /// pausing=true 이면 마지막 입력 시점까지만 인정(유휴 구간 제외).
    /// pausing=false(활성)이면 now까지 전부 인정 → 입력 중에는 1초씩 매끄럽게 증가.
    private func credit(now: Date, pausing: Bool) {
        guard let start = sessionStart, let bid = currentBundleId else { return }
        let credited = pausing
            ? SessionMath.pausedCredit(start: start, now: now, idle: IdleMonitor.idleSeconds())
            : SessionMath.activeCredit(start: start, now: now)
        guard credited > 0 else { return }
        today.add(bundleId: bid, displayName: currentDisplayName, seconds: credited)
        dirty = true
    }

    /// today가 바뀐 경우에만 디스크에 저장(유휴/정지 시 불필요한 쓰기 방지).
    private func saveIfDirty() {
        guard dirty else { return }
        storage.save(today)
        dirty = false
    }

    /// 자정을 넘겼으면 이전 날짜로 정산 후 새 날짜 기록으로 교체.
    private func rolloverIfNeeded(now: Date) {
        let cur = Storage.todayString()
        guard today.date != cur else { return }
        credit(now: now, pausing: false)
        storage.save(today)            // 이전 날짜는 롤오버 시 항상 저장
        today = storage.load(date: cur)
        dirty = false
        sessionStart = isPaused ? nil : now
        notifiedGoalKeys.removeAll()   // 새 날 → 목표 다시 달성 가능
    }

    // MARK: - 조회 헬퍼

    /// 선택한 날짜의 기록. 오늘이면 라이브 today, 과거면 디스크에서 로드.
    func record(for date: String) -> DayRecord {
        date == today.date ? today : storage.load(date: date)
    }

    /// 아직 today에 정산되지 않은, 진행 중인 세션의 경과시간(표시용).
    struct LiveDelta { let bundleId: String; let displayName: String; let seconds: Double }

    /// 팝오버가 1초마다 직접 판정하는 라이브 상태(틱에 의존하지 않음).
    /// delta: 더해서 표시할 진행분, isIdle: 유휴/정지 → ⏸️ 표시.
    struct LiveState { let delta: LiveDelta?; let isIdle: Bool }

    func liveState(now: Date = Date()) -> LiveState {
        // 잠금/슬립/유휴 등으로 명시적 정지 상태
        if isPaused { return LiveState(delta: nil, isIdle: true) }
        guard let start = sessionStart, let bid = currentBundleId else {
            return LiveState(delta: nil, isIdle: false)
        }
        // 추적하던 앱이 종료됨 → 표시도 즉시 멈춤(틱을 기다리지 않음)
        if !isCurrentAppRunning() {
            return LiveState(delta: nil, isIdle: false)
        }
        // 유휴 한계 이상이면 정지로 표시(⏸️), 더하지 않음
        if IdleMonitor.idleSeconds() >= idleThresholdSeconds {
            return LiveState(delta: nil, isIdle: true)
        }
        let credited = SessionMath.activeCredit(start: start, now: now)
        let delta = credited > 0 ? LiveDelta(bundleId: bid, displayName: currentDisplayName, seconds: credited) : nil
        return LiveState(delta: delta, isIdle: false)
    }

    /// 현재 추적 중인 앱이 아직 실행 중인지.
    private func isCurrentAppRunning() -> Bool {
        guard let bid = currentBundleId else { return false }
        // 번들 ID면 직접 조회(전체 앱 순회보다 훨씬 가벼움).
        if bid.contains(".") {
            return !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
        }
        // 번들 ID가 없는 프로세스(실행파일명 fallback)만 순회.
        return NSWorkspace.shared.runningApplications.contains {
            FrontmostMonitor.bundleId(for: $0) == bid
        }
    }
}
