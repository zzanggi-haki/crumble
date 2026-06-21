import AppKit
import SwiftUI

/// 통계 창을 직접 NSWindow로 띄운다(메뉴바 팝오버에 가리지 않도록 팝오버를 닫고 앞으로).
@MainActor
final class StatsWindowController {
    static let shared = StatsWindowController()
    private var window: NSWindow?

    func show(engine: TrackingEngine) {
        if window == nil {
            let root = StatsView()
                .environmentObject(engine)
                .environmentObject(engine.categorizer)
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Crumble 통계"
            win.styleMask = [.titled, .closable, .resizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        for w in NSApp.windows where w !== window && w.isVisible {
            let cls = String(describing: type(of: w))
            if cls.contains("MenuBarExtra") || cls.contains("StatusBar") || cls.contains("Popover") {
                w.orderOut(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
