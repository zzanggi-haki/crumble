import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TrackingEngine
    @EnvironmentObject var categorizer: Categorizer
    @EnvironmentObject var goals: GoalStore
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var showCalendar = false
    @State private var detailDate: String?   // 달력 팝오버 안에서 보고 있는 상세 날짜(nil이면 목록)
    // 날짜 목록은 팝오버를 열 때 한 번만 읽어 캐싱(매 렌더 파일 IO 방지).
    @State private var dateRows: [DateRow] = []
    // 날짜 선택기에서 현재 보고 있는 월("yyyy-MM").
    @State private var pickerMonth: String = ""
    // 목표 세우기 화면 표시 여부.
    @State private var showGoalSetup = false
    // 목표 달성 연출 상태
    @State private var celebrationTrigger = 0
    @State private var celebrationKind: CelebrationKind = .confetti
    @State private var isCelebrating = false         // 효과는 축하 중일 때만 렌더(재진입 재생 방지)
    @State private var streaks: [UUID: Int] = [:]   // 반복 목표 연속 달성일
    @State private var listHeight: CGFloat = 0       // 카테고리 목록 실제 높이(여백 제거용)

    var body: some View {
        if showGoalSetup {
            GoalSetupView(onDone: { showGoalSetup = false })
        } else {
            mainView
        }
    }

    @ViewBuilder
    private var mainView: some View {
        // 팝오버가 열려 있을 때만 1초 주기로 라이브 갱신.
        // 닫혀 있으면(controlActiveState == .inactive) TimelineView를 만들지 않아 매초 렌더가 멈춤 → idle 부하 0.
        if controlActiveState == .inactive {
            popoverBody(now: Date(), live: TrackingEngine.LiveState(delta: nil, isIdle: false))
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                popoverBody(now: context.date, live: engine.liveState(now: context.date))
            }
        }
    }

    @ViewBuilder
    private func popoverBody(now: Date, live: TrackingEngine.LiveState) -> some View {
        let dateStr = Storage.string(from: now)
        let rec = displayRecord(dateStr: dateStr, live: live)
        let doneIDs = Set(goals.activeGoals(on: dateStr).filter { isDone($0, rec: rec) }.map { $0.id })
        let activeBundleId = live.isIdle ? nil : live.delta?.bundleId   // 지금 돌아가는 앱
        let groups = categoryGroups(for: rec, categorizer: categorizer)
        VStack(alignment: .leading, spacing: 0) {
            header(date: now, isIdle: live.isIdle, rec: rec)
            Divider()

            if rec.apps.values.contains(where: { $0.seconds >= 1 }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                            CategorySectionView(group: group, activeBundleId: activeBundleId)
                            if idx < groups.count - 1 { Divider() }
                        }
                    }
                    .padding(16)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ListHeightKey.self, value: g.size.height)
                    })
                }
                // 내용에 맞춰 높이 결정(여백 제거), 너무 길면 최대 460에서 스크롤
                .frame(height: min(max(listHeight, 60), 460))
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
            } else {
                emptyState
            }

            Divider()
            footer(rec: rec)
        }
        .frame(width: 400)
        .overlay {
            if isCelebrating {
                CelebrationView(kind: celebrationKind).id(celebrationTrigger)
            }
        }
        .onAppear {
            computeStreaks()
            celebrate(doneIDs: committedDoneIDs())   // 닫혀 있는 동안 달성한 것 확인 시 1회 축하
        }
        .onChange(of: doneIDs) { _, new in
            celebrate(doneIDs: new)                   // 보고 있는 동안 달성하면 축하
            computeStreaks()
        }
    }

    private func isDone(_ goal: Goal, rec: DayRecord) -> Bool {
        goal.targetSeconds > 0 && (rec.apps[goal.bundleId]?.seconds ?? 0) >= goal.targetSeconds
    }

    /// 아직 축하하지 않은 달성 목표가 있으면 컨페티 1회. 축하한 목표는 영구 기록해 재발생 방지.
    private func celebrate(doneIDs: Set<UUID>) {
        let today = Storage.todayString()
        var fired = false
        for id in doneIDs {
            let key = "\(id.uuidString)-\(today)"
            if !goals.isCelebrated(key) {
                goals.markCelebrated(key)
                fired = true
            }
        }
        if fired {
            DispatchQueue.main.async {
                celebrationKind = CelebrationKind.allCases.randomElement()!   // 매번 랜덤 효과
                celebrationTrigger &+= 1
                isCelebrating = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { isCelebrating = false }
            }
        }
    }

    /// 디스크에 정산된(라이브 제외) 오늘 기준 달성 목표.
    private func committedDoneIDs() -> Set<UUID> {
        let today = Storage.todayString()
        return Set(goals.activeGoals(on: today)
            .filter { isDone($0, rec: engine.today) }
            .map { $0.id })
    }

    // MARK: - 헤더

    private func header(date: Date, isIdle: Bool, rec: DayRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 타이틀 + 액션 아이콘 (디자인 시스템 §6.1)
            HStack {
                Text(koreanDate(date)).font(.headline)
                Spacer()
                HStack(spacing: 14) {
                    Button { openStats() } label: { Image(systemName: "chart.bar.xaxis") }
                        .help("통계")
                    Button { showCalendar.toggle() } label: { Image(systemName: "calendar") }
                        .help("다른 날짜 선택")
                        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                            datePicker(now: Date())
                                .onAppear { detailDate = nil; loadDateRows(now: Date()) }
                        }
                    Button { openSettings() } label: { Image(systemName: "gearshape") }
                        .help("설정")
                    Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                        .help("종료")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            // 오늘 총 작업 시간
            HStack(spacing: 6) {
                Text("오늘 총 작업 시간")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(rec.totalSeconds))
                    .font(.title3.monospacedDigit().weight(.semibold))
                if isIdle {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.secondary)
                        .help("유휴 상태 — 측정 일시정지 중")
                }
            }

            Group {
                let active = goals.activeGoals(on: Storage.todayString())
                if !active.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(active) { goalRow($0, rec: rec) }
                    }
                    .padding(.top, 2)
                }

                // 목표 세우기 버튼 — 진행 중 목표 리스트 아래 고정
                Button { showGoalSetup = true } label: {
                    Label("오늘의 목표 세우기", systemImage: "target")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandOrange)
                .padding(.top, 2)
            }
        }
        .padding(16)
    }

    /// 목표 진행률 한 줄(앱 + 현재/목표 + % + 프로그레스바).
    /// 진행률은 그날 그 앱의 전체 사용량(자정 기준) 기준.
    private func goalRow(_ goal: Goal, rec: DayRecord) -> some View {
        let current = rec.apps[goal.bundleId]?.seconds ?? 0
        let pct = goal.targetSeconds > 0 ? min(1, current / goal.targetSeconds) : 0
        let done = isDone(goal, rec: rec)
        let overage = current - goal.targetSeconds
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppIconView(bundleId: goal.bundleId, size: 18)
                Text(goal.displayName).font(.callout).lineLimit(1)
                if goal.repeatsDaily, let s = streaks[goal.id], s > 0 {
                    Text("🔥\(s)").font(.caption2.weight(.bold)).foregroundStyle(Color.brandOrange)
                        .help("\(s)일 연속 달성")
                } else if goal.repeatsDaily {
                    Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if done {
                    HStack(spacing: 5) {
                        Text(formatDuration(goal.targetSeconds))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "trophy.fill")
                            Text("달성")
                        }
                        .font(.caption2.weight(.bold)).foregroundStyle(Color.brandGold)
                        if overage >= 60 {
                            Text("+\(formatDuration(overage)) 💪")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("\(formatDuration(current)) / \(formatDuration(goal.targetSeconds)) (\(Int(pct * 100))%)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button { goals.remove(goal.id) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("목표 삭제")
            }
            ProgressView(value: pct)
                .tint(done ? .brandGold : .brandOrange)
        }
    }

    // MARK: - 연속 달성 스트릭

    private func computeStreaks() {
        var result: [UUID: Int] = [:]
        for goal in goals.activeGoals(on: Storage.todayString()) where goal.repeatsDaily {
            result[goal.id] = streak(for: goal)
        }
        streaks = result
    }

    /// 오늘부터 거슬러 연속으로 목표를 채운 날 수. 오늘이 아직 미달성이면 깨지 않고 건너뜀.
    private func streak(for goal: Goal) -> Int {
        guard goal.targetSeconds > 0 else { return 0 }
        let cal = Calendar.current
        let todayStr = Storage.todayString()
        var day = cal.startOfDay(for: Date())
        var count = 0
        while true {
            let ymd = Storage.string(from: day)
            if ymd < goal.startDay { break }
            let rec = ymd == todayStr ? engine.today : engine.storage.load(date: ymd)
            let secs = rec.apps[goal.bundleId]?.seconds ?? 0
            if secs >= goal.targetSeconds {
                count += 1
            } else if ymd == todayStr {
                // 오늘은 아직 진행 중일 수 있으니 스트릭을 깨지 않고 건너뜀
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    // MARK: - 날짜 선택 (기록된 날짜 목록)

    @ViewBuilder
    private func datePicker(now: Date) -> some View {
        if let d = detailDate {
            // 상세 보기 (달력 팝오버 안에서 전환)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { detailDate = nil } label: {
                        Label("날짜 목록", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.top, 12)
                DayDetailView(dateStr: d)
                    .environmentObject(engine)
                    .environmentObject(categorizer)
            }
        } else {
            dateListView(now: now)
        }
    }

    private func dateListView(now: Date) -> some View {
        let todayStr = Storage.string(from: now)
        let months = availableMonths                       // 최신순
        let idx = months.firstIndex(of: pickerMonth)
        let rows = dateRows.filter { $0.ymd.hasPrefix(pickerMonth) }
        let monthTotal = rows.reduce(0) { $0 + $1.total }

        return VStack(alignment: .leading, spacing: 0) {
            // 월 이동 헤더:  < 2026년 6월 >
            HStack {
                Button { if let i = idx, i + 1 < months.count { pickerMonth = months[i + 1] } }
                    label: { Image(systemName: "chevron.left").font(.title3) }
                    .buttonStyle(.borderless)
                    .disabled(idx == nil || idx! + 1 >= months.count)
                Spacer()
                VStack(spacing: 2) {
                    Text(monthTitle(pickerMonth)).font(.headline)
                    Text("\(rows.count)일 · \(formatDuration(monthTotal))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { if let i = idx, i > 0 { pickerMonth = months[i - 1] } }
                    label: { Image(systemName: "chevron.right").font(.title3) }
                    .buttonStyle(.borderless)
                    .disabled(idx == nil || idx! <= 0)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        dateRowButton(row, todayStr: todayStr)
                        Divider()
                    }
                }
            }
        }
        .frame(width: 300, height: 420)
    }

    /// 기록이 있는 월 목록(최신순).
    private var availableMonths: [String] {
        var seen: [String] = []
        for row in dateRows {
            let key = String(row.ymd.prefix(7))
            if seen.last != key { seen.append(key) }
        }
        return seen
    }

    private func dateRowButton(_ row: DateRow, todayStr: String) -> some View {
        let isToday = row.ymd == todayStr
        return Button {
            // 오늘은 이미 메인 팝오버에 보이므로 닫기만, 과거 날짜는 달력 팝오버 안에서 상세로 전환
            if isToday {
                showCalendar = false
            } else {
                detailDate = row.ymd
            }
        } label: {
            HStack(spacing: 8) {
                Text(koreanDateString(row.ymd))
                    .font(.body.weight(isToday ? .bold : .regular))
                if isToday {
                    Text("오늘")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.brandOrange.opacity(0.25))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(formatDuration(row.total))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(isToday ? Color.brandOrange.opacity(0.18) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 팝오버를 열 때 한 번 호출: 기록 날짜와 각 일자 총합을 읽어 캐싱.
    private func loadDateRows(now: Date) {
        let todayStr = Storage.string(from: now)
        var ymds = engine.storage.availableDates()           // 최신순
        if !ymds.contains(todayStr) { ymds.insert(todayStr, at: 0) }
        dateRows = ymds.map { ymd in
            let rec = ymd == todayStr ? engine.today : engine.storage.load(date: ymd)
            // 시스템 프로세스(loginwindow 등) 제외한 합계
            let total = rec.apps.values
                .filter { !SystemApps.isIgnored(bundleId: $0.bundleId, displayName: $0.displayName) }
                .reduce(0) { $0 + $1.seconds }
            return DateRow(ymd: ymd, total: total)
        }
        // 기본: 오늘이 속한 달을 보여줌.
        let todayMonth = String(todayStr.prefix(7))
        pickerMonth = availableMonths.contains(todayMonth) ? todayMonth
                                                           : (availableMonths.first ?? todayMonth)
    }

    private func monthTitle(_ yearMonth: String) -> String {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2 else { return yearMonth }
        return "\(parts[0])년 \(Int(parts[1]) ?? 0)월"
    }

    private func koreanDateString(_ ymd: String) -> String {
        guard let d = Storage.dateFormatter.date(from: ymd) else { return ymd }
        return koreanDate(d)
    }

    // MARK: - 빈 상태 / 푸터

    private var emptyState: some View {
        VStack(spacing: 12) {
            WorkieView(size: 76)
            Text("오늘은 아직 부스러기가 없어요")
                .font(.callout).foregroundStyle(.secondary)
            Text("앱을 쓰기 시작하면 여기에 차곡차곡 쌓여요")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    /// 푸터: 좌측 상태 + 우측 버전 (caption2 · tertiary).
    private func footer(rec: DayRecord) -> some View {
        let count = rec.apps.values.filter { $0.seconds >= 1 }.count
        return HStack {
            Text("오늘 \(count)개 앱")
            Spacer()
            Text("v\(appVersion)")
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    private func openSettings() {
        showCalendar = false
        SettingsWindowController.shared.show(engine: engine)
    }

    private func openStats() {
        showCalendar = false
        StatsWindowController.shared.show(engine: engine)
    }

    // MARK: - 로직

    /// 표시용 기록: 오늘이면 진행 중 세션의 미정산 시간까지 더해 라이브로 보여준다.
    /// 과거에 잘못 쌓인 시스템 프로세스(loginwindow 등)는 표시에서 제외.
    private func displayRecord(dateStr: String, live: TrackingEngine.LiveState) -> DayRecord {
        var rec = engine.record(for: dateStr)
        rec.apps = rec.apps.filter {
            !SystemApps.isIgnored(bundleId: $0.value.bundleId, displayName: $0.value.displayName)
        }
        if let d = live.delta {
            rec.add(bundleId: d.bundleId, displayName: d.displayName, seconds: d.seconds)
        }
        return rec
    }

    private func koreanDate(_ date: Date) -> String {
        koreanDateFormatter.string(from: date)
    }
}

struct CategoryGroup: Identifiable {
    let name: String
    let apps: [AppUsage]
    let seconds: Double
    var id: String { name }
}

/// 카테고리 목록의 실제 콘텐츠 높이를 부모로 전달(여백 없는 팝오버 높이 계산용).
struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 날짜 선택 목록의 한 줄(날짜 + 그날 총합).
struct DateRow: Identifiable {
    let ymd: String        // "yyyy-MM-dd"
    let total: Double
    var id: String { ymd }
}

