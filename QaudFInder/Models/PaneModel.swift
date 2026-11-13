//
//  PaneModel.swift
//  QuadFinder — 칸(패널) 하나의 상태: 현재 폴더, 파일 목록, 선택, 정렬, 뒤로/앞으로 기록
//

import Foundation
import AppKit
import Combine

@MainActor
final class PaneModel: ObservableObject {
    let index: Int
    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var freeSpaceText: String = ""
    @Published var errorMessage: String? = nil
    @Published var selection = Set<URL>()
    @Published var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "pane\(index).viewMode") }
    }
    @Published private(set) var sortKey: SortKey
    @Published private(set) var sortAscending: Bool

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var anchor: URL? = nil          // 마지막으로 선택한 파일 (Shift 범위 선택, 훑어보기 대상)

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    init(index: Int, defaultURL: URL) {
        self.index = index
        let defaults = UserDefaults.standard

        // 지난번에 열어 둔 폴더가 있으면 그 폴더로 시작
        var start = defaultURL
        if let saved = defaults.string(forKey: "pane\(index).path") {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: saved, isDirectory: &isDir), isDir.boolValue {
                start = URL(fileURLWithPath: saved)
            }
        }
        _currentURL = Published(initialValue: start)

        // 지난번 보기 방식·정렬 기억
        let savedMode = defaults.string(forKey: "pane\(index).viewMode")
            .flatMap { ViewMode(rawValue: $0) } ?? .list
        _viewMode = Published(initialValue: savedMode)
        let savedSort = defaults.string(forKey: "pane\(index).sortKey")
            .flatMap { SortKey(rawValue: $0) } ?? .name
        _sortKey = Published(initialValue: savedSort)
        _sortAscending = Published(initialValue: defaults.object(forKey: "pane\(index).sortAscending") as? Bool ?? true)

        reload()
    }

    // MARK: 이동

    func open(_ url: URL) {
        guard url.standardizedFileURL.path != currentURL.standardizedFileURL.path else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        setCurrent(url)
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        setCurrent(prev)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        setCurrent(next)
    }

    func goUp() {
        guard currentURL.standardizedFileURL.path != "/" else { return }
        open(currentURL.deletingLastPathComponent())
    }

    private func setCurrent(_ url: URL) {
        currentURL = url.standardizedFileURL
        selection.removeAll()
        anchor = nil
        UserDefaults.standard.set(currentURL.path, forKey: "pane\(index).path")
        reload()
    }

    // 더블클릭·Return·⌘↓: 폴더 하나면 들어가고, 파일이면 기본 앱으로 열기
    func activate(_ urls: [URL]) {
        let chosen = items.filter { urls.contains($0.url) }
        if chosen.count == 1, let only = chosen.first, only.isDirectory {
            open(only.url)
            return
        }
        for item in chosen where !item.isDirectory {
            NSWorkspace.shared.open(item.url)
        }
    }

    // MARK: 선택

    // 목록(표·아이콘)이 선택을 직접 처리한 뒤 결과만 알려 줄 때
    func setSelection(_ urls: Set<URL>, anchor newAnchor: URL?) {
        if selection != urls { selection = urls }
        anchor = newAnchor
    }

    // 훑어보기 대상: 한 번에 하나만 (마지막으로 선택한 파일 우선)
    var previewTarget: URL? {
        if let anchor, selection.contains(anchor) { return anchor }
        return selection.first
    }

    // MARK: 정렬

    func setSort(_ key: SortKey, ascending: Bool) {
        guard key != sortKey || ascending != sortAscending else { return }
        sortKey = key
        sortAscending = ascending
        UserDefaults.standard.set(key.rawValue, forKey: "pane\(index).sortKey")
        UserDefaults.standard.set(ascending, forKey: "pane\(index).sortAscending")
        items = sorted(items)
    }

    // 폴더는 항상 위쪽, 그 안에서 정렬 기준대로. 값이 같으면 이름순.
    private func sorted(_ list: [FileItem]) -> [FileItem] {
        let key = sortKey
        let ascending = sortAscending
        return list.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: ComparisonResult
            switch key {
            case .name:     result = a.name.localizedStandardCompare(b.name)
            case .modified: result = Self.compare(a.modified ?? .distantPast, b.modified ?? .distantPast)
            case .size:     result = Self.compare(a.size ?? -1, b.size ?? -1)
            case .kind:     result = a.kind.localizedStandardCompare(b.kind)
            }
            if result == .orderedSame {
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult {
        x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
    }

    // MARK: 목록 읽기

    func reload() {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .fileSizeKey,
            .contentModificationDateKey, .localizedNameKey, .localizedTypeDescriptionKey
        ]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]          // 숨김 파일은 표시하지 않음
            )
            items = sorted(urls.map { u in
                let v = try? u.resourceValues(forKeys: Set(keys))
                let isDir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
                return FileItem(
                    url: u,
                    name: v?.localizedName ?? u.lastPathComponent,
                    isDirectory: isDir,
                    size: isDir ? nil : v?.fileSize.map { Int64($0) },
                    modified: v?.contentModificationDate,
                    kind: v?.localizedTypeDescription ?? ""
                )
            })
            errorMessage = nil
        } catch {
            items = []
            errorMessage = "이 폴더를 열 수 없습니다: \(error.localizedDescription)"
        }

        // 지워진 파일은 선택에서 빼기
        let existing = Set(items.map { $0.url })
        selection = selection.filter { existing.contains($0) }

        // 아래 상태줄의 "OO GB 사용 가능"
        if let v = try? currentURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = v.volumeAvailableCapacityForImportantUsage {
            freeSpaceText = ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " 사용 가능"
        } else {
            freeSpaceText = ""
        }
    }

    // 아래쪽 경로 막대용: [/, /Users, /Users/tissant, /Users/tissant/Desktop]
    var pathComponents: [URL] {
        var result: [URL] = []
        var u = currentURL.standardizedFileURL
        var guardCount = 0
        while u.path != "/" && !u.path.isEmpty && guardCount < 100 {
            result.append(u)
            u = u.deletingLastPathComponent().standardizedFileURL
            guardCount += 1
        }
        result.append(URL(fileURLWithPath: "/"))
        return result.reversed()
    }

    // MARK: 복사 (다른 칸이나 Finder에서 끌어다 놓았을 때)
    // 안전을 위해 "이동"이 아니라 항상 "복사"만 합니다. 원본은 그대로 남습니다.

    func copyIn(_ sources: [URL]) {
        var failed: [String] = []
        for src in sources {
            // 같은 폴더에 다시 놓은 경우는 무시
            if src.deletingLastPathComponent().standardizedFileURL.path == currentURL.standardizedFileURL.path {
                continue
            }
            let dest = uniqueDestination(currentURL.appendingPathComponent(src.lastPathComponent))
            do {
                try FileManager.default.copyItem(at: src, to: dest)
            } catch {
                failed.append(src.lastPathComponent)
            }
        }
        reload()
        if !failed.isEmpty {
            errorMessage = "복사 실패: " + failed.joined(separator: ", ")
        }
    }

    // 같은 이름이 있으면 덮어쓰지 않고 "이름 2.확장자" 식으로 새 이름을 만듦
    private func uniqueDestination(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
