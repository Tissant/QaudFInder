//
//  QaudFInderApp.swift
//  QaudFInder
//
//  Created by Testarossa on 11/13/26.
//

import SwiftUI
import AppKit

@main
struct QaudFInderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)   // 창을 칸 배치의 최소 크기보다 작게 줄일 수 없게
        .commands {
            SidebarCommands()      // 보기 메뉴의 "사이드바 가리기/보기" (⌃⌘S)
            GoCommands()           // 이동 메뉴
        }

        // 설정 창: 앱 메뉴 "설정…"(⌘,)이 자동으로 생김
        Settings {
            SettingsView()
        }
    }
}

// MARK: - 이동 메뉴 (Finder의 "이동" 메뉴와 같은 자리)

struct GoCommands: Commands {
    @FocusedValue(\.goToFolder) private var goToFolder
    @ObservedObject private var shortcuts = ShortcutStore.shared   // 설정에서 바꾼 단축키를 바로 반영

    var body: some Commands {
        CommandMenu("이동") {
            Button("폴더로 이동…") { goToFolder?.run() }
                .keyboardShortcut(shortcuts.primary(for: .goToFolder).flatMap(\.swiftUIShortcut))
                .disabled(goToFolder == nil)
        }
    }
}

extension KeyCombo {
    // SwiftUI 메뉴용 단축키로 바꾸기 (기능키 등 메뉴에 못 넣는 키는 nil)
    var swiftUIShortcut: KeyboardShortcut? {
        let key: KeyEquivalent
        switch keyCode {
        case 36: key = .return
        case 49: key = .space
        case 51: key = .delete
        case 117: key = .deleteForward
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        default:
            guard !isSpecialKey, let c = menuKey.first else { return nil }
            key = KeyEquivalent(c)
        }
        var mods: EventModifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        return KeyboardShortcut(key, modifiers: mods)
    }
}

// MARK: - 앱 종료 직전 확인: 복사·이동이 진행 중이면 물어봄

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ServiceSupport.register()          // 우클릭 메뉴에 "서비스" 붙이기
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard CopyQueue.shared.isBusy else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "복사·이동이 아직 진행 중입니다"
        alert.informativeText = "지금 종료하면 진행 중인 작업이 취소됩니다. 덜 복사된 항목은 휴지통으로 옮겨지고, 이미 끝난 항목은 그대로 남습니다."
        alert.addButton(withTitle: "계속 진행")
        alert.addButton(withTitle: "취소하고 종료")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }

        // 진행 중인 작업을 멈추고 정리가 끝나면 종료
        CopyQueue.shared.cancelAll {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
