import AppKit
import Foundation

/// 최전면 앱(frontmost application) 전환과 슬립/잠금 상태를 감지해 콜백으로 알린다.
/// 권한 불필요: NSWorkspace 노티피케이션과 frontmostApplication만 사용.
final class FrontmostMonitor {
    /// 최전면 앱이 바뀜 (bundleId, displayName).
    var onFrontmostChange: ((String, String) -> Void)?
    /// 측정 중지 사유 발생 (슬립/화면잠금/스크린세이버 시작).
    var onPause: (() -> Void)?
    /// 측정 재개 (깨어남/잠금해제/스크린세이버 종료).
    var onResume: (() -> Void)?

    private let workspace = NSWorkspace.shared
    private let distributed = DistributedNotificationCenter.default()

    func start() {
        let wsCenter = workspace.notificationCenter

        wsCenter.addObserver(self, selector: #selector(activeAppChanged(_:)),
                             name: NSWorkspace.didActivateApplicationNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(pauseEvent(_:)),
                             name: NSWorkspace.willSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(pauseEvent(_:)),
                             name: NSWorkspace.screensDidSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(resumeEvent(_:)),
                             name: NSWorkspace.didWakeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(resumeEvent(_:)),
                             name: NSWorkspace.screensDidWakeNotification, object: nil)

        // 화면 잠금/잠금해제 (공개 NSWorkspace 노티에 없어 분산 노티 사용)
        distributed.addObserver(self, selector: #selector(pauseEvent(_:)),
                                name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(resumeEvent(_:)),
                                name: .init("com.apple.screenIsUnlocked"), object: nil)

        // 시작 시 현재 최전면 앱으로 초기화
        if let app = workspace.frontmostApplication {
            emitChange(for: app)
        }
    }

    func stop() {
        workspace.notificationCenter.removeObserver(self)
        distributed.removeObserver(self)
    }

    /// 현재 최전면 앱 정보 (bundleId, displayName). 없으면 nil.
    func currentApp() -> (String, String)? {
        guard let app = workspace.frontmostApplication else { return nil }
        return (Self.bundleId(for: app), Self.displayName(for: app))
    }

    @objc private func activeAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            ?? workspace.frontmostApplication else { return }
        emitChange(for: app)
    }

    @objc private func pauseEvent(_ note: Notification) { onPause?() }
    @objc private func resumeEvent(_ note: Notification) { onResume?() }

    private func emitChange(for app: NSRunningApplication) {
        onFrontmostChange?(Self.bundleId(for: app), Self.displayName(for: app))
    }

    static func bundleId(for app: NSRunningApplication) -> String {
        if let id = app.bundleIdentifier, !id.isEmpty { return id }
        // 번들 ID가 없는 프로세스는 실행 파일명으로 식별
        return app.executableURL?.lastPathComponent ?? "unknown.\(app.processIdentifier)"
    }

    static func displayName(for app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? "알 수 없는 앱"
    }
}
