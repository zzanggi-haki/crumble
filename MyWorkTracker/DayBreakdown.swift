import SwiftUI

/// 섹션 라벨 — caption · semibold · UPPERCASE · secondary (디자인 시스템 §3).
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption).fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// 하루 기록을 카테고리별(시간 많은 순)로 그룹핑. 시스템 프로세스는 제외 가정(호출부에서 필터).
func categoryGroups(for rec: DayRecord, categorizer: Categorizer) -> [CategoryGroup] {
    var dict: [String: [AppUsage]] = [:]
    for usage in rec.apps.values where usage.seconds >= 1 {
        let cat = categorizer.category(bundleId: usage.bundleId, displayName: usage.displayName)
        dict[cat, default: []].append(usage)
    }
    return dict.map { name, apps in
        CategoryGroup(name: name,
                      apps: apps.sorted { $0.seconds > $1.seconds },
                      seconds: apps.reduce(0) { $0 + $1.seconds })
    }
    .sorted { $0.seconds > $1.seconds }   // 작업시간 많은 카테고리 순
}

/// 카테고리 한 섹션(제목 + 합계 + 앱별 시간). 팝오버/상세창 공용.
/// activeBundleId: 지금 시간이 흐르는(활성) 앱 — 아이콘에 주황 스피너 표시.
struct CategorySectionView: View {
    let group: CategoryGroup
    var activeBundleId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 섹션 라벨: caption · semibold · uppercase · secondary (디자인 시스템 §3)
            HStack {
                Text(group.name)
                    .font(.caption).fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(group.seconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // 앱 행: 아이콘24 + 이름(.body) + 시간. 행 사이 구분선.
            ForEach(Array(group.apps.enumerated()), id: \.element.id) { idx, app in
                HStack(spacing: 10) {
                    AppIconView(bundleId: app.bundleId, size: 24)
                    Text(app.displayName).font(.body).lineLimit(1)
                    if app.bundleId == activeBundleId {
                        ActivePulseDot()   // 지금 돌아가는 중
                    }
                    Spacer()
                    Text(formatDuration(app.seconds))
                        .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                if idx < group.apps.count - 1 { Divider() }
            }
        }
    }
}

/// 활성 앱 이름 뒤의 작은 주황 원 — 작아졌다 돌아오며 맥박치는 "지금 돌아가는 중" 표시.
struct ActivePulseDot: View {
    @State private var small = false

    var body: some View {
        Circle()
            .fill(Color.brandOrange)
            .frame(width: 9, height: 9)
            .scaleEffect(small ? 0.5 : 1.0)
            .opacity(small ? 0.55 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { small = true }
            }
    }
}
