//
//  QaudFInderApp.swift
//  QaudFInder
//
//  Created by Testarossa on 11/13/26.
//

import SwiftUI

@main
struct QaudFInderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            SidebarCommands()      // 보기 메뉴의 "사이드바 가리기/보기" (⌃⌘S)
        }
    }
}
