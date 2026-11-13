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
        .commands {
            SidebarCommands()      // 보기 메뉴의 "사이드바 가리기/보기" (⌃⌘S)
        }
    }
}

// MARK: - 앱 종료 직전 확인: 복사·이동이 진행 중이면 물어봄

final class AppDelegate: NSObject, NSApplicationDelegate {
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
