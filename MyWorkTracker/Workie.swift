import SwiftUI
import AppKit

/// 메뉴바용 단색 실루엣 아이콘 — 쿠키 + 베어문 자국 + 칩 구멍. 템플릿 이미지로 렌더해
/// 라이트/다크 메뉴바에 자동 적응(흑백).
struct CrumbleBarIcon: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            punch(0.40, 0.33, -0.31)   // 베어문(우상단)
            punch(0.26, 0.14, -0.42)
            punch(0.18, -0.20, -0.06)  // 칩 구멍
            punch(0.17, 0.06, 0.22)
            punch(0.16, -0.14, 0.18)
        }
        .compositingGroup()
        .frame(width: size, height: size)
    }

    private func punch(_ d: CGFloat, _ x: CGFloat, _ y: CGFloat) -> some View {
        Circle().fill(Color.black)
            .frame(width: size * d, height: size * d)
            .offset(x: size * x, y: size * y)
            .blendMode(.destinationOut)
    }
}

/// 메뉴바 라벨용 템플릿 NSImage(한 번 렌더해 재사용).
enum CrumbleBarImage {
    @MainActor static let template: NSImage = {
        let s: CGFloat = 15   // 옆 메뉴바 아이콘들과 비율 맞춤
        let renderer = ImageRenderer(content: CrumbleBarIcon(size: s))
        renderer.scale = 3
        let img = renderer.nsImage ?? NSImage(size: NSSize(width: s, height: s))
        img.size = NSSize(width: s, height: s)
        img.isTemplate = true   // 메뉴바 흑백 자동 적응
        return img
    }()
}

/// 앱 마스코트 "Workie" — 한 입 베어 문 크럼블(쿠키)의 플랫 아이콘.
/// 그라데이션 없이 단색 + 또렷한 초코칩 + 울퉁불퉁한 베어 문 자국(달처럼 안 보이게).
struct WorkieView: View {
    var size: CGFloat = 72

    private let dough = Color(red: 0.80, green: 0.62, blue: 0.42)   // 플랫 쿠키 톤
    private let chip = Color(red: 0.36, green: 0.24, blue: 0.15)    // 초콜릿

    var body: some View {
        ZStack {
            Circle()
                .fill(dough)
                .mask(biteMask)

            // 초코칩 — 곳곳에 또렷하게 (쿠키 시그널)
            chipDot(0.13, x: -0.22, y: -0.10)
            chipDot(0.12, x: -0.02, y: 0.20)
            chipDot(0.11, x: 0.20, y: 0.18)
            chipDot(0.10, x: -0.22, y: 0.20)
            chipDot(0.09, x: 0.02, y: -0.06)
        }
        .frame(width: size, height: size)
    }

    private func chipDot(_ d: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle().fill(chip)
            .frame(width: size * d, height: size * d)
            .offset(x: size * x, y: size * y)
    }

    /// 우상단을 여러 작은 원으로 뚫어 "울퉁불퉁 베어 문" 자국을 만든다(매끈한 초승달 방지).
    private var biteMask: some View {
        Circle()
            .fill(.black)
            .overlay(
                ZStack {
                    bitePunch(0.30, x: 0.34, y: -0.30)
                    bitePunch(0.22, x: 0.16, y: -0.40)
                    bitePunch(0.22, x: 0.44, y: -0.16)
                }
                .compositingGroup()
                .blendMode(.destinationOut)
            )
            .compositingGroup()
    }

    private func bitePunch(_ d: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(.black)
            .frame(width: size * d, height: size * d)
            .offset(x: size * x, y: size * y)
    }
}
