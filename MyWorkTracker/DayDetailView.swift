import SwiftUI

/// 특정 과거 날짜의 기록을 보여주는 상세 화면(별도 창). 라이브 없음(정적).
struct DayDetailView: View {
    @EnvironmentObject var engine: TrackingEngine
    @EnvironmentObject var categorizer: Categorizer
    let dateStr: String

    private var rec: DayRecord {
        var r = engine.record(for: dateStr)
        r.apps = r.apps.filter {
            !SystemApps.isIgnored(bundleId: $0.value.bundleId, displayName: $0.value.displayName)
        }
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(koreanDate).font(.headline)
                HStack {
                    Text("총 작업 시간").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDuration(rec.totalSeconds))
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
            }
            .padding(16)
            Divider()

            if rec.apps.values.contains(where: { $0.seconds >= 1 }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        let groups = categoryGroups(for: rec, categorizer: categorizer)
                        ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                            CategorySectionView(group: group)
                            if idx < groups.count - 1 { Divider() }
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    WorkieView(size: 72)
                    Text("이 날은 부스러기가 없네요")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 380, height: 560)
    }

    private var koreanDate: String {
        guard let d = Storage.dateFormatter.date(from: dateStr) else { return dateStr }
        return koreanDateFormatter.string(from: d)
    }
}
