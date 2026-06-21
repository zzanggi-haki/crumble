import Foundation
import Combine

/// 오늘(또는 매일 반복) 특정 앱을 목표 시간만큼 쓰자는 목표.
struct Goal: Codable, Identifiable {
    var id = UUID()
    var bundleId: String
    var displayName: String
    var targetSeconds: Double
    var repeatsDaily: Bool
    var startDay: String          // "yyyy-MM-dd" 목표를 시작한 날
}

final class GoalStore: ObservableObject {
    @Published private(set) var goals: [Goal] = []
    /// 이미 달성 축하(컨페티)를 보여준 목표 키("goalId-yyyy-MM-dd"). 1회성 보장용.
    @Published private(set) var celebratedKeys: Set<String> = []

    private let key = "goals"
    private let celebratedDefaultsKey = "celebratedGoalKeys"

    init() { load() }

    // MARK: - 달성 축하 1회성

    func isCelebrated(_ key: String) -> Bool { celebratedKeys.contains(key) }

    func markCelebrated(_ key: String) {
        guard !celebratedKeys.contains(key) else { return }
        celebratedKeys.insert(key)
        UserDefaults.standard.set(Array(celebratedKeys), forKey: celebratedDefaultsKey)
    }

    /// 해당 날짜에 적용되는 목표들. 반복 목표는 시작일 이후 매일, 단발 목표는 시작일에만.
    func activeGoals(on day: String) -> [Goal] {
        goals.filter { $0.repeatsDaily ? $0.startDay <= day : $0.startDay == day }
    }

    func add(_ goal: Goal) { goals.append(goal); save() }
    func remove(_ id: UUID) { goals.removeAll { $0.id == id }; save() }

    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let g = try? JSONDecoder().decode([Goal].self, from: d) { goals = g }
        // 축하 기록은 오늘 것만 유지(과거 키는 불필요).
        let todaySuffix = "-" + Storage.todayString()
        if let arr = UserDefaults.standard.array(forKey: celebratedDefaultsKey) as? [String] {
            celebratedKeys = Set(arr.filter { $0.hasSuffix(todaySuffix) })
        }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(goals) { UserDefaults.standard.set(d, forKey: key) }
    }
}
