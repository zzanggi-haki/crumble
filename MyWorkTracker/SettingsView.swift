import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "gearshape") }
            CategorySettingsView()
                .tabItem { Label("카테고리", systemImage: "tag") }
        }
        .frame(width: 480, height: 600)
    }
}

// MARK: - 일반

struct GeneralSettingsView: View {
    @EnvironmentObject var engine: TrackingEngine
    @EnvironmentObject var storage: Storage

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var moveDataOnChange = true

    private var idleMinutes: Binding<Double> {
        Binding(get: { engine.idleThresholdSeconds / 60 },
                set: { engine.idleThresholdSeconds = max(1, $0) * 60 })
    }

    var body: some View {
        Form {
            Section("시작") {
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("로그인 시 시작하기")
                        Text("맥을 켜면 자동으로 실행됩니다")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
            }

            Section("측정") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("유휴 임계값")
                        Spacer()
                        Text("\(Int(idleMinutes.wrappedValue))분")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Slider(value: idleMinutes, in: 1...30, step: 1)
                    Text("이 시간 동안 키보드·마우스 입력이 없으면 측정을 일시정지합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("데이터 저장 폴더") {
                Text(storage.folderURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Toggle("폴더 변경 시 기존 기록도 함께 이동", isOn: $moveDataOnChange)
                HStack {
                    Button("폴더 변경…") { chooseFolder() }
                    Button("기본 폴더로 되돌리기") {
                        storage.resetToDefaultFolder(moveExisting: moveDataOnChange)
                    }
                    Spacer()
                    Button("Finder에서 열기") {
                        NSWorkspace.shared.open(storage.folderURL)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "이 폴더 사용"
        panel.directoryURL = storage.folderURL
        if panel.runModal() == .OK, let url = panel.url {
            storage.setFolder(url, moveExisting: moveDataOnChange)
        }
    }
}

// MARK: - 카테고리 (내 업무 카테고리 설정하기)

struct CategorySettingsView: View {
    @EnvironmentObject var categorizer: Categorizer

    @State private var newName = ""
    @State private var addError: String?
    @State private var editingCategory: String?   // 이름 변경 중인 카테고리
    @State private var editText = ""

    private var apps: [KnownApp] {
        categorizer.knownApps.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            categoryManager
            Divider()
            appAssignment
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 카테고리 관리

    private var categoryManager: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("카테고리")

            // 추가 입력
            HStack {
                TextField("새 카테고리 (최대 \(DefaultCategory.maxNameLength)자)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: newName) { _, v in
                        if v.count > DefaultCategory.maxNameLength {
                            newName = String(v.prefix(DefaultCategory.maxNameLength))
                        }
                        addError = nil
                    }
                    .onSubmit(addCategory)
                Button("추가", action: addCategory)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addError {
                Text(addError).font(.caption).foregroundStyle(.red)
            }

            // 카테고리 목록 (수정/삭제)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(categorizer.allCategoryNames(), id: \.self) { name in
                        categoryRow(name)
                        Divider()
                    }
                }
            }
            .frame(height: 150)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private func categoryRow(_ name: String) -> some View {
        let isFallback = name == DefaultCategory.fallback
        return HStack(spacing: 8) {
            if editingCategory == name {
                TextField("", text: $editText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: editText) { _, v in
                        if v.count > DefaultCategory.maxNameLength {
                            editText = String(v.prefix(DefaultCategory.maxNameLength))
                        }
                    }
                    .onSubmit { commitRename(name) }
                Button("저장") { commitRename(name) }
                Button("취소") { editingCategory = nil }
            } else {
                Text(name)
                if isFallback {
                    Text("기본값 · 삭제 불가").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if !isFallback {
                    Button { startRename(name) } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                    Button { categorizer.deleteCategory(name) } label: {
                        Image(systemName: "trash").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    // MARK: 앱별 카테고리

    private var appAssignment: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("앱별 카테고리")
            Text("인식된 앱마다 어떤 카테고리로 묶을지 지정하세요.")
                .font(.caption).foregroundStyle(.secondary)

            if apps.isEmpty {
                VStack(spacing: 10) {
                    WorkieView(size: 60)
                    Text("아직 인식된 앱이 없어요")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("앱을 사용하면 자동으로 추가됩니다")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List {
                    ForEach(apps) { app in
                        HStack(spacing: 10) {
                            AppIconView(bundleId: app.bundleId, size: 24)
                            Text(app.displayName).font(.body).lineLimit(1)
                            Spacer()
                            categoryPicker(for: app)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func categoryPicker(for app: KnownApp) -> some View {
        let current = categorizer.category(bundleId: app.bundleId, displayName: app.displayName)
        return Picker("", selection: Binding(
            get: { current },
            set: { categorizer.setCategory($0, for: app.bundleId) }
        )) {
            ForEach(categorizer.allCategoryNames(), id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    // MARK: 액션

    private func addCategory() {
        if let err = categorizer.validationError(for: newName) {
            addError = err
            return
        }
        categorizer.addCategory(newName)
        newName = ""
        addError = nil
    }

    private func startRename(_ name: String) {
        editingCategory = name
        editText = name
    }

    private func commitRename(_ old: String) {
        if categorizer.renameCategory(old, to: editText) {
            editingCategory = nil
        }
    }
}
