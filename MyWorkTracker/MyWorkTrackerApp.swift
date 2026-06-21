import SwiftUI

@main
struct MyWorkTrackerApp: App {
    @StateObject private var engine = TrackingEngine.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(engine)
                .environmentObject(engine.categorizer)
                .environmentObject(engine.storage)
                .environmentObject(engine.goals)
        } label: {
            // 메뉴바 아이콘: 크럼블 쿠키 실루엣(템플릿)
            Image(nsImage: CrumbleBarImage.template)
        }
        .menuBarExtraStyle(.window)
    }
}
