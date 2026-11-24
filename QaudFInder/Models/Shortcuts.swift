//
//  Shortcuts.swift
//  QuadFinder — 단축키 목록과 사용자 변경 (1.1.0, 설정 창 "단축키" 탭)
//
//  - 바꿀 수 있는 단축키(ShortcutAction): QaudFInder가 직접 처리하는 것
//  - 고정 단축키(fixedShortcuts): macOS 기본 메뉴(⌘C·⌘V·⌘N 등)나 칸 이동(Tab·esc)처럼
//    바꾸면 헷갈리거나 macOS가 먼저 가져가는 것 → 목록에 보여 주기만 함
//  - 바꾼 값은 UserDefaults "settings.shortcuts"에만 저장 ("모든 설정 초기화"로 함께 초기화)
//  - 키는 키 위치 번호(keyCode)로 비교 → 한글 입력 상태에서도 똑같이 동작
//

import AppKit
import SwiftUI
import Combine

// MARK: - 키 조합 하나 (예: ⇧⌘N)

struct KeyCombo: Equatable, Codable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt          // NSEvent.ModifierFlags의 ⌘⇧⌥⌃만
    let char: String             // 화면 표시·메뉴용 글자 (소문자, 예: "n")

    static let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    init(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], char: String) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Self.relevant).rawValue
        self.char = char.lowercased()
    }

    // 입력 소스가 한글이어도 "ㅅ"이 아니라 키 위치의 영문 글자("t")로 기억 (Finder 메뉴 표시와 같게)
    init(event: NSEvent) {
        self.init(event.keyCode, event.modifierFlags,
                  char: Self.usKeys[event.keyCode] ?? event.charactersIgnoringModifiers ?? "")
    }

    // 키 위치 번호 → 영문 자판(ANSI) 글자
    static let usKeys: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k",
        37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u",
        9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
    ]

    // 예전에 한글 글자로 저장된 값도 영문으로 보이도록 키 위치로 다시 정함
    private var letter: String { Self.usKeys[keyCode] ?? char }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevant) == flags
    }

    // 특별한 키의 이름·메뉴 글자 (키 위치 번호 기준)
    private static let special: [UInt16: (name: String, menu: String)] = [
        36: ("↩", "\r"), 76: ("⌤", "\u{3}"), 49: ("Space", " "), 51: ("⌫", "\u{8}"),
        117: ("⌦", "\u{7f}"), 48: ("⇥", "\t"), 53: ("esc", "\u{1b}"),
        123: ("←", String(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        124: ("→", String(UnicodeScalar(NSRightArrowFunctionKey)!)),
        125: ("↓", String(UnicodeScalar(NSDownArrowFunctionKey)!)),
        126: ("↑", String(UnicodeScalar(NSUpArrowFunctionKey)!)),
        122: ("F1", ""), 120: ("F2", ""), 99: ("F3", ""), 118: ("F4", ""), 96: ("F5", ""), 97: ("F6", ""),
        98: ("F7", ""), 100: ("F8", ""), 101: ("F9", ""), 109: ("F10", ""), 103: ("F11", ""), 111: ("F12", ""),
    ]

    // 화면 표시: ⌃⌥⇧⌘ 순서 (macOS 메뉴와 같은 순서)
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + (Self.special[keyCode]?.name ?? letter.uppercased())
    }

    // 메뉴 항목의 keyEquivalent (기능키처럼 메뉴에 못 넣는 키는 빈 글자)
    var menuKey: String { Self.special[keyCode]?.menu ?? letter }

    var isSpecialKey: Bool { Self.special[keyCode] != nil }
    var isFunctionKey: Bool { (Self.special[keyCode]?.name ?? "").hasPrefix("F") }
}

// MARK: - 바꿀 수 있는 단축키

enum ShortcutAction: String, CaseIterable, Identifiable {
    case open, preview, rename, goUp, trash, newFolder, pasteMove, copyPath, toggleHidden, goToFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open:         return "열기"
        case .preview:      return "훑어보기"
        case .rename:       return "이름 바꾸기"
        case .goUp:         return "상위 폴더로"
        case .trash:        return "휴지통으로 이동"
        case .newFolder:    return "새 폴더"
        case .pasteMove:    return "여기로 옮기기 (붙여넣기)"
        case .copyPath:     return "경로 복사"
        case .toggleHidden: return "숨김 파일 보기/가리기"
        case .goToFolder:   return "폴더로 이동 (경로 입력)"
        }
    }

    // 기본 단축키. 첫 번째가 메뉴·설정 창에 보이는 대표 키, 나머지는 함께 동작하는 키
    var defaults: [KeyCombo] {
        switch self {
        case .open:         return [KeyCombo(31, .command, char: "o"), KeyCombo(125, .command, char: "")]
        case .preview:      return [KeyCombo(49, char: " ")]
        case .rename:       return [KeyCombo(36, char: "\r"), KeyCombo(76, char: "")]
        case .goUp:         return [KeyCombo(126, .command, char: "")]
        case .trash:        return [KeyCombo(51, .command, char: "")]
        case .newFolder:    return [KeyCombo(45, [.command, .shift], char: "n")]
        case .pasteMove:    return [KeyCombo(9, [.command, .option], char: "v")]
        case .copyPath:     return [KeyCombo(8, [.command, .option], char: "c")]
        case .toggleHidden: return [KeyCombo(47, [.command, .shift], char: ".")]
        case .goToFolder:   return [KeyCombo(5, [.command, .shift], char: "g")]
        }
    }
}

// MARK: - 고정 단축키 (보여 주기만)

struct FixedShortcut: Identifiable {
    let keys: String
    let title: String
    var id: String { keys + title }
}

let fixedShortcuts: [FixedShortcut] = [
    .init(keys: "⌘C", title: "복사"),
    .init(keys: "⌘V", title: "붙여넣기 (복사해서)"),
    .init(keys: "⌘A", title: "모두 선택"),
    .init(keys: "⇥ / ⇧⇥", title: "다음 칸 / 이전 칸"),
    .init(keys: "esc", title: "병합 선택 취소, 입력 취소"),
    .init(keys: "←→↑↓", title: "선택 이동 (리스트 보기 ← → 는 폴더 접기·펼치기)"),
    .init(keys: "⌘N", title: "새 창"),
    .init(keys: "⌘W", title: "창 닫기"),
    .init(keys: "⌃⌘S", title: "사이드바 보기/가리기"),
    .init(keys: "⌘,", title: "설정"),
    .init(keys: "⌘ + 위쪽 막대 클릭", title: "병합할 칸 고르기"),
    .init(keys: "⌘ + 아이콘 보기 버튼", title: "아이콘 크기·격자 간격"),
    .init(keys: "경로 더블클릭", title: "경로 입력"),
    .init(keys: "⌘ / ⌥ + 끌기", title: "이동으로 바꾸기 / 그 폴더로 칸 이동"),
]

// macOS나 고정 단축키가 이미 쓰는 조합 → 새 단축키로 고를 수 없음
private let reservedCombos: [(UInt16, NSEvent.ModifierFlags)] = [
    (8, .command), (9, .command), (7, .command), (0, .command), (6, .command), (6, [.command, .shift]),
    (45, .command), (13, .command), (12, .command), (4, .command), (46, .command), (43, .command),
    (1, [.command, .control]), (3, [.command, .control]), (4, [.command, .option]), (48, []), (48, .shift), (53, []),
]

// MARK: - 저장소

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    private let key = "settings.shortcuts"
    @Published private(set) var custom: [String: KeyCombo] = [:]     // 바꾼 것만

    private init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            custom = saved
        } else {
            custom = [:]
        }
    }

    // 지금 동작하는 키들 (바꿨으면 그 하나, 아니면 기본 키 전부)
    func combos(for action: ShortcutAction) -> [KeyCombo] {
        custom[action.rawValue].map { [$0] } ?? action.defaults
    }

    func primary(for action: ShortcutAction) -> KeyCombo? { combos(for: action).first }

    func isCustom(_ action: ShortcutAction) -> Bool { custom[action.rawValue] != nil }

    func action(for event: NSEvent) -> ShortcutAction? {
        ShortcutAction.allCases.first { a in combos(for: a).contains { $0.matches(event) } }
    }

    // 새 단축키로 정하기. 쓸 수 없으면 이유를 돌려줌
    func set(_ combo: KeyCombo, for action: ShortcutAction) -> String? {
        let flags = combo.flags
        let hasMainModifier = !flags.intersection([.command, .control, .option]).isEmpty
        if !hasMainModifier && !(combo.isSpecialKey && [36, 76, 49, 51].contains(combo.keyCode)) && !combo.isFunctionKey {
            return "글자 키만으로는 쓸 수 없습니다(이름으로 찾기와 겹침). ⌘, ⌥, ⌃ 중 하나와 함께 눌러 주세요."
        }
        if reservedCombos.contains(where: { $0.0 == combo.keyCode && $0.1 == flags }) {
            return "\(combo.display)는 macOS나 고정 단축키가 이미 쓰고 있습니다."
        }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && combos(for: $0).contains { $0.keyCode == combo.keyCode && $0.flags == flags } }) {
            return "\(combo.display)는 이미 '\(other.title)'에 쓰고 있습니다."
        }
        custom[action.rawValue] = combo
        save()
        return nil
    }

    func reset(_ action: ShortcutAction) {
        custom[action.rawValue] = nil
        save()
    }

    func resetAll() {
        custom = [:]
        save()
    }

    private func save() {
        if custom.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
