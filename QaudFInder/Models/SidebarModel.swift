//
//  SidebarModel.swift
//  QuadFinder — 사이드바 즐겨찾기 목록 (순서 포함, 앱을 껐다 켜도 기억)
//
//  1.1.0부터 폴더를 "경로 글자"가 아니라 북마크(macOS가 폴더 자체를 기억하는 정보)로 저장합니다.
//  - 이름을 바꾸거나 옮긴 폴더도 따라감
//  - 사라진 폴더 자동 정리(설정에서 끌 수 있음):
//      휴지통으로 간 폴더, 연결된 디스크에서 없어진 폴더 → 목록에서 뺌 (폴더 자체는 건드리지 않음)
//      연결이 끊긴 외장 디스크·NAS의 폴더 → 지우지 않고 흐리게 표시 (다시 연결하면 그대로)
//  - 예전(1.0) 목록 "sidebar.favorites"는 처음 켤 때 자동으로 옮기고, 지우지 않고 남겨 둠
//

import Foundation
import AppKit
import Combine

@MainActor
final class SidebarModel: ObservableObject {
    // 앱 전체에서 하나만 씀 (칸의 우클릭 메뉴 "사이드바에 추가"에서도 접근)
    static let shared = SidebarModel()

    @Published private(set) var favorites: [URL] = []
    @Published private(set) var offline: Set<String> = []     // 연결 안 된 디스크의 즐겨찾기 (경로)
    @Published private(set) var notice: String? = nil         // 창 아래쪽에 잠깐 띄울 안내 ("○○를 정리했습니다" 등)

    private var bookmarks: [Data?] = []                       // favorites와 같은 순서

    private let key = "sidebar.bookmarks"
    private let pathKey = "sidebar.favorites"                 // 예전 형식 / 북마크를 못 만들 때 대비용 경로

    private init() {
        let store = UserDefaults.standard
        if let data = store.array(forKey: key) as? [Data], let paths = store.stringArray(forKey: pathKey),
           data.count == paths.count {
            // 1.1.0 형식: 빈 Data는 "북마크 없음"
            favorites = paths.map { URL(fileURLWithPath: $0) }
            bookmarks = data.map { $0.isEmpty ? nil : $0 }
        } else if let paths = store.stringArray(forKey: pathKey) {
            // 1.0에서 올라온 경우: 경로 목록을 북마크로 옮김
            favorites = paths.map { URL(fileURLWithPath: $0) }
            bookmarks = favorites.map { Self.makeBookmark($0) }
            save()
        } else {
            // 처음 실행: 기본 즐겨찾기
            let home = FileManager.default.homeDirectoryForCurrentUser
            favorites = [
                home.appendingPathComponent("Desktop"),
                home.appendingPathComponent("Documents"),
                home.appendingPathComponent("Downloads"),
                home,
                URL(fileURLWithPath: "/Applications"),
            ]
            bookmarks = favorites.map { Self.makeBookmark($0) }
            save()
        }
        refresh()

        // 다른 앱(Finder 등)에서 폴더를 지우거나 옮긴 뒤 이 앱으로 돌아오면 다시 확인
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SidebarModel.shared.refresh() }
        }
    }

    func contains(_ url: URL) -> Bool {
        favorites.contains { Self.samePath($0, url) }
    }

    // 즐겨찾기를 눌렀을 때: 열 수 있으면 true. 없으면 정리하거나 안내하고 false
    func canOpen(_ url: URL) -> Bool {
        if Self.isFolder(url) { return true }
        refresh()
        if isOffline(url) {
            notice = "'\(FileManager.default.displayName(atPath: url.path))' 폴더가 있는 디스크가 연결되어 있지 않습니다."
        }
        return false
    }

    func isOffline(_ url: URL) -> Bool {
        offline.contains(url.standardizedFileURL.path)
    }

    // 폴더만 추가. 이미 있으면 무시. index가 없으면 맨 아래에.
    func add(_ urls: [URL], at index: Int? = nil) {
        var insertAt = min(index ?? favorites.count, favorites.count)
        for url in urls where Self.isFolder(url) && !contains(url) {
            let clean = url.standardizedFileURL
            favorites.insert(clean, at: insertAt)
            bookmarks.insert(Self.makeBookmark(clean), at: insertAt)
            insertAt += 1
        }
        save()
    }

    func remove(at index: Int) {
        guard favorites.indices.contains(index) else { return }
        favorites.remove(at: index)
        bookmarks.remove(at: index)
        save()
    }

    // 끌어서 순서 바꾸기: from 위치의 항목을 to 위치 "앞"으로
    func move(from: Int, to: Int) {
        guard favorites.indices.contains(from) else { return }
        let item = favorites.remove(at: from)
        let mark = bookmarks.remove(at: from)
        let target = min(max(to > from ? to - 1 : to, 0), favorites.count)
        favorites.insert(item, at: target)
        bookmarks.insert(mark, at: target)
        save()
    }

    // 설정 창 "즐겨찾기 초기화": 처음 설치했을 때의 5개(데스크탑·문서·다운로드·홈·응용 프로그램)로
    func resetToDefaults() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        favorites = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home,
            URL(fileURLWithPath: "/Applications"),
        ]
        bookmarks = favorites.map { Self.makeBookmark($0) }
        offline = []
        save()
    }

    // MARK: 사라진 즐겨찾기 확인 (앱 시작, 앱으로 돌아올 때, 휴지통으로 보낸 뒤, 없는 항목을 눌렀을 때)

    func refresh() {
        var newFavorites: [URL] = []
        var newBookmarks: [Data?] = []
        var newOffline: Set<String> = []
        var removed: [String] = []
        let autoClean = AppSettings.shared.cleanFavorites

        for (i, url) in favorites.enumerated() {
            switch Self.check(url, bookmark: bookmarks[i]) {
            case .available(let now, let freshBookmark):
                newFavorites.append(now)
                newBookmarks.append(freshBookmark ?? bookmarks[i])
            case .offline:
                newFavorites.append(url)
                newBookmarks.append(bookmarks[i])
                newOffline.insert(url.standardizedFileURL.path)
            case .gone:
                if autoClean {
                    removed.append(FileManager.default.displayName(atPath: url.path))
                } else {
                    newFavorites.append(url)
                    newBookmarks.append(bookmarks[i])
                    newOffline.insert(url.standardizedFileURL.path)   // 끈 경우엔 흐리게만
                }
            }
        }

        let changed = newFavorites != favorites || !removed.isEmpty
        if changed {
            favorites = newFavorites
            bookmarks = newBookmarks
            save()
        }
        if newOffline != offline { offline = newOffline }
        if !removed.isEmpty {
            notice = removed.count == 1
                ? "사라진 폴더 '\(removed[0])'를 즐겨찾기에서 정리했습니다."
                : "사라진 폴더 \(removed.count)개를 즐겨찾기에서 정리했습니다."
        }
    }

    private enum State {
        case available(URL, Data?)     // 지금 위치(이름이 바뀌었으면 새 위치), 새로 만든 북마크
        case offline                   // 디스크가 연결되어 있지 않음 → 남겨 둠
        case gone                      // 휴지통으로 갔거나 연결된 디스크에서 없어짐 → 정리 대상
    }

    private static func check(_ url: URL, bookmark: Data?) -> State {
        // 1) 북마크로 지금 위치 찾기 (디스크를 마운트하거나 창을 띄우지 않음)
        if let bookmark {
            var stale = false
            if let found = try? URL(resolvingBookmarkData: bookmark,
                                    options: [.withoutUI, .withoutMounting],
                                    relativeTo: nil, bookmarkDataIsStale: &stale) {
                let now = found.standardizedFileURL
                if isInTrash(now) { return .gone }
                if isFolder(now) {
                    let moved = now.path != url.standardizedFileURL.path
                    return .available(now, (stale || moved) ? makeBookmark(now) : nil)
                }
            }
        }
        // 2) 북마크가 없거나 못 찾음 → 원래 경로 확인
        if isFolder(url) {
            return .available(url.standardizedFileURL, bookmark == nil ? makeBookmark(url) : nil)
        }
        // 3) 경로도 없음: 그 폴더가 있던 디스크가 연결되어 있는지
        return volumeIsMissing(url) ? .offline : .gone
    }

    // /Volumes/디스크이름/... 인데 /Volumes/디스크이름 자체가 없으면 "연결 안 됨"
    private static func volumeIsMissing(_ url: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents      // ["/", "Volumes", "디스크", ...]
        guard parts.count >= 3, parts[1] == "Volumes" else { return false }
        let volume = "/Volumes/" + parts[2]
        return !FileManager.default.fileExists(atPath: volume)
    }

    private static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash") || url.pathComponents.contains(".Trashes")
    }

    // MARK: 저장

    private func save() {
        let store = UserDefaults.standard
        store.set(favorites.map { $0.path }, forKey: pathKey)
        store.set(bookmarks.map { $0 ?? Data() }, forKey: key)
    }

    private static func makeBookmark(_ url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func samePath(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.path == b.standardizedFileURL.path
    }

    // 들어갈 수 있는 폴더인지 (.app 같은 패키지는 제외)
    static func isFolder(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
    }
}
