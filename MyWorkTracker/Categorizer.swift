import Foundation
import Combine

/// 한번이라도 최전면에 등장한 앱. 영구 목록(레지스트리)에 쌓인다.
struct KnownApp: Codable, Identifiable {
    let bundleId: String
    var displayName: String
    var id: String { bundleId }
}

/// 앱 → 카테고리 매핑. 기본 룰 + 사용자 룰 + KnownApp 레지스트리 관리.
final class Categorizer: ObservableObject {
    /// 사용자가 지정한 룰 (bundleId -> 카테고리). UserDefaults에 영구 저장.
    @Published private(set) var userRules: [String: String] = [:]
    /// 인식된 앱 레지스트리 (bundleId -> KnownApp).
    @Published private(set) var knownApps: [String: KnownApp] = [:]
    /// 카테고리 목록(순서 유지, 마지막은 항상 `기본`). 사용자가 편집 가능.
    @Published private(set) var categories: [String] = DefaultCategory.initialList

    private let rulesKey = "userCategoryRules"
    private let knownKey = "knownApps"
    private let categoriesKey = "categories"

    /// 기본 룰: 부분 문자열(소문자) 매칭. bundleId 또는 displayName 어느 쪽이든.
    private static let defaultRules: [(needle: String, category: String)] = [
        // 편집 작업
        ("final cut", DefaultCategory.editing),
        ("finalcut", DefaultCategory.editing),
        ("premiere", DefaultCategory.editing),
        ("davinci", DefaultCategory.editing),
        ("photoshop", DefaultCategory.editing),
        ("lightroom", DefaultCategory.editing),
        ("after effects", DefaultCategory.editing),
        ("illustrator", DefaultCategory.editing),
        ("figma", DefaultCategory.editing),
        // 업무
        ("notion", DefaultCategory.work),
        ("slack", DefaultCategory.work),
        ("mail", DefaultCategory.work),
        ("outlook", DefaultCategory.work),
        ("calendar", DefaultCategory.work),
        ("excel", DefaultCategory.work),
        ("word", DefaultCategory.work),
        ("powerpoint", DefaultCategory.work),
        ("keynote", DefaultCategory.work),
        ("numbers", DefaultCategory.work),
        ("pages", DefaultCategory.work),
        // AI 툴
        ("claude", DefaultCategory.ai),
        ("chatgpt", DefaultCategory.ai),
        ("openai", DefaultCategory.ai),
        ("codex", DefaultCategory.ai),
        ("cursor", DefaultCategory.ai),
        ("terminal", DefaultCategory.ai),
        ("iterm", DefaultCategory.ai),
        ("xcode", DefaultCategory.ai),
        ("code", DefaultCategory.ai),   // VS Code
    ]

    init() {
        load()
    }

    // MARK: - 조회

    /// 앱의 카테고리. 우선순위: 사용자 룰 > 기본 룰 > 기본(fallback).
    /// 해석된 카테고리가 현재 목록에 없으면(삭제됐으면) `기본`으로 대체.
    func category(bundleId: String, displayName: String) -> String {
        let resolved = resolvedCategory(bundleId: bundleId, displayName: displayName)
        return categories.contains(resolved) ? resolved : DefaultCategory.fallback
    }

    private func resolvedCategory(bundleId: String, displayName: String) -> String {
        if let user = userRules[bundleId] { return user }
        let hay = (bundleId + " " + displayName).lowercased()
        for rule in Self.defaultRules where hay.contains(rule.needle) {
            return rule.category
        }
        return DefaultCategory.fallback
    }

    /// 현재 카테고리 목록(순서 유지).
    func allCategoryNames() -> [String] { categories }

    // MARK: - 카테고리 추가/수정/삭제

    /// 추가 가능 여부 검증 결과(불가 사유 메시지, 가능하면 nil).
    func validationError(for name: String, excluding: String? = nil) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "이름을 입력하세요." }
        if trimmed.count > DefaultCategory.maxNameLength {
            return "최대 \(DefaultCategory.maxNameLength)자까지 가능합니다."
        }
        let exists = categories.contains {
            $0 != excluding && $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if exists { return "이미 있는 이름입니다." }
        return nil
    }

    /// 카테고리 추가. 성공 시 true. fallback 앞에 삽입(fallback은 항상 마지막).
    @discardableResult
    func addCategory(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard validationError(for: trimmed) == nil else { return false }
        let insertAt = max(0, categories.count - 1)   // fallback 앞
        categories.insert(trimmed, at: insertAt)
        saveCategories()
        return true
    }

    /// 카테고리 이름 변경. fallback은 변경 불가. 기존에 그 카테고리를 쓰던 룰도 갱신.
    @discardableResult
    func renameCategory(_ old: String, to new: String) -> Bool {
        guard old != DefaultCategory.fallback else { return false }
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard validationError(for: trimmed, excluding: old) == nil,
              let idx = categories.firstIndex(of: old) else { return false }
        categories[idx] = trimmed
        for (bid, cat) in userRules where cat == old { userRules[bid] = trimmed }
        saveCategories()
        saveRules()
        return true
    }

    /// 카테고리 삭제. fallback은 삭제 불가. 그 카테고리를 쓰던 앱들은 `기본`으로 복귀.
    @discardableResult
    func deleteCategory(_ name: String) -> Bool {
        guard name != DefaultCategory.fallback,
              let idx = categories.firstIndex(of: name) else { return false }
        categories.remove(at: idx)
        for (bid, cat) in userRules where cat == name { userRules.removeValue(forKey: bid) }
        saveCategories()
        saveRules()
        return true
    }

    // MARK: - 변경

    /// 최전면에 앱이 등장하면 레지스트리에 등록(중복/이름변경 반영).
    func register(bundleId: String, displayName: String) {
        if let existing = knownApps[bundleId], existing.displayName == displayName { return }
        knownApps[bundleId] = KnownApp(bundleId: bundleId, displayName: displayName)
        saveKnown()
    }

    /// 앱의 카테고리를 사용자 지정으로 설정.
    func setCategory(_ category: String, for bundleId: String) {
        userRules[bundleId] = category
        saveRules()
    }

    /// 사용자 지정 룰 제거(기본/기타로 복귀).
    func clearCategory(for bundleId: String) {
        userRules.removeValue(forKey: bundleId)
        saveRules()
    }

    // MARK: - 영구 저장

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            userRules = decoded
        }
        if let data = d.data(forKey: knownKey),
           let decoded = try? JSONDecoder().decode([String: KnownApp].self, from: data) {
            knownApps = decoded
        }
        if let data = d.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            // fallback이 항상 마지막에 존재하도록 보정
            var list = decoded.filter { $0 != DefaultCategory.fallback }
            list.append(DefaultCategory.fallback)
            categories = list
        }
    }

    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(userRules) {
            UserDefaults.standard.set(data, forKey: rulesKey)
        }
    }

    private func saveKnown() {
        if let data = try? JSONEncoder().encode(knownApps) {
            UserDefaults.standard.set(data, forKey: knownKey)
        }
    }
}
