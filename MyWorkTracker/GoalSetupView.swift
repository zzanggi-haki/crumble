import SwiftUI

/// 오늘 목표를 세우는 화면(팝오버 내부 인라인).
struct GoalSetupView: View {
    @EnvironmentObject var categorizer: Categorizer
    @EnvironmentObject var goals: GoalStore
    var onDone: () -> Void

    @State private var selectedBundleId: String?
    @State private var hours = 1
    @State private var minutes = 0
    @State private var repeatsDaily = false

    private var apps: [KnownApp] {
        categorizer.knownApps.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
    private var targetSeconds: Double { Double(hours * 3600 + minutes * 60) }
    private var canStart: Bool { selectedBundleId != nil && targetSeconds > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 헤더
            HStack {
                Text("오늘 목표 세우기").font(.headline)
                Spacer()
                Button { onDone() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("닫기")
            }
            Text(koreanToday()).font(.caption).foregroundStyle(.secondary)

            Divider()

            // 앱 선택
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("앱 선택")
                appPicker
            }

            // 목표 시간
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("목표 시간")
                HStack(spacing: 16) {
                    Stepper("\(hours)시간", value: $hours, in: 0...23)
                    Stepper("\(minutes)분", value: $minutes, in: 0...59, step: 1)
                }
                HStack(spacing: 8) {
                    presetChip("30분", 0, 30)
                    presetChip("1시간", 1, 0)
                    presetChip("2시간", 2, 0)
                    presetChip("4시간", 4, 0)
                }
            }

            Toggle("매일 반복", isOn: $repeatsDaily)

            Spacer(minLength: 0)

            Button(action: start) {
                Text("목표 시작하기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandOrange)
            .controlSize(.large)
            .disabled(!canStart)
        }
        .padding(16)
        .frame(width: 380, height: 560)
    }

    private var appPicker: some View {
        Menu {
            ForEach(apps) { app in
                Button { selectedBundleId = app.bundleId } label: { Text(app.displayName) }
            }
        } label: {
            HStack {
                if let bid = selectedBundleId, let app = categorizer.knownApps[bid] {
                    AppIconView(bundleId: bid, size: 24)
                    Text(app.displayName).font(.body)
                } else {
                    Text("앱을 선택하세요").font(.body).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
        .menuStyle(.borderlessButton)
    }

    private func presetChip(_ label: String, _ h: Int, _ m: Int) -> some View {
        Button(label) { hours = h; minutes = m }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func start() {
        guard let bid = selectedBundleId, let app = categorizer.knownApps[bid] else { return }
        // 진행률은 항상 자정 기준(그날 그 앱 전체) → 기준선 불필요.
        goals.add(Goal(bundleId: bid,
                       displayName: app.displayName,
                       targetSeconds: targetSeconds,
                       repeatsDaily: repeatsDaily,
                       startDay: Storage.todayString()))
        onDone()
    }

    private func koreanToday() -> String {
        koreanDateFormatter.string(from: Date())
    }
}
