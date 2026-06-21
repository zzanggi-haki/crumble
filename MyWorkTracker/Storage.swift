import Foundation
import Combine

/// 날짜별 JSON 파일 저장/로드. 저장 폴더는 기본 자동 생성, 설정에서 변경 가능.
final class Storage: ObservableObject {
    private let bookmarkKey = "storageFolderBookmark"

    /// 현재 저장 폴더(표시용). 변경 시 UI 갱신.
    @Published private(set) var folderURL: URL

    /// 보안 스코프 접근 중인 URL(설정에서 고른 폴더일 때). 기본 폴더면 nil.
    private var scopedURL: URL?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        folderURL = Storage.defaultFolder()
        ensureFolder(folderURL)
        restoreBookmarkedFolderIfAny()
    }

    // MARK: - 폴더 관리

    static func defaultFolder() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MyWorkTracker", isDirectory: true)
    }

    private func ensureFolder(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// 설정에서 새 폴더 선택. 보안 스코프 북마크로 저장해 재시작 후에도 접근 유지.
    /// moveExisting=true 면 기존 날짜 파일들을 새 폴더로 이동.
    func setFolder(_ newURL: URL, moveExisting: Bool) {
        let old = folderURL
        ensureFolder(newURL)

        if moveExisting {
            moveAllRecords(from: old, to: newURL)
        }

        // 새 폴더 보안 스코프 북마크 저장
        if let data = try? newURL.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }

        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = newURL
        _ = newURL.startAccessingSecurityScopedResource()
        folderURL = newURL
    }

    /// 저장 폴더를 기본 위치로 되돌림.
    func resetToDefaultFolder(moveExisting: Bool) {
        let def = Storage.defaultFolder()
        ensureFolder(def)
        if moveExisting { moveAllRecords(from: folderURL, to: def) }
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        folderURL = def
    }

    private func restoreBookmarkedFolderIfAny() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return }
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
            ensureFolder(url)
            folderURL = url
        }
    }

    private func moveAllRecords(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) else { return }
        for item in items where item.pathExtension == "json" {
            let dest = new.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try? fm.moveItem(at: item, to: dest)
        }
    }

    // MARK: - 레코드 입출력

    private func fileURL(for date: String) -> URL {
        folderURL.appendingPathComponent("\(date).json")
    }

    func load(date: String) -> DayRecord {
        let url = fileURL(for: date)
        guard let data = try? Data(contentsOf: url),
              let record = try? decoder.decode(DayRecord.self, from: data) else {
            return DayRecord(date: date)
        }
        return record
    }

    func save(_ record: DayRecord) {
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: fileURL(for: record.date), options: .atomic)
    }

    /// 저장된 날짜 목록(최신순).
    func availableDates() -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else { return [] }
        return items
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { Storage.dateFormatter.date(from: $0) != nil }
            .sorted(by: >)
    }

    static func todayString() -> String {
        dateFormatter.string(from: Date())
    }

    static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
