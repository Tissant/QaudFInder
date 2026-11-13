//
//  PaneModel.swift
//  QuadFinder — 칸(패널) 하나의 상태: 현재 폴더, 파일 목록, 선택, 정렬, 뒤로/앞으로 기록,
//  그리고 파일 조작(휴지통, 이름 바꾸기, 새 폴더, 복사·이동, 붙여넣기)
//
//  안전 규칙: 파일을 지울 때는 항상 "휴지통으로 이동"만 합니다. 완전 삭제 코드는 없습니다.
//

import Foundation
import AppKit
import Combine

@MainActor
final class PaneModel: ObservableObject {
    let index: Int
    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var folderSizeText: String = ""    // 상태줄: 이 폴더가 차지하는 용량
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

    private var sizeTask: Task<Void, Never>? = nil   // 폴더 용량 계산 (백그라운드)

    // 열려 있는 모든 칸 (파일을 바꾼 뒤 같은 폴더를 보는 다른 칸도 새로고침하려고)
    private static let allPanes = NSHashTable<PaneModel>.weakObjects()

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

        PaneModel.allPanes.add(self)
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

        computeFolderSize()
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

    // MARK: 폴더 용량 (하위 폴더까지 전부 더함)
    // 큰 폴더는 오래 걸리므로 화면 뒤(백그라운드)에서 계산하고, 폴더를 옮기면 이전 계산은 취소합니다.

    private func computeFolderSize() {
        sizeTask?.cancel()
        folderSizeText = "계산 중…"
        let url = currentURL
        sizeTask = Task.detached(priority: .utility) { [weak self] in
            let total = PaneModel.totalSize(of: url)
            await self?.finishFolderSize(total, for: url)
        }
    }

    private func finishFolderSize(_ total: Int64?, for url: URL) {
        guard url == currentURL else { return }       // 그사이 다른 폴더로 옮겼으면 버림
        if let total {
            folderSizeText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        } else if !Task.isCancelled {
            folderSizeText = ""
        }
    }

    // 백그라운드에서 실행됨. 취소되면 nil.
    nonisolated private static func totalSize(of folder: URL) -> Int64? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [],
            errorHandler: { _, _ in true }                 // 권한 없는 폴더는 건너뛰고 계속
        ) else { return nil }

        // 맨 위(/)에서 계산할 때 같은 디스크를 두 번 세거나 외장 디스크까지 세지 않도록
        let skip: Set<String> = ["/Volumes", "/System/Volumes", "/dev"]
        var total: Int64 = 0
        var count = 0
        for case let url as URL in walker {
            count += 1
            if count % 500 == 0 && Task.isCancelled { return nil }
            if skip.contains(url.path) {
                walker.skipDescendants()
                continue
            }
            if let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return Task.isCancelled ? nil : total
    }

    // MARK: 다른 칸 새로고침
    // 파일을 바꾼 뒤, 바뀐 폴더를 보고 있는 칸(이 칸 포함)을 모두 새로고침합니다.

    static func refreshPanes(showing folders: [URL]) {
        let paths = Set(folders.map { $0.standardizedFileURL.path })
        for pane in allPanes.allObjects where paths.contains(pane.currentURL.standardizedFileURL.path) {
            pane.reload()
        }
    }

    // MARK: 휴지통으로 이동 (⌘⌫)
    // 완전 삭제가 아닙니다. Finder의 휴지통에서 "되돌려 놓기"로 살릴 수 있습니다.

    func moveToTrash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var failed: [String] = []
        var folders: [URL] = [currentURL]
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                folders.append(url.deletingLastPathComponent())
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        PaneModel.refreshPanes(showing: folders)
        if !failed.isEmpty {
            errorMessage = "휴지통으로 옮기지 못함: " + failed.joined(separator: ", ")
        }
    }

    // MARK: 이름 바꾸기

    @discardableResult
    func rename(_ url: URL, to rawName: String) -> URL? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldName = url.lastPathComponent
        guard name != oldName else { return url }

        if name.isEmpty {
            errorMessage = "이름을 비워 둘 수 없습니다."
            return nil
        }
        if name.contains("/") || name.contains(":") {
            errorMessage = "이름에 / 나 : 는 쓸 수 없습니다."
            return nil
        }
        if name.hasPrefix(".") {
            errorMessage = "점(.)으로 시작하는 이름은 숨김 파일이 되어 보이지 않게 됩니다."
            return nil
        }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        // 대소문자만 바꾸는 경우(a → A)는 같은 파일로 보이므로 "이미 있음" 검사에서 뺌
        let onlyCaseChange = name.lowercased() == oldName.lowercased()
        if !onlyCaseChange && FileManager.default.fileExists(atPath: dest.path) {
            errorMessage = "\"\(name)\" 이름의 항목이 이미 있습니다."
            return nil
        }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            errorMessage = "이름을 바꾸지 못했습니다: \(error.localizedDescription)"
            return nil
        }
        PaneModel.refreshPanes(showing: [currentURL])
        selection = [dest]
        anchor = dest
        return dest
    }

    // MARK: 새 폴더 (⇧⌘N)

    func makeNewFolder() -> URL? {
        let dest = uniqueDestination(currentURL.appendingPathComponent("새 폴더"))
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorMessage = "새 폴더를 만들지 못했습니다: \(error.localizedDescription)"
            return nil
        }
        PaneModel.refreshPanes(showing: [currentURL])
        selection = [dest]
        anchor = dest
        return dest
    }

    // MARK: 클립보드 (⌘C / ⌘V / ⌥⌘V / ⌥⌘C)

    // ⌘C: 파일을 클립보드에 담기 (Finder에도 붙여넣을 수 있음)
    func copyToPasteboard(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(urls.map { $0 as NSURL })
    }

    // ⌘V: 복사해서 붙여넣기 / ⌥⌘V: 옮기기
    func pasteFromPasteboard(move: Bool) {
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        let urls = objects.compactMap { $0 as? URL }
        guard !urls.isEmpty else { return }
        if move {
            moveIn(urls)
        } else {
            copyIn(urls, duplicateInSameFolder: true)
        }
    }

    // ⌥⌘C: 경로를 글자로 복사 (선택이 없으면 지금 폴더의 경로)
    func copyPaths(_ urls: [URL]) {
        let paths = (urls.isEmpty ? [currentURL] : urls).map { $0.path }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls.isEmpty ? [currentURL] : urls)
    }

    // MARK: 복사 (끌어다 놓기, ⌘V)
    // 원본은 그대로 남습니다. 같은 이름이 있으면 덮어쓰지 않고 "이름 2"로 저장합니다.
    // duplicateInSameFolder: 같은 폴더에 붙여넣으면 사본을 만듦(⌘V). 끌어다 놓기에서는 무시.

    func copyIn(_ sources: [URL], duplicateInSameFolder: Bool = false) {
        var failed: [String] = []
        for src in sources {
            if isSameFolder(src) && !duplicateInSameFolder { continue }
            if isInsideItself(src) {
                failed.append(src.lastPathComponent + "(자기 안으로는 복사할 수 없음)")
                continue
            }
            let dest = uniqueDestination(currentURL.appendingPathComponent(src.lastPathComponent))
            do {
                try FileManager.default.copyItem(at: src, to: dest)
            } catch {
                failed.append(src.lastPathComponent)
            }
        }
        PaneModel.refreshPanes(showing: [currentURL])
        if !failed.isEmpty {
            errorMessage = "복사 실패: " + failed.joined(separator: ", ")
        }
    }

    // MARK: 이동 (⌘ 누른 채 끌어다 놓기, ⌥⌘V)
    // 원본이 원래 자리에서 사라지고 이 칸의 폴더로 옮겨집니다.

    func moveIn(_ sources: [URL]) {
        var failed: [String] = []
        var folders: [URL] = [currentURL]
        for src in sources {
            if isSameFolder(src) { continue }
            if isInsideItself(src) {
                failed.append(src.lastPathComponent + "(자기 안으로는 옮길 수 없음)")
                continue
            }
            let dest = uniqueDestination(currentURL.appendingPathComponent(src.lastPathComponent))
            do {
                try FileManager.default.moveItem(at: src, to: dest)
                folders.append(src.deletingLastPathComponent())
            } catch {
                failed.append(src.lastPathComponent)
            }
        }
        PaneModel.refreshPanes(showing: folders)
        if !failed.isEmpty {
            errorMessage = "이동 실패: " + failed.joined(separator: ", ")
        }
    }

    private func isSameFolder(_ src: URL) -> Bool {
        src.deletingLastPathComponent().standardizedFileURL.path == currentURL.standardizedFileURL.path
    }

    // 폴더를 그 폴더 자신(또는 그 안의 폴더)으로 복사·이동하려는 경우
    private func isInsideItself(_ src: URL) -> Bool {
        let s = src.standardizedFileURL.path
        let here = currentURL.standardizedFileURL.path
        return here == s || here.hasPrefix(s + "/")
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
