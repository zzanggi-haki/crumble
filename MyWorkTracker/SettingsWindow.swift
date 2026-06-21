import AppKit
import SwiftUI

/// 메뉴바 전용(LSUIElement) 앱에서 SwiftUI `Settings` 씬이 안정적으로 열리지 않아,
/// 설정 창을 직접 NSWindow로 띄운다.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(engine: TrackingEngine) {
        if window == nil {
            let root = SettingsView()
                .environmentObject(engine)
                .environmentObject(engine.storage)
                .environmentObject(engine.categorizer)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Crumble 설정"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        guard let win = window else { return }
        closeMenuBarPopover()                  // 같은 앱의 메뉴바 팝오버를 닫아 가림 방지
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }

    /// 메뉴바 팝오버(높은 윈도우 레벨)가 설정 창을 가리므로 닫는다.
    private func closeMenuBarPopover() {
        for w in NSApp.windows where w !== window && w.isVisible {
            let cls = String(describing: type(of: w))
            if cls.contains("MenuBarExtra") || cls.contains("StatusBar") || cls.contains("Popover") {
                w.orderOut(nil)
            }
        }
    }
}
