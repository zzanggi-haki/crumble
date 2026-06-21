import SwiftUI

/// 목표 달성 시 무작위로 재생되는 축하 효과 종류.
enum CelebrationKind: CaseIterable {
    case confetti      // 위에서 쏟아지는 색종이
    case thumbsUp      // 아래에서 떠오르는 👍
    case sparkle       // 곳곳에서 반짝이는 ✨
    case trophyPunch   // 중앙에 트로피가 팡
    case scorePopup    // "달성! 🎉" 점수 팝업
}

/// 종류에 맞는 효과를 렌더. 호출부에서 `.id(trigger)`로 감싸 매 달성마다 새로 재생.
struct CelebrationView: View {
    let kind: CelebrationKind

    var body: some View {
        switch kind {
        case .confetti:    ConfettiView()
        case .thumbsUp:    EmojiRiseView(emoji: "👍")
        case .sparkle:     SparkleView()
        case .trophyPunch: TrophyPunchView()
        case .scorePopup:  ScorePopupView()
        }
    }
}

/// 이모지가 화면 아래에서 위로 둥실 떠오르는 효과(라이브 반응 느낌).
struct EmojiRiseView: View {
    let emoji: String
    @State private var items: [Item] = []

    struct Item: Identifiable {
        let id = UUID()
        let x: CGFloat        // 0~1
        let drift: CGFloat    // 좌우 흔들림
        let size: CGFloat
        let rotation: Double
        let delay: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(items) { item in
                    EmojiPiece(item: item, size: geo.size, emoji: emoji)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onAppear { spawn() }
    }

    private func spawn() {
        items = (0..<12).map { _ in
            Item(x: .random(in: 0.1...0.9),
                 drift: .random(in: -45...45),
                 size: .random(in: 28...48),
                 rotation: .random(in: -25...25),
                 delay: .random(in: 0...0.5))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { items = [] }
    }
}

private struct EmojiPiece: View {
    let item: EmojiRiseView.Item
    let size: CGSize
    let emoji: String
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(emoji)
            .font(.system(size: item.size))
            .rotationEffect(.degrees(item.rotation * Double(progress)))
            .position(
                x: item.x * size.width + item.drift * progress,
                y: (size.height + 40) - progress * (size.height + 100)   // 아래 → 위
            )
            .opacity(progress < 0.7 ? 1 : max(0, (1 - progress) / 0.3))
            .onAppear {
                withAnimation(.easeOut(duration: 2.0).delay(item.delay)) { progress = 1 }
            }
    }
}

// MARK: - ✨ 반짝이 폭발

struct SparkleView: View {
    @State private var items: [Item] = []
    @State private var textShown = false
    @State private var textGone = false

    struct Item: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let rotation: Double
        let delay: Double
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(items) { item in
                    SparklePiece(item: item, size: geo.size)
                }
                Text("목표 달성")
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(Color.brandGold)
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    .scaleEffect(textShown ? 1 : 0.4)
                    .opacity(textGone ? 0 : (textShown ? 1 : 0))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .onAppear {
            spawn()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { textShown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.5)) { textGone = true }
            }
        }
    }

    private func spawn() {
        // 글자 주변까지 빽빽하게 깔리도록 개수를 늘리고 전 영역에 분포.
        items = (0..<48).map { _ in
            Item(x: .random(in: 0.04...0.96),
                 y: .random(in: 0.06...0.94),
                 size: .random(in: 12...30),
                 rotation: .random(in: -30...30),
                 delay: .random(in: 0...0.8))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { items = [] }
    }
}

private struct SparklePiece: View {
    let item: SparkleView.Item
    let size: CGSize
    @State private var shown = false
    @State private var gone = false

    var body: some View {
        // 2단계: 팡 떴다(shown) → 사라짐(gone). 양 끝값이 달라야 보간이 보임.
        Text("✨")
            .font(.system(size: item.size))
            .scaleEffect(gone ? 0.1 : (shown ? 1.25 : 0.1))
            .opacity(gone ? 0 : (shown ? 1 : 0))
            .rotationEffect(.degrees(shown ? item.rotation : 0))
            .position(x: item.x * size.width, y: item.y * size.height)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35).delay(item.delay)) { shown = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + item.delay + 0.45) {
                    withAnimation(.easeIn(duration: 0.5)) { gone = true }
                }
            }
    }
}

// MARK: - 🏆 트로피 펀치

struct TrophyPunchView: View {
    @State private var popIn = false
    @State private var ring = false
    @State private var fadeOut = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .stroke(Color.brandGold, lineWidth: 5)
                    .frame(width: 110, height: 110)
                    .scaleEffect(ring ? 2.6 : 0.3)
                    .opacity(ring ? 0 : 0.9)
                VStack(spacing: 6) {
                    Image(systemName: "trophy.fill").font(.system(size: 58))
                    Text("달성!").font(.title.weight(.heavy))
                }
                .foregroundStyle(Color.brandGold)
                .scaleEffect(popIn ? 1 : 0.1)
                .opacity(fadeOut ? 0 : (popIn ? 1 : 0))
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { popIn = true }
            withAnimation(.easeOut(duration: 0.7)) { ring = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation(.easeOut(duration: 0.45)) { fadeOut = true }
            }
        }
    }
}

// MARK: - 💯 점수 팝업 + 팡파레 불꽃놀이

struct ScorePopupView: View {
    @State private var appear = false
    @State private var float = false
    @State private var particles: [Particle] = []

    struct Particle: Identifiable {
        let id = UUID()
        let emoji: String
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                // 중앙에서 사방으로 터지는 팡파레 이모지(불꽃놀이)
                ForEach(particles) { p in
                    ScoreParticle(particle: p, center: center)
                }
                // 골드 텍스트가 떠오름
                Text("달성! 🎉")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundStyle(Color.brandGold)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .scaleEffect(appear ? 1 : 0.4)
                    .opacity(float ? 0 : (appear ? 1 : 0))
                    .offset(y: float ? -80 : 0)
                    .position(center)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            let emojis = ["🎉", "🎊", "✨", "🎈", "⭐️"]
            particles = (0..<18).map { i in
                Particle(emoji: emojis.randomElement()!,
                         angle: Double(i) / 18 * 2 * .pi + .random(in: -0.18...0.18),
                         distance: .random(in: 90...180),
                         size: .random(in: 18...34))
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { appear = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 1.0)) { float = true }
            }
        }
    }
}

private struct ScoreParticle: View {
    let particle: ScorePopupView.Particle
    let center: CGPoint
    @State private var progress: CGFloat = 0

    var body: some View {
        Text(particle.emoji)
            .font(.system(size: particle.size))
            .position(
                x: center.x + CGFloat(cos(particle.angle)) * particle.distance * progress,
                y: center.y + CGFloat(sin(particle.angle)) * particle.distance * progress + 50 * progress * progress
            )
            .scaleEffect(0.3 + progress * 0.9)
            .opacity(progress < 0.6 ? 1 : max(0, (1 - progress) / 0.4))
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) { progress = 1 }
            }
    }
}
