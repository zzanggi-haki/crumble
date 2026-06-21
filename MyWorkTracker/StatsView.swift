import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct StatsView: View {
    @EnvironmentObject var engine: TrackingEngine
    @EnvironmentObject var categorizer: Categorizer

    @State private var period: StatsPeriod = .week
    @State private var offset = 0                  // 0 = 이번 주/달, -1 = 지난 주/달
    @State private var stats: PeriodStats?

    private var aggregator: StatsAggregator { StatsAggregator(storage: engine.storage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            if let stats {
                summary(stats)
                chart(stats)
                Divider()
                breakdown(stats)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 620)
        .onAppear(perform: reload)
        .onChange(of: period) { _, _ in offset = 0; reload() }
    }

    // MARK: - 상단 컨트롤

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button { offset -= 1; reload() } label: { Image(systemName: "chevron.left").font(.title3) }
                    .buttonStyle(.borderless)
                Spacer()
                Text(stats?.title ?? "")
                    .font(.headline)
                Spacer()
                Button { if offset < 0 { offset += 1; reload() } } label: { Image(systemName: "chevron.right").font(.title3) }
                    .buttonStyle(.borderless)
                    .disabled(offset >= 0)
            }
        }
    }

    // MARK: - 요약

    private func summary(_ s: PeriodStats) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(period == .week ? "이 주 총 작업 시간" : "이 달 총 작업 시간")
                    .font(.caption).foregroundStyle(.secondary)
                Text(formatDuration(s.total)).font(.title2.weight(.bold).monospacedDigit())
            }
            Spacer()
            Button {
                exportCSV(s)
            } label: { Label("CSV 내보내기", systemImage: "square.and.arrow.up") }
                .disabled(s.total == 0)
        }
    }

    // MARK: - 차트

    private func chart(_ s: PeriodStats) -> some View {
        // 주간: 매일 라벨(요일), 월간: 5일 간격 라벨(일)로 솎아 겹침 방지 → 월 전체 한눈에.
        let ko = Locale(identifier: "ko_KR")
        let labelFormat = period == .week
            ? Date.FormatStyle().locale(ko).weekday(.abbreviated)
            : Date.FormatStyle().locale(ko).day()
        return Chart(s.days) { day in
            BarMark(
                x: .value("날짜", day.dateValue, unit: .day),
                y: .value("시간(분)", day.seconds / 60)
            )
            .foregroundStyle(Color.brandOrange.gradient)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: labelFormat)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let m = value.as(Double.self) { Text(minutesLabel(m)) }
                }
            }
        }
        .frame(height: 200)
    }

    private func minutesLabel(_ minutes: Double) -> String {
        minutes >= 60 ? String(format: "%.0f시간", minutes / 60) : "\(Int(minutes))분"
    }

    // MARK: - 카테고리/앱 분해

    private func breakdown(_ s: PeriodStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(categoryGroups(s)) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("[\(group.name)]").font(.headline)
                            Spacer()
                            Text(formatDuration(group.seconds))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ForEach(group.apps) { app in
                            HStack(spacing: 10) {
                                AppIconView(bundleId: app.bundleId, size: 20)
                                Text(app.displayName).lineLimit(1)
                                Spacer()
                                Text(formatDuration(app.seconds))
                                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func categoryGroups(_ s: PeriodStats) -> [CategoryGroup] {
        var dict: [String: [AppUsage]] = [:]
        for app in s.apps where app.seconds >= 1 {
            let cat = categorizer.category(bundleId: app.bundleId, displayName: app.displayName)
            dict[cat, default: []].append(app)
        }
        return dict.map { name, apps in
            CategoryGroup(name: name,
                          apps: apps.sorted { $0.seconds > $1.seconds },
                          seconds: apps.reduce(0) { $0 + $1.seconds })
        }
        .sorted { $0.seconds > $1.seconds }   // 작업시간 많은 카테고리 순
    }

    // MARK: - 로직

    private func reload() {
        stats = aggregator.stats(period: period, offset: offset, now: Date())
    }

    /// 하루·앱별 tidy CSV. 한 행 = (날짜, 앱). 미래는 제외(오늘까지만).
    private func exportCSV(_ s: PeriodStats) {
        let cal = Calendar.current
        let isoCal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: Date())
        let end = min(s.endDate, today)                 // 진행 중 기간은 오늘까지만

        struct Row { let date: String; let ym: String; let week: String
                     let category: String; let app: String; let bundleId: String; let seconds: Int }
        var rows: [Row] = []

        var day = s.startDate
        while day <= end {
            let ymd = Storage.string(from: day)         // yyyy-MM-dd
            let ym = String(ymd.prefix(7))              // yyyy-MM
            let week = String(format: "%04d-W%02d",
                              isoCal.component(.yearForWeekOfYear, from: day),
                              isoCal.component(.weekOfYear, from: day))
            for u in engine.storage.load(date: ymd).apps.values
                where !SystemApps.isIgnored(bundleId: u.bundleId, displayName: u.displayName) && u.seconds >= 1 {
                let cat = categorizer.category(bundleId: u.bundleId, displayName: u.displayName)
                rows.append(Row(date: ymd, ym: ym, week: week, category: cat,
                                app: u.displayName, bundleId: u.bundleId, seconds: Int(u.seconds)))
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        // 날짜 오름차순, 같은 날은 시간 많은 순
        rows.sort { $0.date != $1.date ? $0.date < $1.date : $0.seconds > $1.seconds }

        func esc(_ v: String) -> String { "\"\(v.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        var csv = "date,year_month,iso_week,category,app,bundle_id,seconds,minutes\n"
        for r in rows {
            let minutes = String(format: "%.1f", Double(r.seconds) / 60)
            csv += "\(r.date),\(r.ym),\(r.week),\(esc(r.category)),\(esc(r.app)),\(esc(r.bundleId)),\(r.seconds),\(minutes)\n"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let kind = period == .week ? "weekly" : "monthly"
        panel.nameFieldStringValue = "Crumble_\(kind)_\(Storage.string(from: s.startDate))_\(Storage.string(from: end)).csv"
        if panel.runModal() == .OK, let url = panel.url {
            // 엑셀에서 한글 앱 이름이 깨지지 않도록 UTF-8 BOM 추가
            let data = "\u{FEFF}".data(using: .utf8)! + (csv.data(using: .utf8) ?? Data())
            try? data.write(to: url)
        }
    }
}
