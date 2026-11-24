//
//  AppSettings.swift
//  QuadFinder — 설정 창(⌘,)에서 바꾸는 값 모음 (1.1.0)
//
//  모든 값은 이 맥의 앱 설정(UserDefaults)에만 저장합니다. 키는 "settings."으로 시작합니다.
//  기본값은 1.0의 동작과 같게 정해서, 설정을 건드리지 않으면 예전과 똑같이 동작합니다.
//
//  나중 버전에서 더할 설정: 시작할 때 칸 배치·최대 칸 수(1.2.0 자유 분할),
//  풀고 난 원본 zip·숨김 파일 빼기·보조 압축 앱(1.4.0 압축)
//

import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store = UserDefaults.standard
    private static let prefix = "settings."

    // 파일 목록을 다시 읽어야 하는 설정이 바뀌면 +1 (PaneModel이 보고 새로고침)
    @Published private(set) var listRevision = 0

    // MARK: 일반

    // 칸별 시작 폴더 (칸 0~3). 지난번 상태가 없을 때와 ⌘N으로 연 창에서 씀
    @Published var startFolders: [String] { didSet { save(startFolders, "startFolders") } }

    // MARK: 보기

    @Published var newViewMode: ViewMode { didSet { save(newViewMode.rawValue, "newViewMode") } }
    @Published var iconScale: Double { didSet { save(iconScale, "iconScale") } }          // 0.5 ~ 3
    @Published var gridSpacing: Double { didSet { save(gridSpacing, "gridSpacing") } }    // 0.5 ~ 1.5
    @Published var showThumbnails: Bool { didSet { save(showThumbnails, "showThumbnails") } }
    @Published var foldersFirst: Bool { didSet { save(foldersFirst, "foldersFirst"); listRevision += 1 } }
    @Published var showExtensions: Bool { didSet { save(showExtensions, "showExtensions"); listRevision += 1 } }

    // MARK: 파일 조작

    @Published var confirmTrash: Bool { didSet { save(confirmTrash, "confirmTrash") } }
    @Published var folderSize: Bool { didSet { save(folderSize, "folderSize"); listRevision += 1 } }
    // 칸끼리 끌어 놓을 때 기본 동작. true면 그냥 끌기 = 이동, ⌘ 누른 채 = 복사 (Finder에서 끌어온 파일은 항상 복사)
    @Published var dragDefaultMove: Bool { didSet { save(dragDefaultMove, "dragDefaultMove") } }

    // MARK: 사이드바

    @Published var cleanFavorites: Bool {
        didSet {
            save(cleanFavorites, "cleanFavorites")
            SidebarModel.shared.refresh()
        }
    }

    // MARK: 기본값 (1.0과 같은 동작)

    static var defaultStartFolders: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Desktop", "Documents", "Downloads", ""].map {
            $0.isEmpty ? home.path : home.appendingPathComponent($0).path
        }
    }

    private init() {
        let s = UserDefaults.standard
        func value<T>(_ key: String, _ fallback: T) -> T { s.object(forKey: Self.prefix + key) as? T ?? fallback }

        let folders = value("startFolders", Self.defaultStartFolders)
        startFolders = folders.count == 4 ? folders : Self.defaultStartFolders
        newViewMode = ViewMode(rawValue: value("newViewMode", ViewMode.list.rawValue)) ?? .list
        iconScale = min(max(value("iconScale", 1.0), 0.5), 3.0)
        gridSpacing = min(max(value("gridSpacing", 1.0), 0.5), 1.5)
        showThumbnails = value("showThumbnails", true)
        foldersFirst = value("foldersFirst", true)
        showExtensions = value("showExtensions", false)
        confirmTrash = value("confirmTrash", false)
        folderSize = value("folderSize", true)
        dragDefaultMove = value("dragDefaultMove", false)
        cleanFavorites = value("cleanFavorites", true)
    }

    private func save(_ value: Any, _ key: String) {
        store.set(value, forKey: Self.prefix + key)
    }

    // MARK: 초기화

    // 설정만 처음 상태로 (칸의 폴더·즐겨찾기는 그대로)
    func resetAll() {
        for key in store.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            store.removeObject(forKey: key)
        }
        startFolders = Self.defaultStartFolders
        newViewMode = .list
        iconScale = 1.0
        gridSpacing = 1.0
        showThumbnails = true
        foldersFirst = true
        showExtensions = false
        confirmTrash = false
        folderSize = true
        dragDefaultMove = false
        cleanFavorites = true
        ShortcutStore.shared.load()          // 단축키도 기본값으로 (위에서 settings.shortcuts를 지움)
    }
}
