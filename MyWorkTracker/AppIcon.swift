import AppKit
import SwiftUI

/// bundleId로 앱 아이콘을 가져와 캐싱한다. 못 찾으면 일반 앱 아이콘으로 대체.
enum AppIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleId: String) -> NSImage {
        if let cached = cache[bundleId] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        cache[bundleId] = image
        return image
    }
}

/// 앱 아이콘 표시용 작은 뷰.
struct AppIconView: View {
    let bundleId: String
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: AppIconProvider.icon(for: bundleId))
            .resizable()
            .frame(width: size, height: size)
    }
}
