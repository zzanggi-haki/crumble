import SwiftUI

/// 목표 달성 순간 꽃가루가 파파박 터지는 일회성 연출. `burst` 값이 바뀌면 발사.
/// 입자별로 랜덤 출발점·속도·중력·딜레이를 미리 뽑아두고, progress(0→1) 애니메이션 하나로
/// 위치를 계산 → 가볍게 불규칙한 폭발 느낌.
struct ConfettiView: View {
    @State private var items: [Item] = []

    private let colors: [Color] = [.brandOrange, .brandGold, .green, .pink, .blue, .purple, .red, .cyan]

    struct Item: Identifiable {
        let id = UUID()
        let originX: CGFloat   // 0~1
        let originY: CGFloat   // 0~1
        let vx: CGFloat        // 가로 속도(±)
        let vy: CGFloat        // 세로 초기 속도(±, 음수면 위로)
        let gravity: CGFloat   // 아래로 당기는 힘
        let color: Color
        let delay: Double
        let spin: Double
        let size: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(items) { item in
                    ConfettiPiece(item: item, size: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onAppear { spawn() }
    }

    private func spawn() {
        // 최상단에 고정해서 동시에 발사, 방향(가로 흩뿌림)만 랜덤 → 위에서 쏟아지는 폭죽.
        items = (0..<130).map { _ in
            Item(
                originX: .random(in: 0.1...0.9),
                originY: 0,                                  // 최상단 고정
                vx: .random(in: -320...320),                // 좌우 랜덤 흩뿌림
                vy: .random(in: 80...360),                  // 아래로 쏘기
                gravity: .random(in: 500...900),
                color: colors.randomElement()!,
                delay: 0,
                spin: .random(in: 180...900),
                size: .random(in: 6...11)
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { items = [] }
    }
}

private struct ConfettiPiece: View {
    let item: ConfettiView.Item
    let size: CGSize
    @State private var progress: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(item.color)
            .frame(width: item.size, height: item.size * 1.5)
            .rotationEffect(.degrees(item.spin * Double(progress)))
            .position(
                x: item.originX * size.width + item.vx * progress,
                y: item.originY * size.height + item.vy * progress + item.gravity * progress * progress
            )
            .opacity(progress < 0.75 ? 1 : max(0, (1 - progress) / 0.25))
            .onAppear {
                withAnimation(.easeOut(duration: 1.5).delay(item.delay)) { progress = 1 }
            }
    }
}
