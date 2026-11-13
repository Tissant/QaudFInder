//
//  SidebarModel.swift
//  QuadFinder — 사이드바 즐겨찾기 목록 (순서 포함, 앱을 껐다 켜도 기억)
//

import Foundation
import Combine

@MainActor
final class SidebarModel: ObservableObject {
    // 앱 전체에서 하나만 씀 (칸의 우클릭 메뉴 "사이드바에 추가"에서도 접근)
    static let shared = SidebarModel()

    @Published private(set) var favorites: [URL] = []

    private let key = "sidebar.favorites"

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: key) {
            favorites = saved.map { URL(fileURLWithPath: $0) }
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
        }
    }

    func contains(_ url: URL) -> Bool {
        favorites.contains { Self.samePath($0, url) }
    }

    // 폴더만 추가. 이미 있으면 무시. index가 없으면 맨 아래에.
    func add(_ urls: [URL], at index: Int? = nil) {
        var insertAt = min(index ?? favorites.count, favorites.count)
        for url in urls where Self.isFolder(url) && !contains(url) {
            favorites.insert(url.standardizedFileURL, at: insertAt)
            insertAt += 1
        }
        save()
    }

    func remove(at index: Int) {
        guard favorites.indices.contains(index) else { return }
        favorites.remove(at: index)
        save()
    }

    // 끌어서 순서 바꾸기: from 위치의 항목을 to 위치 "앞"으로
    func move(from: Int, to: Int) {
        guard favorites.indices.contains(from) else { return }
        let item = favorites.remove(at: from)
        let target = to > from ? to - 1 : to
        favorites.insert(item, at: min(max(target, 0), favorites.count))
        save()
    }

    private func save() {
        UserDefaults.standard.set(favorites.map { $0.path }, forKey: key)
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
