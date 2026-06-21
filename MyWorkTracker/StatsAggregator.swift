import Foundation

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "주간"
    case month = "월간"
    var id: String { rawValue }
}

/// 기간 내 하루 총합.
struct DayTotal: Identifiable {
    let date: String        // "yyyy-MM-dd"
    let dateValue: Date     // 차트 x축용 실제 날짜
    let seconds: Double
    var id: String { date }
}

/// 기간 집계 결과.
struct PeriodStats {
    let title: String           // "2026년 6월" / "6월 15일 ~ 6월 21일"
    let startDate: Date
    let endDate: Date
    let days: [DayTotal]        // 오래된→최신
    let apps: [AppUsage]        // 합산 후 내림차순
    var total: Double { apps.reduce(0) { $0 + $1.seconds } }
}

/// 여러 날짜의 기록을 기간(주/월) 단위로 합산. 시스템 프로세스는 제외.
struct StatsAggregator {
    let storage: Storage

    func stats(period: StatsPeriod, offset: Int, now: Date) -> PeriodStats {
        let cal = Calendar.current
        let (start, end, title) = range(period: period, offset: offset, now: now, cal: cal)

        var days: [DayTotal] = []
        var appAgg: [String: AppUsage] = [:]

        var day = start
        while day <= end {
            let ymd = Storage.string(from: day)
            let rec = storage.load(date: ymd)
            var dayTotal = 0.0
            for u in rec.apps.values where !SystemApps.isIgnored(bundleId: u.bundleId, displayName: u.displayName) {
                dayTotal += u.seconds
                if var e = appAgg[u.bundleId] {
                    e.seconds += u.seconds
                    e.displayName = u.displayName
                    appAgg[u.bundleId] = e
                } else {
                    appAgg[u.bundleId] = u
                }
            }
            days.append(DayTotal(date: ymd, dateValue: day, seconds: dayTotal))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        let apps = appAgg.values.sorted { $0.seconds > $1.seconds }
        return PeriodStats(title: title, startDate: start, endDate: end, days: days, apps: apps)
    }

    // MARK: - 기간 계산

    private func range(period: StatsPeriod, offset: Int, now: Date, cal: Calendar) -> (Date, Date, String) {
        switch period {
        case .week:
            let base = cal.date(byAdding: .weekOfYear, value: offset, to: now)!
            let interval = cal.dateInterval(of: .weekOfYear, for: base)!
            let start = cal.startOfDay(for: interval.start)
            let end = cal.date(byAdding: .day, value: 6, to: start)!
            return (start, end, "\(shortKorean(start)) ~ \(shortKorean(end))")
        case .month:
            let base = cal.date(byAdding: .month, value: offset, to: now)!
            let interval = cal.dateInterval(of: .month, for: base)!
            let start = cal.startOfDay(for: interval.start)
            let end = cal.date(byAdding: .day, value: -1, to: interval.end)!
            return (start, end, monthKorean(start))
        }
    }

    private func shortKorean(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M월 d일"
        return f.string(from: date)
    }

    private func monthKorean(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "yyyy년 M월"
        return f.string(from: date)
    }
}
