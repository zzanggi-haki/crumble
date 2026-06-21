// Crumble 앱 아이콘 1024 마스터 렌더 (디자인 시스템 §5.1)
// 사용: swift scripts/render_crumble_icon.swift  → /tmp/Crumble-1024.png
import SwiftUI
import AppKit

// 쿠키 몸통 + 베어문(Path 빼기로 확실히 렌더)
struct CookieBody: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width
        let body = Path(ellipseIn: rect)
        // 우상단 베어문 (살짝 울퉁불퉁하게 두 입)
        let b1 = Path(ellipseIn: CGRect(x: rect.minX + s*0.58, y: rect.minY - s*0.06,
                                        width: s*0.5, height: s*0.5))
        let b2 = Path(ellipseIn: CGRect(x: rect.minX + s*0.48, y: rect.minY - s*0.18,
                                        width: s*0.34, height: s*0.34))
        return body.subtracting(b1).subtracting(b2)
    }
}

// 컬러 쿠키 (메뉴바 아이콘과 같은 모양: 베어문 + 칩)
struct Cookie: View {
    var size: CGFloat
    private let dough = Color(red: 0.80, green: 0.58, blue: 0.36)
    private let chocolate = Color(red: 0.34, green: 0.22, blue: 0.13)

    var body: some View {
        ZStack {
            CookieBody().fill(dough)
            chip(0.12, -0.20, -0.06)
            chip(0.11, 0.00, 0.16)
            chip(0.10, -0.22, 0.20)
            chip(0.10, 0.16, 0.24)
            chip(0.09, -0.04, -0.04)
        }
        .frame(width: size, height: size)
    }
    private func chip(_ d: CGFloat, _ x: CGFloat, _ y: CGFloat) -> some View {
        Circle().fill(chocolate).frame(width: size * d, height: size * d).offset(x: size * x, y: size * y)
    }
}

struct IconView: View {
    var body: some View {
        let canvas: CGFloat = 1024
        let inset: CGFloat = 88
        let side = canvas - inset * 2
        let radius = side * 0.2237
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 1.0, green: 0.95, blue: 0.84),
                             Color(red: 1.0, green: 0.82, blue: 0.55)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: side, height: side)
            Cookie(size: side * 0.6)
                .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 16)
        }
        .frame(width: canvas, height: canvas)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let img = renderer.nsImage,
          let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: "/tmp/Crumble-1024.png"))
    print("wrote /tmp/Crumble-1024.png")
}
