//
//  AppSettings.swift
//  QuadFinder — 설정 창(⌘,)에서 바꾸는 값 모음 (1.1.0)
//
//  모든 값은 이 맥의 앱 설정(UserDefaults)에만 저장합니다. 키는 "settings."으로 시작합니다.
//  기본값은 1.0의 동작과 같게 정해서, 설정을 건드리지 않으면 예전과 똑같이 동작합니다.
//
//  1.2.0: 시작할 때 칸 배치(지난번 그대로 / 이 배열로), 가로·세로 배열, 칸별 시작 폴더 6개
//  나중 버전에서 더할 설정: 풀고 난 원본 zip·숨김 파일 빼기·보조 압축 앱(1.4.0 압축)
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

    // 칸별 시작 폴더 (칸 번호 0~5 = 배열 미리보기의 1~6번). 새 창(⌘N), 지난번 상태가 없을 때, "이 배열로 시작"일 때 씀
    @Published var startFolders: [String] { didSet { save(startFolders, "startFolders") } }

    // 시작할 때 칸 배치: false = 지난번 배치 그대로, true = 이 배열로 시작(매번 칸별 시작 폴더로)
    @Published var startWithGrid: Bool { didSet { save(startWithGrid ? "grid" : "last", "startLayout") } }
    // 가로 배열(열 수)·세로 배열(줄 수) 1~3. 둘 다 3은 안 됨(최대 6칸)
    @Published var startColumns: Int {
        didSet {
            if startColumns == 3 && startRows == 3 { startRows = 2 }
            save(startColumns, "startColumns")
        }
    }
    @Published var startRows: Int {
        didSet {
            if startColumns == 3 && startRows == 3 { startColumns = 2 }
            save(startRows, "startRows")
        }
    }

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
        return ["Desktop", "Documents", "Downloads", "", "", ""].map {
            $0.isEmpty ? home.path : home.appendingPathComponent($0).path
        }
    }

    private init() {
        let s = UserDefaults.standard
        func value<T>(_ key: String, _ fallback: T) -> T { s.object(forKey: Self.prefix + key) as? T ?? fallback }

        let folders = value("startFolders", Self.defaultStartFolders)
        // 1.1.0까지는 4개 → 뒤에 기본값(홈 폴더) 2개를 붙여 6개로
        let defaults = Self.defaultStartFolders
        startFolders = folders.count <= defaults.count ? folders + defaults.dropFirst(folders.count) : defaults
        startWithGrid = value("startLayout", "last") == "grid"
        var cols = min(max(value("startColumns", 2), 1), 3)
        let rows = min(max(value("startRows", 2), 1), 3)
        if cols == 3 && rows == 3 { cols = 2 }
        startColumns = cols
        startRows = rows
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
        startWithGrid = false
        startColumns = 2
        startRows = 2
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
